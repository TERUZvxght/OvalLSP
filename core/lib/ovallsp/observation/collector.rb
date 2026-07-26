# frozen_string_literal: true

require "set"
require_relative "type_normalizer"
require_relative "fingerprint"
require_relative "observed_signature"
require_relative "../index/symbol_id"
require_relative "../types"

module Ovallsp
  module Observation
    # TracePoint-based collector, meant to run *inside* the isolated
    # observation runner process (Observation::Runner), never in Core
    # itself -- installing a global TracePoint in the same process
    # serving LSP requests would slow down and destabilize every other
    # feature for the whole session, not just the opt-in observation run
    # ("production process injection" is explicitly out of scope).
    #
    # Only ever reads, from an observed call: the method's own identity
    # (owner/name/kind), its parameters' and return value's *class*
    # (never the value itself -- TypeNormalizer never calls #inspect/
    # #to_s), and whether the call happened at all. Never reads argument
    # names' string contents, SQL, env vars, or file contents ("保存禁止"
    # -- docs/design/tasks/019-runtime-observation.md).
    class Collector
      # `raise_epoch` is the value of #current_raise_epoch when this frame
      # was pushed; #return_type_for compares it against the epoch at
      # `:return` time to tell a real `nil` return from a frame CRuby
      # abandoned because an exception unwound it (see its own docs).
      Frame = Struct.new(:symbol_id, :fingerprint, :param_types, :raise_epoch)
      private_constant :Frame

      def initialize(workspace_root:)
        @workspace_root = File.realpath(workspace_root)
        @mutex = Mutex.new
        @aggregates = {}
        # Per-instance so two Collectors in one process can't share a
        # stack; see #current_stack for why this is fiber-local storage
        # rather than a Hash this object owns.
        @stack_key = :"ovallsp_observation_stack_#{object_id}"
        # Counts `:raise` events on this fiber; see #return_type_for.
        # Fiber-local for exactly the reason the stack is: an exception
        # raised on one fiber never unwinds another's frames.
        @raise_epoch_key = :"ovallsp_observation_raise_epoch_#{object_id}"
        # `[defined_class, method_id]` -> the workspace-eligibility check,
        # symbol_id, fingerprint (re-hashes the *whole* source file --
        # deliberately coarse, see Fingerprint's own docs), and parameter
        # name list -- every one of which is invariant across repeated
        # calls to the *same* method within one run. Recomputing this
        # (in particular the SHA256 file digest) on every single `:call`
        # event made a tight loop calling one method thousands of times
        # pay for thousands of redundant full-file hashes; caught by
        # this module's own overhead regression test
        # (spec/ovallsp/observation/overhead_spec.rb).
        #
        # Deliberately neither pruned nor mutex-guarded, unlike the call
        # stacks below (round 20) -- checked again in round 21 and left
        # alone on purpose. It is bounded by construction (one entry per
        # method that actually exists in the process, not per call, per
        # thread, or per run), and it is a pure memoization of a
        # deterministic function of its own key, so the worst a lost or
        # duplicated concurrent write can cost is recomputing one entry.
        # A lock on the `:call` path would be paid by every traced call
        # in the user's suite to buy nothing.
        #
        # Also deliberately never invalidated, checked in round 22. A
        # `method_id` is an interned Symbol, so redefining a method
        # (`class_eval { def m; end }` over an already-observed `m`)
        # reuses this exact key and keeps serving the *old* definition's
        # symbol_id, fingerprint and parameter names. The symbol_id is
        # `[kind, owner, name]` and so is unchanged by any redefinition,
        # and a stale parameter-name list degrades to Types::UNKNOWN
        # (#positional_param_types rescues the failed
        # `local_variable_get`) -- i.e. under-collection, which is this
        # module's stated preference. `prepend` and `alias_method`, the
        # two ways real code patches a method, both produce a *different*
        # `defined_class`/`method_id` and so a different key, and the
        # observation run is a single short-lived process. Invalidating
        # would mean an `instance_method(...).source_location` on every
        # traced `:call`, paid by the whole suite, to correct a case that
        # only ever loses evidence.
        @method_cache = {}
      end

      def start
        @trace = TracePoint.new(:call, :return, :raise) { |tp| handle(tp) }
        @trace.enable
      end

      def stop
        @trace&.disable
      end

      def results(run_id:)
        now = Time.now
        @mutex.synchronize do
          @aggregates.map do |symbol_id, agg|
            ObservedSignature.new(
              symbol_id: symbol_id,
              parameter_types: agg[:param_type_sets].map { |set| Types.normalize_union(set.to_a) },
              return_type: Types.normalize_union(agg[:return_type_set].to_a),
              samples: agg[:samples],
              run_id: run_id,
              code_fingerprint: agg[:fingerprint],
              created_at: now
            )
          end
        end
      end

      private

      # A plugin/library's own bug must never take down the actual test
      # run this is silently riding along with -- every event is fully
      # isolated from every other.
      def handle(tp)
        case tp.event
        when :call then handle_call(tp)
        when :return then handle_return(tp)
        when :raise then handle_raise(tp)
        end
      rescue StandardError
        nil
      end

      # Pushes an entry for *every* `:call`, not only for the ones being
      # recorded -- the frame slot is simply nil for a method outside the
      # workspace (found by an independent review, round 20).
      #
      # Pushing only workspace calls while #handle_return popped on every
      # `:return` left the stack unbalanced by construction, and TracePoint
      # fires `:call`/`:return` for every *Ruby-defined* method, gem and
      # stdlib included. So the first non-workspace Ruby method a workspace
      # method called -- `n.to_s` is C and invisible, but any
      # ActiveRecord/ActiveSupport/rspec helper is not, which in a real
      # Rails app is essentially every method body -- returned first and
      # popped the *caller's* frame, recording the callee's return value
      # against the caller's symbol_id. The workspace method's own
      # `:return` then found an empty stack and recorded nothing at all.
      #
      # Reproduced before the fix on a two-file workspace: `App2#label`,
      # which calls one non-workspace method and then returns `n.to_s`,
      # was recorded with `return=Array` (the callee's value) instead of
      # `String`. That evidence is what Server#show_type_evidence and
      # LocalInferencer hand the user as observed types, so the feature
      # was reporting a confidently wrong type for the majority of real
      # methods rather than merely observing fewer of them.
      #
      # Every entry now carries the identity of the method it belongs to
      # and #unwind_to pops by *matching* that identity rather than
      # trusting position, which additionally makes the stack self-healing
      # -- see its own docs for the two ways TracePoint legitimately
      # delivers a `:return` with no `:call` of its own to match.
      def handle_call(tp)
        key, info = cached_method_info(tp)
        frame = info && Frame.new(info[:symbol_id], info[:fingerprint],
                                  positional_param_types(tp, info[:param_names]),
                                  current_raise_epoch)
        current_stack.push(key, frame)
      end

      # Returns `[key, info]`, where `key` is the `[defined_class,
      # method_id]` identity #handle_call pushes and #unwind_to matches on.
      # The key is handed back rather than rebuilt per call site because
      # the cache lookup has to allocate it anyway.
      def cached_method_info(tp)
        key = [tp.defined_class, tp.method_id]
        return [key, @method_cache[key]] if @method_cache.key?(key)

        [key, @method_cache[key] = compute_method_info(tp)]
      end

      def compute_method_info(tp)
        method_obj = defined_method(tp)
        return nil unless method_obj && workspace_method?(method_obj)

        symbol_id = symbol_id_for(tp)
        return nil unless symbol_id

        {
          symbol_id: symbol_id,
          fingerprint: fingerprint_for(method_obj),
          param_names: positional_param_names(method_obj)
        }
      end

      def handle_return(tp)
        frame = unwind_to(tp)
        return unless frame

        record(frame, return_type: return_type_for(tp, frame))
      end

      # CRuby fires a `:return` event for a method that never returned at
      # all -- one an exception unwound past -- and reports its
      # `return_value` as `nil`, indistinguishable at the event itself
      # from a method that genuinely evaluated to `nil` (found by an
      # independent review, round 21; verified on ruby 3.4.7).
      #
      # Round 20's `:raise` handling only closed out the frame of the
      # method the raise happened *in* (round 22 removed that close-out
      # entirely -- see #handle_raise). Every frame between that one and
      # whichever frame rescues is abandoned without a `:raise` of its
      # own, and each of those still gets this `nil`-valued `:return`. So
      # `def find_it; Model.find(id); end`, a method that on this call
      # raised RecordNotFound and returned nothing, was recorded as
      # "returns nil" -- and `nil` in an observed return union is exactly
      # the signal a user acts on, surfaced verbatim by
      # `ovallsp/showTypeEvidence` (`returnType: "User | nil"`). That
      # breaks this module's own stated contract ("a call that never
      # returned must never contribute a fabricated return type"), which
      # before this round held only for a method that raised *directly*.
      #
      # A non-nil `return_value` proves a normal return -- an abandoned
      # frame's is always `nil` -- so only a `nil` needs qualifying, and
      # it is trusted exactly when no `:raise` happened on this fiber
      # during the frame's own lifetime. Frames pushed *after* the raise
      # (an `ensure` body's own calls, which run mid-unwind) carry the
      # current epoch and so stay trusted, which a plain "an exception is
      # in flight" flag would have got wrong.
      #
      # Accepted, deliberately one-directional residue: a frame that was
      # already on the stack when some exception was raised and rescued
      # below it, and that then genuinely returns `nil`, loses that one
      # `nil` observation (`def f; g rescue nil; end`). This module's
      # documented policy is that under-collecting beats fabricating --
      # Store's authority policy already treats a missing return type as
      # "no confirmed evidence", never as "returns nothing" -- and the
      # sample is still counted either way.
      #
      # The opposite residue -- a frame abandoned with no `:raise` at all,
      # whose fabricated `nil` therefore still gets trusted -- is real and
      # deliberately uncorrected, because CRuby offers nothing to key on.
      # `throw`, `break`, and a non-local `return` out of a block all end
      # a frame with the same bare `nil`-valued `:return` and no other
      # event (verified on ruby 3.4.7), and so does `Thread#kill` on a
      # thread parked inside a workspace method -- measured in round 22:
      # `call`, then `return ret=nil`, no `:raise` anywhere on that
      # thread. Distinguishing any of them would need `:c_call`/
      # `:b_return` in the TracePoint, which fire for every C method and
      # every block return respectively and would not survive this
      # module's own overhead budget (overhead_spec.rb). All four are far
      # rarer in application code than a raise, and all four are bounded
      # to one fabricated `nil` in one method's union rather than the
      # systematic misreporting rounds 20-22 each fixed.
      def return_type_for(tp, frame)
        value = tp.return_value
        return TypeNormalizer.normalize(value) unless value.nil?
        return nil unless frame.raise_epoch == current_raise_epoch

        Types::NIL
      end

      # Pops the entry belonging to the method this `:return` event is
      # actually for, discarding anything still stacked above it, and
      # returns its frame (nil when that method wasn't one being
      # recorded). Returns nil, leaving the stack untouched, when no entry
      # matches at all. `:return` is the only caller: round 22 made it the
      # single close-out path, since CRuby fires one for every `:call`,
      # abandoned frames included.
      #
      # Matching rather than a bare `pop` is what makes the stack
      # self-healing, and both ways it can legitimately desynchronize are
      # reachable in an ordinary suite:
      #
      # 1. Calls already in flight when #start ran. Harness installs this
      #    from a `-r` require, so every frame between `main` and that
      #    require -- RubyGems' and Bundler's own loaders, at minimum --
      #    fires a `:return` whose `:call` predates the TracePoint. A bare
      #    `pop` treated each of those as "the innermost recorded call
      #    just returned".
      # 2. An exception unwinding several frames. `:raise` fires once, at
      #    the raise site; the frames it unwinds past never get a `:return`
      #    of their own, so they stay stacked until something below them
      #    returns. Slicing everything above the match is what clears them.
      #
      # The match is at the top of the stack on the overwhelmingly common
      # path (call returns, nothing intervened), so the scan is O(1) there
      # and only walks on the two paths above.
      def unwind_to(tp)
        stack = current_stack
        defined_class = tp.defined_class
        method_id = tp.method_id

        index = stack.size - 2
        while index >= 0
          key = stack[index]
          if key[0].equal?(defined_class) && key[1] == method_id
            frame = stack[index + 1]
            stack.slice!(index, stack.size - index)
            return frame
          end
          index -= 2
        end
        nil
      end

      # `:raise` closes out no frame at all. It only bumps the epoch
      # #return_type_for consults, because a raise is not evidence that
      # any frame ended -- only that a `nil` return seen later might be
      # fabricated (found by an independent review, round 22).
      #
      # Rounds 20 and 21 both still had this event *pop and record* the
      # frame of the method the raise was attributed to, on the premise
      # that such a method never returns. CRuby says otherwise: `:raise`
      # is attributed to the innermost Ruby frame the raise occurred in,
      # whether or not the exception ever unwinds that frame, and a
      # method that rescues its own raise is reported exactly like one
      # that dies of it (verified on ruby 3.4.7). All three of these fire
      # `raise Widget#m` and then `return Widget#m` with the real value:
      #
      #   def m; raise Bad unless ok?; "hit"; rescue Bad; "miss"; end
      #   def m; xs.each { raise Stop }; "done"; rescue Stop; "done"; end
      #   def m; Model.transaction { raise Rollback }; "after"; end
      #
      # -- a guard clause, a raise inside a block, and the Rails
      # `transaction`/`Rollback` idiom, i.e. ordinary application code
      # rather than an edge case. Popping at `:raise` threw that frame
      # away, so the real `:return` matched nothing and the method's
      # actual return type was discarded. Worse than losing it outright:
      # a method observed on both paths reported only the non-raising
      # one, so `def fetch(id); raise Missing unless ok; User.find(id);
      # rescue Missing; NullUser.new; end` was reported as returning
      # `User`, never `User | NullUser` -- a union that is confidently
      # wrong rather than merely incomplete, which is what
      # `ovallsp/showTypeEvidence` then hands the user. And because
      # #unwind_to discards everything stacked above its match, the
      # frames *between* the raise site and that method -- other
      # workspace methods, still perfectly alive -- were discarded with
      # it.
      #
      # Nothing is lost by not popping here: CRuby fires exactly one
      # `:return` for every `:call`, abandoned frames included (an
      # exception unwinding a->b->c produces `return c`, `return b`,
      # `return a`, all with `ret=nil`). So `:return` is the single
      # authoritative close-out for every frame, it keeps the stack
      # balanced by construction, and round 21's epoch check is already
      # what tells an abandoned frame's `nil` from a real one. Removing
      # the second close-out path also removes the double-count it made
      # possible, where a raise popped one invocation of a recursive
      # method and its `:return` then closed out the next one down.
      def handle_raise(_tp)
        # Bumped for every raise rather than only for recorded ones,
        # because what the epoch has to answer is "could an exception
        # have abandoned this frame", not "did we record the raiser".
        Thread.current[@raise_epoch_key] = current_raise_epoch + 1
      end

      def record(frame, return_type:)
        @mutex.synchronize do
          agg = @aggregates[frame.symbol_id] ||= {
            param_type_sets: Array.new(frame.param_types.size) { Set.new },
            return_type_set: Set.new,
            samples: 0,
            fingerprint: frame.fingerprint
          }
          frame.param_types.each_with_index { |type, index| agg[:param_type_sets][index] << type }
          agg[:return_type_set] << return_type if return_type
          agg[:samples] += 1
        end
      end

      # Fiber-local storage, not a `Hash` this object keys by
      # `Thread.current.object_id` (found by an independent review, round
      # 20 -- the same unbounded-registry class rounds 17/18 fixed in
      # AgentProcessManager, here in the code that runs inside the *user's
      # own test-suite process*).
      #
      # The Hash was three separate defects at once:
      #
      # 1. Unbounded growth. Nothing ever removed a thread's entry, so
      #    every thread that ever executed one Ruby method left a
      #    permanent entry -- plus any frames stranded on it by an
      #    exception -- for the whole run. `object_id` is a monotonic
      #    counter in modern CRuby, never reused, so a suite that churns
      #    threads (system/Capybara tests, parallel workers, any app that
      #    forks work off per request) grows this monotonically with
      #    nothing that would ever reclaim it.
      # 2. Unsynchronized cross-thread mutation. `@mutex` guards
      #    `@aggregates` only, while this Hash was written from every
      #    traced thread -- including its default block's own `h[k] = []`
      #    insert. CRuby's GVL happens to make that survivable today;
      #    nothing else does, and this codebase's own AgentSupervisor spec
      #    is explicit that "no other Ruby implementation is obligated to
      #    avoid" such an interleaving.
      # 3. Fibers shared one stack per thread. A Fiber has its own call
      #    stack, so an Enumerator or async library switching fibers
      #    mid-call interleaved two unrelated call stacks into one array.
      #
      # Fiber-local storage fixes all three structurally rather than
      # patching any one of them: the stack is reachable only from the
      # fiber it belongs to, so it is inherently unshared (no lock needed,
      # no fiber crosstalk) and it is reclaimed with that fiber (no
      # registry to prune).
      def current_stack
        Thread.current[@stack_key] ||= []
      end

      # Fiber-local for the same reason, and an Integer rather than a
      # collection, so it needs no pruning of its own.
      def current_raise_epoch
        Thread.current[@raise_epoch_key] || 0
      end

      def defined_method(tp)
        tp.defined_class.instance_method(tp.method_id)
      rescue StandardError
        nil
      end

      # Filters to methods whose own *definition* lives under the
      # workspace root -- not merely called from workspace test code, so
      # a Gem/stdlib method invoked from a workspace spec is correctly
      # excluded ("workspace外Gemイベントを既定で収集しない").
      def workspace_method?(method_obj)
        file, = method_obj.source_location
        return false unless file

        File.realpath(file).start_with?(@workspace_root)
      rescue StandardError
        false
      end

      def symbol_id_for(tp)
        defined_class = tp.defined_class
        if singleton_class?(defined_class)
          owner_name = tp.self.is_a?(Module) ? tp.self.name : nil
          return nil unless owner_name

          Index::SymbolId.new(kind: :singleton_method, owner: "::#{owner_name}", name: tp.method_id.to_s, discriminator: nil)
        else
          owner_name = defined_class.name
          return nil unless owner_name

          Index::SymbolId.new(kind: :instance_method, owner: "::#{owner_name}", name: tp.method_id.to_s, discriminator: nil)
        end
      end

      def singleton_class?(mod)
        mod.respond_to?(:singleton_class?) && mod.singleton_class?
      end

      def fingerprint_for(method_obj)
        file, line = method_obj.source_location
        return nil unless file

        Fingerprint.for_file_and_line(File.realpath(file), line)
      rescue StandardError
        nil
      end

      # Only :req/:opt positional parameters -- keyword/rest/block
      # parameters don't fit ObservedSignature's flat, position-indexed
      # `parameter_types` array, and are rarer in the small, first-hop
      # method summaries this evidence is meant to supplement anyway.
      # Split from #positional_param_types (below) so the name list --
      # invariant per method -- is computed once and cached, while the
      # actual argument *values* (which must be read fresh from each
      # call's own binding) stay per-call.
      def positional_param_names(method_obj)
        method_obj.parameters.select { |(kind, _)| %i[req opt].include?(kind) }.map { |(_, name)| name }
      rescue StandardError
        []
      end

      def positional_param_types(tp, param_names)
        param_names.map do |name|
          TypeNormalizer.normalize(tp.binding.local_variable_get(name))
        rescue StandardError
          Types::UNKNOWN
        end
      rescue StandardError
        []
      end
    end
  end
end
