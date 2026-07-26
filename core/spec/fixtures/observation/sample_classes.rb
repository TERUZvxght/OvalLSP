# frozen_string_literal: true

# Stands in for the workspace's Gemfile dependencies: the classes and
# modules below are patched together with the ones in
# spec/fixtures/observation_neighbor, which lives *outside* the workspace
# root these fixtures represent.
require_relative "../observation_neighbor/neighbor"

module ObservationFixture
  class Widget
    def combine(a, b)
      "#{a}#{b}"
    end

    def maybe_nil(flag)
      flag ? "value" : nil
    end

    # Table row 6: a method whose entire body is C-implemented calls.
    # `Collector` subscribes to `:call`/`:return`/`:raise` only, so none of
    # `#freeze`/`#upcase`/`#to_sym` fires an event of any kind -- and the
    # *absence* of those events cannot desync the stack, because nothing
    # pushes for them in the first place. What this pins is that this
    # method's own `:call`/`:return` pair is still delivered and still
    # recorded correctly (row 5's block case is pinned by
    # #raises_in_yielded_block / #yielding_rescuer, which yield to blocks
    # that likewise produce no `b_call`/`b_return` under this filter).
    def only_c_calls(name)
      name.freeze.upcase.to_sym
    end

    def self.build(name)
      name
    end

    def boom
      raise "boom"
    end

    # Calls a Ruby method defined OUTSIDE this workspace root (the spec
    # file defines ObservationOutside, and lives outside
    # spec/fixtures/observation) and then returns a String of its own.
    # That is the ordinary shape of every method in a real app -- a
    # workspace method whose body calls into a gem -- and it is what
    # Collector's round-20 fix is about: the callee's `:return` used to
    # pop this method's own frame.
    def via_outside(n)
      ObservationOutside.array_returning_helper
      n.to_s
    end

    # A raise the workspace method itself rescues, so its `:raise` and its
    # `:return` both fire for the same call.
    def rescues_internally(n)
      ObservationOutside.raising_helper
    rescue RuntimeError
      n.to_s
    end

    # Never returns at all: the raise comes from a non-workspace callee
    # and this method does not rescue it. CRuby still fires a `:return`
    # for this frame, reporting `nil` -- round 21's finding. Its observed
    # return type must be "no evidence", never `nil`.
    def propagates_outside_raise(n)
      ObservationOutside.raising_helper
      n.to_s
    end

    # An `ensure` body runs *during* the unwind, so the call it makes is
    # pushed after the `:raise` -- its own genuine `nil` return is real
    # evidence and must still be recorded. Guards against "fixing" the
    # above with a plain 'an exception is in flight' flag.
    def ensure_calls_nil_returner
      ObservationOutside.raising_helper
    ensure
      nil_returner
    end

    def nil_returner
      nil
    end

    # The guard-clause idiom: the raise is written in this method's *own*
    # body, so CRuby attributes the `:raise` to this frame even though the
    # frame is alive and about to return normally. Observed on both paths
    # its return type is genuinely `String | Symbol` -- round 22's finding
    # is that only `String` was reported, the raising path's real return
    # having been thrown away with the frame.
    def guarded(ok)
      raise ArgumentError, "not ok" unless ok

      ok.to_s
    rescue ArgumentError
      :fallback
    end

    # Same `:raise`-on-a-live-frame shape, reached the way Rails reaches it
    # (`transaction { raise Rollback }`): the raise is inside a block this
    # method passes to another method, so it is attributed to *this* frame,
    # not the callee's. #yielding_rescuer is a workspace method too, and
    # sits between the raise site and this one -- pre-fix it was discarded
    # as collateral, since closing out a frame also drops everything
    # stacked above it.
    def raises_in_yielded_block
      yielding_rescuer { raise "from the block" }
    end

    def yielding_rescuer
      yield
    rescue RuntimeError
      "inner rescued"
    end

    # Returns `nil` for real on one path and never returns at all on the
    # other, where the raise comes from a non-workspace callee. The `nil`
    # must be recorded, the abandoned frame's fabricated `nil` must not --
    # and the two are indistinguishable at the `:return` event itself.
    def nil_or_outside_raise(ok)
      ObservationOutside.raising_helper unless ok

      nil
    end

    # Direct recursion: CallStackMachine#pop_matching must close the
    # *innermost* live invocation on each `:return`, not an outer one with
    # the same key -- see its own docs (I3) and
    # docs/design/tasks/022.2-collector-tracepoint-state-machine.md's
    # table row 3.
    def factorial(n)
      return 1 if n <= 1

      n * factorial(n - 1)
    end

    # A `:return` CRuby delivers for a frame it never announced a `:call`
    # for (round 30). `:call` fires only *after* the argument prologue has
    # run, so when an optional-argument default expression raises, the
    # method gets no `:call` at all -- and still gets its own `:return`,
    # `return_value = nil`, as the exception unwinds past it.
    #
    # Arranged so that stray `:return` arrives while the *same* key is
    # already live further down the stack, with a third workspace frame
    # stacked in between: `unannounced_outer(1)` -> `unannounced_middle` ->
    # `unannounced_outer(0)`, whose default calls #boom_for_default. A
    # `#pop_matching` that scans past the top for the nearest matching key
    # answers that stray `:return` with the *outer, still-running* frame
    # and discards `unannounced_middle` along with it, so
    # `unannounced_middle` disappears from the run entirely.
    #
    # Every return value here is deliberately a distinct class, so a frame
    # closed against the wrong event shows up as a wrong (or missing)
    # recorded type rather than coincidentally matching.
    def boom_for_default
      raise "raised while evaluating a default argument"
    end

    def unannounced_outer(n, _guard = (n.zero? ? boom_for_default : nil))
      unannounced_middle(n)
    end

    # Rescues the raise itself, so both live frames go on to return real,
    # non-nil values of their own: whatever they are recorded as is then a
    # statement about which event closed which frame, not about the
    # fabricated-nil rule (I6) that would apply to an abandoned one.
    def unannounced_middle(n)
      unannounced_outer(n - 1)
    rescue RuntimeError
      "middle-string"
    end

    # The *recursive* form of the same shape, which is the one round 30
    # left as a documented residue rather than fixing (the design doc's
    # "fifth residue"). Here the unannounced `:return`'s key matches the
    # top of the stack -- because the method is directly recursive and it
    # is the recursive invocation whose default raised -- so it is
    # indistinguishable from the live frame's own `:return` and closes that
    # still-running frame one event early.
    #
    # The bound this pins is what the residue costs: the live frame's
    # *parameter* types are its own and still correct, while its return
    # value is *discarded* rather than fabricated, because the raise epoch
    # has already advanced and #return_type_for refuses the `nil` (I6).
    # Only the innermost invocation is affected, so a deeper call still
    # reports the real return type from its unaffected frames.
    def recur(n, _guard = (n.zero? ? boom_for_default : nil))
      recur(n - 1)
      :done
    rescue RuntimeError
      :done
    end

    # Mutual recursion (table row 4): two different keys interleaved on
    # the same fiber's stack, neither ever popping the other's frame.
    def mutual_a(n)
      return "a-base" if n <= 0

      mutual_b(n - 1)
    end

    def mutual_b(n)
      return 0.0 if n <= 0

      mutual_a(n - 1)
    end

    # Calls a workspace method whose `:call` event Collector cannot even
    # finish translating (see UnnameableOwner below), so no frame is ever
    # pushed for it -- while this method's own frame is live underneath and
    # a third workspace frame gets pushed above it. The skipped frame's
    # `:return` still fires, in the *middle* of the stack rather than at
    # its outermost edge, which is the one real shape where matching a
    # `:return` by identity (rather than popping whatever is on top) is
    # what keeps this method's own return type from being replaced by its
    # callee's. Returns a String; the callee returns an Integer, so a
    # mismatch is visible in the recorded type rather than coincidental.
    def calls_unnameable
      UnnameableOwner.new.mid(self)
      "outer-string"
    end
  end

  # `Collector#symbol_id_for` reads `defined_class.name`; a class that
  # overrides `name` to raise (real code does override `name` -- ORMs and
  # proxy/delegator gems both do) makes Collector's whole `:call` handler
  # raise before it reaches `CallStackMachine#push`, so this class's
  # methods get a `:return` with no corresponding push. That asymmetry --
  # `#handle_call` can bail out before pushing, while `#handle_return`
  # always pops -- is why `#pop_matching` must answer an unmatched key
  # with a no-op instead of taking the top of the stack.
  class UnnameableOwner
    def self.name = raise("this class refuses to be named")

    # Keeps RSpec's own failure output safe despite the `name` override.
    def inspect = "#<ObservationFixture::UnnameableOwner>"

    def mid(widget)
      widget.combine("x", "y")
      99 # Integer -- deliberately not what Widget#calls_unnameable returns
    end
  end

  # Singleton methods reached through inheritance and through `super`.
  # For both, `tp.defined_class` is the singleton class of the class the
  # method is *written in*, while `tp.self` is whichever class the call was
  # dispatched through -- so deriving the owner from `tp.self` (round 24's
  # finding) files the evidence under the wrong symbol, and does it
  # differently depending on which receiver happened to call first.
  class Registry
    def self.register(name, scope)
      "#{name}/#{scope}"
    end
  end

  # Inherits .register unchanged: `Sub.register` and `Registry.register`
  # are the same method, at the same source location, and must produce the
  # same symbol_id no matter which is observed first.
  class SubRegistry < Registry; end

  # Overrides .register with a *different arity* and calls `super`, so one
  # call produces two frames that both report `tp.self == OverridingRegistry`.
  # Collapsing them into one symbol_id unions their parameter lists
  # position-wise, inventing a second positional parameter this method does
  # not have.
  class OverridingRegistry < Registry
    def self.register(name)
      super(name, :default)
    end
  end

  # `prepend` is the one construct that makes `defined_class` and
  # "whatever `defined_class.instance_method(id)` resolves to" different
  # methods, because it inserts a module *ahead of* a class in that class's
  # own ancestor chain (round 25). This is the workspace class a gem
  # prepends into -- the ordinary shape of every instrumentation gem and of
  # ActiveSupport's own patching.
  class Patched
    def perform(workspace_arg)
      "done:#{workspace_arg}"
    end
  end
  Patched.prepend(ObservationNeighbor::Instrumentation)

  # The mirror image: a module the workspace prepends into a *gem's* class.
  # This module is workspace code and must be collected; the gem method it
  # calls `super` into must not be, even though the lookup starting from
  # the gem class now finds this file.
  module ServicePatch
    def call(workspace_name, workspace_extra = :tagged)
      super(workspace_name)
    end
  end
  ObservationNeighbor::Service.prepend(ServicePatch)

  # Two positional parameters that share a name. Ruby allows this and binds
  # only the *first* one, so a by-name `local_variable_get` lookup answers
  # both slots with the same value -- reporting the wrong class for every
  # slot but the first (round 25).
  class RepeatedParamNames
    def pair(_, _)
      "paired"
    end

    # The same collision reached across a parameter-*kind* boundary (round
    # 26). `*rest` is dropped from the flat positional list, so counting
    # repeats within that list never sees this one -- but Ruby binds the
    # leftmost declaration, and here that is the rest parameter, so reading
    # the trailing required slot by name answers with the rest Array. Its
    # own value is a String, so a wrong class is visible rather than
    # coincidental.
    def trailing_after_rest(*_a, _a)
      _a
    end

    # No collision at all, just a `*rest` in the middle. Every positional
    # name here resolves to its own value, so this is the control that keeps
    # the fix above from being written as "blank every slot of any method
    # that has a rest parameter" -- and it is also where round 25's
    # documented, deliberate index imprecision is pinned so it cannot
    # silently get worse.
    def rest_between(a, *rest, b)
      [a, rest, b]
    end

    # The same collision again, this time reached across the one boundary
    # `#parameters` refuses to describe at all (round 28). A destructuring
    # parameter is reported as a bare `[:req]` with no name, and the names it
    # binds are reported nowhere, so a tally over `#parameters` -- however
    # wide -- sees `_` exactly once here and concludes the slot is readable.
    # Ruby binds the *rightmost* declaration, which is the destructured one,
    # so reading slot 0 by name answers with the first element of the second
    # argument. Slot 0's own value is an Integer and that element a String,
    # so a wrong class is visible rather than coincidental. `_` and a
    # destructuring parameter are both everyday idioms; they are legal
    # *together* only because `_`-prefixed names are exempt from Ruby's
    # duplicate-name rule (`def m(a, (a, b))` is a SyntaxError).
    #
    # `_a` rather than a bare `_` -- both behave identically here, and bare
    # `_` is the more everyday spelling, but only the prefixed form makes a
    # fix narrowed to the single name `:_` fail rather than pass.
    def shadowed_by_destructure(_a, (_a, _b))
      [_a, _b]
    end

    # The control: the same destructuring shape with no collision in it, so
    # the fix above cannot be written as "blank every slot of any method that
    # destructures". `kept` is not `_`-prefixed and so cannot be the hidden
    # second binding at all -- its own Integer must still be reported.
    def clean_destructure(kept, (_x, _y))
      [kept, _x, _y]
    end
  end

  # Two *distinct* Class objects that both answer `#name` with
  # "ObservationFixture::Reloaded", so both file their evidence under one
  # symbol_id -- `[kind, owner-name, method-name]` has no notion of which
  # class object produced it. That is the shape a Rails/Zeitwerk constant
  # reload, a bare `remove_const` + redefine, and rspec-mocks' `stub_const`
  # all produce inside a single observation run, and the two definitions
  # need not share an arity (round 27). Deliberately *different* arities
  # and different slot-0 argument classes below, so an aggregate that
  # silently truncates to the first-observed slot count is visible in the
  # recorded signature rather than coincidental.
  module Reloading
    module_function

    def define_narrow
      reset
      ObservationFixture.const_set(:Reloaded, Class.new do
        def m(_a)
          "narrow"
        end
      end)
    end

    def define_wide
      reset
      ObservationFixture.const_set(:Reloaded, Class.new do
        def m(_a, _b, _c)
          "wide"
        end
      end)
    end

    def reset
      ObservationFixture.send(:remove_const, :Reloaded) if ObservationFixture.const_defined?(:Reloaded, false)
    end
  end

  class Widget
    # A Fiber suspending mid-call and later resuming (table row 15): the
    # fiber's own call stack must stay isolated from whatever else runs on
    # the same Thread while it's suspended.
    def fiber_worker(steps)
      fiber = Fiber.new do
        steps.times { |i| Fiber.yield combine("f", i.to_s) }
        "fiber-done"
      end
      loop do
        result = fiber.resume
        break result if result == "fiber-done"

        combine("main", "interleaved") # runs on the *main* fiber's own stack, between resumes
      end
    end

    # Round 31. Classes created at *runtime*, which is what a real suite
    # does constantly: rspec-mocks defines a stubbed method on each
    # double's own singleton class, `stub_const` takes a fresh
    # `Class.new`, `Struct.new`/`Data.define` get called inside methods,
    # and a Zeitwerk reload replaces every model class. Collector's
    # per-method cache is indexed by the frame's `defined_class`, so
    # holding that index strongly pins every one of these for the whole
    # run -- and through a singleton class, the object it is attached to
    # as well.
    #
    # Both return a value of their own so the churn is a normal, fully
    # traced call rather than something the collector might skip.
    def churn_anonymous_class
      Class.new { def churned(n) = n.to_s }.new.churned(1)
    end

    def churn_singleton_method
      holder = ChurnHolder.new
      def holder.churned(n) = n.to_s
      holder.churned(1)
    end
  end

  # Nothing but a countable identity for the churn above: a spec can ask
  # ObjectSpace how many instances survived without the noise of counting
  # every Class in the VM.
  class ChurnHolder; end
end
