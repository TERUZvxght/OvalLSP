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
  end
end
