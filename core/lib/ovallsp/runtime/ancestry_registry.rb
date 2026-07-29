# frozen_string_literal: true

require "set"

module Ovallsp
  module Runtime
    # Three outcomes, and the difference between them is the whole point:
    #
    # - `:loaded` -- the class is loaded, and `foreign_ancestors` are the
    #   ones it carries beyond the running Object's;
    # - `:external` -- not loaded, but registered for autoload from a file
    #   the workspace does not own, which settles the question outright;
    # - `:absent` -- the application does not know this name, or knows it
    #   only from a workspace file it has not loaded. Both leave the static
    #   reading standing, which is right for a class the workspace owns.
    #
    # `:absent` is a real answer, not a missing one, and is why a name the
    # application cannot place does not defer forever.
    ClassAncestry = Data.define(:status, :foreign_ancestors)

    # What the running application says a class's ancestors really are.
    #
    # The unknown-method check reports only on a receiver whose ancestry
    # the workspace fully declares, which it tests by walking the static
    # chain to BasicObject. Reopening a class that lives in a gem is
    # syntactically identical to defining it, so that walk succeeds and
    # the class looks complete when it is not -- every Rails application's
    # `test/test_helper.rb` reopens `ActiveSupport::TestCase` this way
    # (docs/design/tasks/024-deferred-review-findings.md, 024.R5).
    #
    # Only the running application can tell the two apart, and it is asked
    # in the one way that actually answers: for the class's ancestors,
    # measured against that same process's own `Object.ancestors`.
    # `Object.const_source_location` was tried first and cannot do it --
    # it reports where a constant was *registered*, which for every
    # Zeitwerk-managed class in `app/` is one line inside Zeitwerk itself,
    # and for every `ActiveSupport::Autoload` constant is one line inside
    # Active Support. The disproof, and the two other rejected approaches,
    # are recorded in 024.R5.
    #
    # Written from a background thread (Server's Agent refresh) while the
    # main thread reads it during diagnostics, so every access takes the
    # mutex.
    class AncestryRegistry
      # An Agent that is reachable but has stopped answering is the one
      # state nothing else notices, so the questions give up on it. Counted
      # rather than tripped on the first failure, because a single timeout
      # during a busy boot is ordinary.
      #
      # The count lives here, with the epoch it belongs to, rather than on
      # the caller: kept separately it survived #reset, so a fresh Agent
      # inherited the previous one's failures and the first timeout against
      # a perfectly healthy application re-tripped the limit for good.
      FAILURE_LIMIT = 3

      def initialize
        @entries = {}
        @pending = Set.new
        @active = false
        @gave_up = false
        @failures = 0
        @epoch = 0
        @mutex = Mutex.new
      end

      # Whether there is a running application to ask at all. An untrusted
      # workspace, or a project with no Rails app, never has one -- so the
      # check must not wait for an answer there, or it would go silent
      # permanently rather than fall back to the static reading.
      #
      # Deliberately not derived from "has answered at least once": the
      # first question can only be asked while no answer exists yet, so
      # that reading would never let a single question through.
      def active? = @mutex.synchronize { @active }

      # A no-op once the caller has given up on this Agent. Diagnostics
      # call this on every publish, so without that a give-up would be
      # undone by the very next keystroke and the fallback would never
      # take hold -- the check would go back to deferring to an Agent
      # already known not to answer.
      def activate!
        @mutex.synchronize do
          next if @gave_up

          @active = true
        end
      end

      # Called when the Agent is gone for good (crash-looped past its retry
      # budget), so the check stops deferring to an answer that can never
      # arrive. Answers already installed are kept -- they were true about
      # the application that was running, and dropping them would turn a
      # dead Agent into a fresh crop of false positives.
      #
      # Moves the epoch for the same reason #reset does: a fetch that was
      # already in flight when the Agent died would otherwise land, and
      # #install marks the registry active, quietly undoing this and
      # leaving the check deferring forever to a process that is gone.
      def deactivate!
        @mutex.synchronize do
          @active = false
          @gave_up = true
          @epoch += 1
        end
      end

      def entry(name) = @mutex.synchronize { @entries[name] }

      # Records a fetch that came back with nothing, and answers whether
      # that was the failure that made the caller give up. Returns false
      # for a failure belonging to an Agent that has since been replaced:
      # a retired manager refuses requests, and counting that as evidence
      # the application is unresponsive would let three ordinary restarts
      # -- one per `Gemfile.lock` save -- disable the check for good.
      def note_failure(epoch:)
        @mutex.synchronize do
          next false if epoch != @epoch

          @failures += 1
          next false if @failures < FAILURE_LIMIT

          @active = false
          @gave_up = true
          @epoch += 1
          true
        end
      end

      # The epoch a caller must still be in for its answers to be accepted.
      # `#reset` moves it, so a fetch that was in flight against a process
      # that has since been replaced can be told apart from a current one.
      def epoch = @mutex.synchronize { @epoch }

      # `classes` maps a name to the Agent's answer for it: a hash with
      # `ancestors`, a hash with `definedOutsideWorkspace`, or nil.
      # Merged rather than swapped: answers are gathered a few names at a
      # time, as the check meets receivers it would otherwise report on.

      # `epoch:` is checked inside the same lock that installs, which is
      # what makes discarding a stale answer airtight: checking it outside
      # left a window where #reset could land between the check and the
      # write, and an answer about the dead process would then stay for the
      # session, since answered names are never re-asked.
      def install(object_ancestors:, classes:, epoch: nil)
        baseline = Array(object_ancestors).map(&:to_s).to_set

        @mutex.synchronize do
          next if epoch && epoch != @epoch

          classes.each do |name, ancestors|
            key = name.to_s
            @entries[key] = build_entry(key, ancestors, baseline)
            @pending.delete(key)
          end
          # An answer is itself proof there is something to ask, and that
          # the Agent is answering -- so the failure streak starts over.
          @active = true
          @failures = 0
        end
      end

      # Asks about a name the next drain will carry to the Agent. Already
      # answered names are dropped here rather than at the call site: the
      # check meets the same receiver on every keystroke, and re-asking a
      # name the Agent has already settled would never stop.
      def request(name)
        key = name.to_s
        @mutex.synchronize do
          next if @entries.key?(key)

          @pending << key
        end
      end

      def pending? = @mutex.synchronize { !@pending.empty? }

      def drain_pending
        @mutex.synchronize { @pending.to_a.tap { @pending = Set.new } }
      end

      # A restarted Agent may be a genuinely different application -- a
      # changed Gemfile, a different environment. Ancestors cannot change
      # without a restart, which is exactly why a restart must drop them.
      def reset
        @mutex.synchronize do
          @entries = {}
          @pending = Set.new
          @active = false
          # A restart is a new application, and neither the reason the
          # previous one was given up on nor its failures carry over.
          @gave_up = false
          @failures = 0
          @epoch += 1
        end
      end

      private

      # An application that mixes into Object -- Active Support mixes in
      # four modules, and JSON another -- gives every class those
      # ancestors, so they are evidence about the application, not about
      # this class. Subtracting the same process's own Object.ancestors
      # calibrates that away without maintaining a list of what to expect.
      def build_entry(name, answer, baseline)
        return ClassAncestry.new(status: :absent, foreign_ancestors: []) unless answer.is_a?(Hash)
        if answer[:definedOutsideWorkspace] || answer["definedOutsideWorkspace"]
          return ClassAncestry.new(status: :external, foreign_ancestors: [])
        end

        ancestors = answer[:ancestors] || answer["ancestors"]
        return ClassAncestry.new(status: :absent, foreign_ancestors: []) if ancestors.nil?

        foreign = Array(ancestors).map(&:to_s).reject { |a| a == name || baseline.include?(a) }
        ClassAncestry.new(status: :loaded, foreign_ancestors: foreign.freeze)
      end
    end
  end
end
