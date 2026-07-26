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

      # Finds the frame matching `key`, scanning from the top of the stack
      # downward (the *nearest* match, not necessarily the top itself),
      # and discards it along with anything stacked above it.
      #
      # For an ordinary, single-fiber event stream this scan degenerates
      # to "match is always the top" and nothing above it ever exists to
      # discard: CRuby delivers exactly one `:return` per `#push`, in
      # strict inner-to-outer order, even for a frame an exception unwound
      # past (see #note_raise's docs and
      # docs/design/tasks/022.2-collector-tracepoint-state-machine.md's
      # transition table row 7) -- so a plain LIFO pop already gets rows
      # 1-10 right on its own, and matching-by-identity is not what makes
      # multi-frame unwinding or recursion correct (a bare `pop` handles
      # both, verified while building this class).
      #
      # What matching-by-identity is actually for is a `:return` with *no*
      # corresponding `#push` at all, which a bare `pop` would answer by
      # discarding whatever legitimate frame happens to be on top,
      # corrupting every match after it for the rest of the run. Returns
      # `nil`, leaving the stack completely untouched, in exactly that
      # case (I4) rather than ever guessing.
      #
      # That case is reachable from real code, and NOT only as table row
      # 11's "call already in flight when tracking started" (whose stray
      # `:return`s, being strictly outermost, arrive when the stack is
      # already empty and so are harmless even to a bare pop). The shape
      # that actually bites is a push Collector *skipped*: `#handle_call`
      # can raise -- `symbol_id_for` reads `defined_class.name`, which
      # real code does override -- and be swallowed by `#handle`'s blanket
      # rescue before ever reaching `#push`, while `#handle_return` pops
      # unconditionally. The unmatched `:return` then arrives in the
      # *middle* of a live stack. Measured with a bare pop, the caller's
      # recorded return type becomes its callee's: round 20's bug exactly.
      # Pinned by collector_spec.rb's "keeps a live frame when a :return
      # arrives for a call that was never pushed".
      #
      # Note this makes matching, not `#push`-for-every-call (I2), the
      # mechanism round 20's shape actually depends on today: reverting
      # either one alone leaves collector_spec.rb green, because each
      # covers the other. I2 is retained as deliberate defense in depth
      # (I7's spirit), not as the load-bearing half.
      #
      # The "discard everything above the match" behavior this scan
      # implies is defensive generality (I7: never raise, never corrupt
      # state, for *any* input this class is given) rather than a property
      # today's real TracePoint delivery is known to require -- see
      # call_stack_machine_spec.rb's generative section, which constructs
      # event sequences with no attempt to mirror what real Ruby code
      # would produce, specifically to hold this class to a contract
      # stronger than "correct for the cases observed so far".
      #
      # Never raises, for any input, including an empty stack or a key
      # that matches nothing anywhere in it.
      def pop_matching(key)
        index = @stack.size - 1
        while index >= 0
          frame = @stack[index]
          if frame.key == key
            @stack.slice!(index, @stack.size - index)
            return frame
          end
          index -= 1
        end
        nil
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
