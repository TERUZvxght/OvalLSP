# frozen_string_literal: true

module ObservationFixture
  class Widget
    def combine(a, b)
      "#{a}#{b}"
    end

    def maybe_nil(flag)
      flag ? "value" : nil
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
  end
end
