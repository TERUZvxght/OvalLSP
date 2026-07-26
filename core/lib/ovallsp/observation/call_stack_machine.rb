# frozen_string_literal: true

module Ovallsp
  module Observation
    # The pure call/return/raise state machine `Collector` translates real
    # `TracePoint` events through -- no `TracePoint`, no threads, no
    # fibers, no I/O, so its invariants can be pinned by feeding it a
    # sequence of symbolic events directly
    # (spec/ovallsp/observation/call_stack_machine_spec.rb), including
    # generated sequences that never construct a real Ruby call shape at
    # all.
    #
    # Extracted after independent review rounds 20-22 each found a genuine
    # correctness bug here, every fix revealing that the *previous* fix's
    # premise was still wrong (round 20: unbalanced push/pop across
    # non-workspace callees; round 21: an unwound frame's fabricated `nil`
    # return; round 22: `:raise` itself does not mean a frame ended). That
    # pattern -- the same file, three rounds running, each correcting the
    # last one's assumption -- was treated as a sign the ad hoc stack logic
    # itself, not just its edge-case coverage, needed pulling into
    # something independently testable. See
    # docs/design/tasks/022.2-collector-tracepoint-state-machine.md for the
    # full invariant list, the TracePoint event/transition table this class
    # implements, and what is deliberately left unhandled (and why).
    #
    # One instance per fiber -- see Collector#current_stack for why fiber
    # isolation matters and why it is handed to this class as "one
    # instance per fiber" rather than something this class tracks itself.
    # This class has no notion of threads, fibers, or process lifecycle at
    # all: an instance (and any frames still on it) is simply garbage the
    # moment nothing references it any more.
    class CallStackMachine
      # `raise_epoch` is #raise_epoch's value at the moment this frame was
      # pushed. A caller (Collector#return_type_for) compares it against
      # the *current* epoch at pop time to tell a frame a raise abandoned
      # (its own return value is always `nil` and untrustworthy) from one
      # that returned normally (its epoch is unchanged, so a `nil` return
      # value is genuine). This class does not interpret the value itself
      # -- it only stamps it at push time and hands it back unchanged at
      # pop time.
      Frame = Struct.new(:key, :payload, :raise_epoch)

      def initialize
        @stack = []
        @raise_epoch = 0
      end

      # Every observed `:call` becomes exactly one #push, whether or not
      # the caller intends to record it -- a frame with a `nil`/sentinel
      # `payload` for an untracked method still occupies a stack slot, so
      # the stack stays balanced across calls to methods this Collector
      # doesn't care about (this was round 20's fix: pushing only for
      # "interesting" calls while popping on every `:return` desyncs the
      # stack against the very first uninteresting call). Never raises.
      def push(key, payload)
        @stack << Frame.new(key, payload, @raise_epoch)
        nil
      end

      # Advances the raise epoch. Does NOT touch the stack -- a raise is
      # evidence that some frame *might later turn out to have been*
      # abandoned, not that any particular frame has ended right now
      # (round 22's finding: CRuby attributes `:raise` to the frame the
      # exception originated in, whether or not that frame ever actually
      # unwinds -- a method that rescues its own raise is indistinguishable,
      # at the `:raise` event itself, from one that dies of it). Safe to
      # call with an empty stack (a raise from outside any tracked frame
      # still needs to be visible to whatever frame's later `:return`
      # checks its own #raise_epoch against the current one). Never raises.
      def note_raise
        @raise_epoch += 1
        nil
      end

      # Closes the frame on *top* of the stack, and only if its key
      # matches. Any other `:return` -- one whose key matches nothing, or
      # matches only some frame deeper down -- is a no-op: `nil` is
      # returned and the stack is left completely untouched (I4).
      #
      # The rule is a consequence of one property of CRuby's delivery,
      # not a heuristic: a `:return` can only ever be about the
      # *innermost* live frame. Returns arrive in strict inner-to-outer
      # order, one per frame, abandoned frames included -- a raise
      # unwinding N frames fires N returns, innermost first (see
      # #note_raise's docs and the transition table's row 7). So if the
      # innermost frame this machine holds is not the one returning, no
      # frame this machine holds has ended, and closing one would be a
      # guess. This module prefers under-collection to fabrication
      # everywhere else; the stack is no different.
      #
      # Matching at all (rather than a bare `@stack.pop`) is what keeps a
      # `:return` with *no* corresponding `#push` from discarding whatever
      # legitimate frame happens to be on top, corrupting every match
      # after it for the rest of the run. That shape is reachable two
      # ways, and NOT only as table row 11's "call already in flight when
      # tracking started" (whose stray `:return`s, being strictly
      # outermost, arrive when the stack is already empty and so are
      # harmless even to a bare pop):
      #
      # 1. A push Collector *skipped*. `#handle_call` can raise --
      #    `symbol_id_for` reads `defined_class.name`, which real code does
      #    override -- and be swallowed by `#handle`'s blanket rescue
      #    before ever reaching `#push`, while `#handle_return` pops
      #    unconditionally. Measured with a bare pop, the caller's
      #    recorded return type becomes its callee's: round 20's bug
      #    exactly. Pinned by collector_spec.rb's "keeps a live frame when
      #    a :return arrives for a call that was never pushed".
      # 2. A push *CRuby itself* never announced (round 30). `:call` fires
      #    only after the argument prologue has run, so a method whose own
      #    optional-argument or keyword-argument default expression raises
      #    gets **no `:call` at all** -- and still gets its `:return`,
      #    with `return_value = nil`, as the exception unwinds past it.
      #    `def m(a, b = might_raise)` is ordinary Ruby, and this stray
      #    `:return` arrives in the *middle* of a live stack.
      #
      # Shape 2 is why the match is restricted to the top. This method
      # used to scan downward for the *nearest* frame with a matching key
      # and discard everything above it, on the grounds that real
      # delivery never exercises the scan (true for rows 1-12) and that
      # generality could only be defensive (I7). It was not defensive: a
      # stray `:return` for a key that is *also* live further down -- the
      # everyday `a -> b -> a` shape, where the inner `a`'s default
      # argument raises -- matched that outer, still-running `a` and
      # sliced off every live frame stacked above it. Measured through a
      # real Collector on `outer -> middle -> outer(raising default)`:
      # `middle` vanished from the run entirely (its own later `:return`
      # then matched nothing), and `outer`'s return type was replaced by
      # the abandoned frame's untrusted `nil`. Silent, and it scales with
      # the depth of the call chain between the two invocations.
      #
      # What the top-only rule costs is bounded and strictly
      # under-collection: when the stray `:return`'s key matches the top
      # *because the same method is directly recursive* (`recur` whose own
      # default raises at the base case), the live outer frame is closed
      # one event early. Its parameter types are its own and still
      # correct, and its return value is discarded rather than fabricated
      # -- the raise epoch has already advanced, so #return_type_for
      # refuses the `nil` (I6). There is no event that distinguishes that
      # case, so it is recorded as a residue rather than guessed at; see
      # the design doc's "what is not fixed".
      #
      # Note this makes matching, not `#push`-for-every-call (I2), the
      # mechanism round 20's shape actually depends on today: reverting
      # either one alone leaves collector_spec.rb green, because each
      # covers the other. I2 is retained as deliberate defense in depth
      # (I7's spirit), not as the load-bearing half.
      #
      # Never raises, for any input, including an empty stack or a key
      # that matches nothing.
      def pop_matching(key)
        frame = @stack.last
        return nil unless frame && frame.key == key

        @stack.pop
        frame
      end

      # The epoch a frame must match to have its own `nil` return trusted
      # as genuine rather than fabricated by an intervening raise. Exposed
      # so a caller can stamp its own bookkeeping (Collector has none
      # beyond the Frame itself today) against the same clock; the machine
      # itself only ever compares a Frame's stored value against this one.
      attr_reader :raise_epoch

      # Current stack depth -- exposed for callers/tests that want to
      # assert on shape without reaching into the Struct layout directly.
      def depth
        @stack.size
      end
    end
  end
end
