# frozen_string_literal: true

require_relative "../../fixtures/observation/sample_classes"

# Deliberately defined *here* rather than under spec/fixtures/observation:
# this file is outside the workspace root the collector under test is
# given, so these stand in for "a gem's own Ruby methods" -- the thing
# TracePoint reports `:call`/`:return` for just as loudly as it does for
# the workspace's own code, and which the round-20 fix is about.
module ObservationOutside
  def self.array_returning_helper = [1, 2, 3]

  def self.raising_helper = raise("from outside the workspace")
end

RSpec.describe Ovallsp::Observation::Collector do
  let(:workspace_root) { File.expand_path("../../fixtures/observation", __dir__) }
  subject(:collector) { described_class.new(workspace_root: workspace_root) }

  def sym(kind:, owner:, name:) = Ovallsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil)

  it "records an instance method's observed parameter and return classes" do
    collector.start
    ObservationFixture::Widget.new.combine("a", "b")
    collector.stop

    results = collector.results(run_id: "r1")
    signature = results.find { |r| r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::Widget", name: "combine") }

    expect(signature).not_to be_nil
    expect(signature.parameter_types).to eq([Ovallsp::Types::Nominal.new(name: "String"), Ovallsp::Types::Nominal.new(name: "String")])
    expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
    expect(signature.samples).to eq(1)
  end

  it "unions the return type across multiple calls, including nil" do
    collector.start
    ObservationFixture::Widget.new.maybe_nil(true)
    ObservationFixture::Widget.new.maybe_nil(false)
    collector.stop

    signature = collector.results(run_id: "r1").find do |r|
      r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::Widget", name: "maybe_nil")
    end

    expect(signature.return_type).to eq(
      Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "String"), Ovallsp::Types::NIL])
    )
    expect(signature.samples).to eq(2)
  end

  it "records a call that raises without fabricating a return type, but still counts the sample" do
    collector.start
    begin
      ObservationFixture::Widget.new.boom
    rescue RuntimeError
      nil
    end
    collector.stop

    signature = collector.results(run_id: "r1").find do |r|
      r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::Widget", name: "boom")
    end

    expect(signature).not_to be_nil
    expect(signature.samples).to eq(1)
    expect(signature.return_type).to eq(Ovallsp::Types::UNKNOWN)
  end

  it "records a singleton method call with the class itself as owner" do
    collector.start
    ObservationFixture::Widget.build("x")
    collector.stop

    signature = collector.results(run_id: "r1").find do |r|
      r.symbol_id == sym(kind: :singleton_method, owner: "::ObservationFixture::Widget", name: "build")
    end

    expect(signature).not_to be_nil
    expect(signature.parameter_types).to eq([Ovallsp::Types::Nominal.new(name: "String")])
  end

  it "does not record a call to a method defined outside the workspace root" do
    outside_collector = described_class.new(workspace_root: File.expand_path("../../fixtures/plugins", __dir__))
    outside_collector.start
    ObservationFixture::Widget.new.combine("a", "b")
    outside_collector.stop

    expect(outside_collector.results(run_id: "r1")).to be_empty
  end

  it "attaches the run_id and a code_fingerprint to every recorded signature" do
    collector.start
    ObservationFixture::Widget.new.combine("a", "b")
    collector.stop

    signature = collector.results(run_id: "my-run").first

    expect(signature.run_id).to eq("my-run")
    expect(signature.code_fingerprint).not_to be_nil
  end

  # Found by an independent review (round 20) of Task 022.2, sweeping the
  # observation feature for the resource/lifecycle classes rounds 9-19
  # kept finding. This one is a correctness bug rather than a leak, and
  # the worst kind: it does not lose evidence, it reports *confidently
  # wrong* evidence, and it fires for the ordinary shape of essentially
  # every method in a real Rails app rather than for an exotic edge.
  #
  # #handle_call pushed a frame only for workspace methods, while
  # #handle_return popped on *every* `:return` -- and TracePoint fires
  # `:call`/`:return` for every Ruby-defined method, gem and stdlib
  # included. So the first non-workspace Ruby method a workspace method
  # called returned first and popped the caller's frame, recording the
  # callee's return value against the caller's symbol_id; the caller's own
  # `:return` then found an empty stack and recorded nothing. Measured
  # pre-fix: `return_type` = Array (ObservationOutside's value) for a
  # method that plainly returns a String.
  describe "call/return balance across non-workspace callees (round 20)" do
    def signature_for(collector, name)
      collector.results(run_id: "r1").find do |r|
        r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::Widget", name: name)
      end
    end

    it "records a workspace method's own return type, not that of the non-workspace method it called" do
      collector.start
      ObservationFixture::Widget.new.via_outside(7)
      collector.stop

      signature = signature_for(collector, "via_outside")

      expect(signature).not_to be_nil
      expect(signature.parameter_types).to eq([Ovallsp::Types::Nominal.new(name: "Integer")])
      expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
      expect(signature.samples).to eq(1)
    end

    it "never attributes a non-workspace callee's own signature to anything" do
      collector.start
      ObservationFixture::Widget.new.via_outside(7)
      collector.stop

      owners = collector.results(run_id: "r1").map { |r| r.symbol_id.owner }
      expect(owners).not_to include("::ObservationOutside")
    end

    # The `:raise` half of the same imbalance: a raise inside a
    # non-workspace callee, rescued by the workspace method itself. Pre-fix
    # the `:raise` popped the *caller's* frame (recording it with no return
    # type at all), so the method's real String return was lost and its
    # evidence said "this never returns anything".
    it "records the real return type of a workspace method that rescues a non-workspace raise" do
      collector.start
      ObservationFixture::Widget.new.rescues_internally(7)
      collector.stop

      signature = signature_for(collector, "rescues_internally")

      expect(signature).not_to be_nil
      expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
    end
  end

  # Found by an independent review (round 21). CRuby fires a `:return`
  # event for a method an exception unwound past -- one that never
  # returned at all -- and reports its `return_value` as `nil`, which at
  # the event itself is indistinguishable from a method that genuinely
  # evaluated to `nil`. Round 20's `:raise` handling only closed out the
  # frame of the method the raise happened *in*; every frame between that
  # one and whichever frame rescues was recorded as "returns nil".
  #
  # Same shape as round 20 and worse than losing evidence: `nil` in an
  # observed return union is precisely the signal a user acts on, and
  # `ovallsp/showTypeEvidence` hands it over verbatim as
  # `returnType: "String | nil"` for a method whose every observed call
  # raised instead of returning.
  describe "returns fabricated by an exception unwinding a frame (round 21)" do
    def signature_for(collector, name)
      collector.results(run_id: "r1").find do |r|
        r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::Widget", name: name)
      end
    end

    it "records no return type for a method a non-workspace raise unwound past" do
      collector.start
      begin
        ObservationFixture::Widget.new.propagates_outside_raise(7)
      rescue RuntimeError
        nil
      end
      collector.stop

      signature = signature_for(collector, "propagates_outside_raise")

      expect(signature).not_to be_nil
      expect(signature.samples).to eq(1)
      expect(signature.return_type).to eq(Ovallsp::Types::UNKNOWN)
    end

    # The other direction: a genuine `nil` return is real evidence and
    # must survive. Both of these pass *before* the fix as well -- they
    # are here so the fix can't be made by simply distrusting every `nil`
    # (or every `nil` after any raise), which would silently delete the
    # single most useful thing this feature observes.
    it "still records a genuine nil return made after an earlier raise has been rescued" do
      collector.start
      begin
        ObservationFixture::Widget.new.boom
      rescue RuntimeError
        nil
      end
      ObservationFixture::Widget.new.maybe_nil(false)
      collector.stop

      signature = signature_for(collector, "maybe_nil")

      expect(signature.return_type).to eq(Ovallsp::Types::NIL)
    end

    it "still records a genuine nil return made from an ensure body mid-unwind" do
      collector.start
      begin
        ObservationFixture::Widget.new.ensure_calls_nil_returner
      rescue RuntimeError
        nil
      end
      collector.stop

      signature = signature_for(collector, "nil_returner")

      expect(signature).not_to be_nil
      expect(signature.return_type).to eq(Ovallsp::Types::NIL)
    end
  end

  # Same round: the per-thread call stacks lived in a plain `Hash` keyed by
  # `Thread.current.object_id` that nothing ever pruned, in code that runs
  # inside the *user's own test-suite process* for the whole length of
  # their suite -- the unbounded-registry class rounds 17/18 fixed in
  # AgentProcessManager. `object_id` is a monotonic counter in modern
  # CRuby, so entries were never even reused: one permanent entry per
  # thread that ever ran a single Ruby method, plus any frames an
  # exception stranded on it. Now fiber-local, so a stack is reachable
  # only from the fiber it belongs to and dies with it.
  it "retains no per-thread call-stack state once the threads that produced it have died" do
    collector.start
    20.times { Thread.new { ObservationFixture::Widget.new.combine("a", "b") }.join }
    collector.stop

    # Counts the call stacks the collector itself still holds, through
    # either shape a per-thread registry could take (a Hash keyed by
    # thread, or a plain list of stacks). Its legitimate state --
    # @aggregates and @method_cache -- maps to Hashes and to nil, never to
    # the bare Arrays a call stack is, so this is zero for any
    # implementation that doesn't keep a registry of its own.
    retained_stacks = collector.instance_variables.sum do |name|
      case (value = collector.instance_variable_get(name))
      when Hash then value.count { |_, entry| entry.is_a?(Array) }
      when Array then value.count { |entry| entry.is_a?(Array) }
      else 0
      end
    end

    expect(retained_stacks).to be_zero, "collector retained #{retained_stacks} per-thread call stack(s)"
  end

  it "still observes a workspace method called on a thread of its own" do
    collector.start
    Thread.new { ObservationFixture::Widget.new.combine("a", "b") }.join
    collector.stop

    signature = collector.results(run_id: "r1").find do |r|
      r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::Widget", name: "combine")
    end

    expect(signature).not_to be_nil
    expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
  end

  it "does not raise even when TracePoint observes something Collector can't classify cleanly" do
    collector.start
    expect { Class.new.new.instance_eval { 1 + 1 } }.not_to raise_error
    collector.stop
  end
end
