# frozen_string_literal: true

require_relative "../../fixtures/observation/sample_classes"
require_relative "../../fixtures/observation_neighbor/neighbor"

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

  # Found by an independent review (round 22), in the same file and with
  # the same shape as rounds 20 and 21: not lost evidence but a
  # confidently wrong type, fired by ordinary application code.
  #
  # `:raise` is attributed by CRuby to the innermost Ruby frame the raise
  # occurred in, whether or not the exception ever unwinds that frame --
  # a method that rescues its own raise is reported exactly like one that
  # dies of it. Rounds 20 and 21 both still *closed out* that frame on
  # `:raise`, so a guard clause, a raise inside a block, or the Rails
  # `transaction { raise Rollback }` idiom threw the live frame away and
  # the method's real `:return` matched nothing. A method observed on
  # both paths then reported only the non-raising one's type.
  describe "raises the raising method itself survives (round 22)" do
    def signature_for(collector, name)
      collector.results(run_id: "r1").find do |r|
        r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::Widget", name: name)
      end
    end

    it "records the return type of a method that rescues a raise from its own body" do
      collector.start
      ObservationFixture::Widget.new.guarded(false)
      collector.stop

      signature = signature_for(collector, "guarded")

      expect(signature).not_to be_nil
      expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "Symbol"))
      expect(signature.samples).to eq(1)
    end

    it "unions both paths of a guard clause instead of reporting only the non-raising one" do
      collector.start
      ObservationFixture::Widget.new.guarded(true)
      ObservationFixture::Widget.new.guarded(false)
      collector.stop

      signature = signature_for(collector, "guarded")

      expect(signature.return_type).to eq(
        Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "String"), Ovallsp::Types::Nominal.new(name: "Symbol")])
      )
      expect(signature.samples).to eq(2)
    end

    # A raise inside a block is attributed to the frame that *wrote* the
    # block, so closing that frame out also discarded every frame stacked
    # above it -- here a second workspace method, alive and about to
    # return a String of its own.
    it "records both the block's own frame and the workspace frames stacked above it" do
      collector.start
      ObservationFixture::Widget.new.raises_in_yielded_block
      collector.stop

      expect(signature_for(collector, "raises_in_yielded_block")&.return_type)
        .to eq(Ovallsp::Types::Nominal.new(name: "String"))
      expect(signature_for(collector, "yielding_rescuer")&.return_type)
        .to eq(Ovallsp::Types::Nominal.new(name: "String"))
    end

    # The invariant the fix must not break, in both orders: a genuine
    # `nil` return and an abandoned frame's fabricated one are the same
    # event, so the classification has to be per call, not per method.
    %i[raise_first nil_first].each do |order|
      it "classifies a genuine nil and an unwound frame's fake nil per call (#{order})" do
        widget = ObservationFixture::Widget.new
        collector.start
        calls = order == :raise_first ? [false, true] : [true, false]
        calls.each do |ok|
          widget.nil_or_outside_raise(ok)
        rescue RuntimeError
          nil
        end
        collector.stop

        signature = signature_for(collector, "nil_or_outside_raise")

        expect(signature.samples).to eq(2)
        expect(signature.return_type).to eq(Ovallsp::Types::NIL)
      end
    end
  end

  # Found by an independent review (round 24), in the same file and with
  # the same shape as rounds 20-22: not lost evidence but confidently
  # wrong evidence, fired by ordinary application code -- here the
  # `class ApplicationService; def self.call; end; end` + subclasses idiom
  # that every Rails app has several of.
  #
  # `#symbol_id_for` derived a singleton method's owner from `tp.self`,
  # the receiver the call was *dispatched through*, rather than from the
  # class the method is *defined on*. Those differ for every inherited
  # class method and for every `super` between two singleton methods.
  #
  # It also silently broke `@method_cache`'s stated premise (its own docs
  # assert every cached field is a function of `[defined_class,
  # method_id]`), which is what makes the misattribution stick for the
  # whole run rather than just for one call.
  describe "a singleton method's owner is where it is defined, not the receiver (round 24)" do
    def singleton_for(collector, owner, name)
      collector.results(run_id: "r1").find do |r|
        r.symbol_id == sym(kind: :singleton_method, owner: owner, name: name)
      end
    end

    # Order matters, and that is the point: pre-fix the *first* receiver to
    # reach the method won the cache entry, and every later caller's
    # evidence was filed against it.
    %i[subclass_first base_first].each do |order|
      it "files an inherited class method under its defining class regardless of call order (#{order})" do
        collector.start
        if order == :subclass_first
          ObservationFixture::SubRegistry.register("a", "b")
          ObservationFixture::Registry.register(:c, :d)
        else
          ObservationFixture::Registry.register(:c, :d)
          ObservationFixture::SubRegistry.register("a", "b")
        end
        collector.stop

        expect(singleton_for(collector, "::ObservationFixture::SubRegistry", "register")).to be_nil
        signature = singleton_for(collector, "::ObservationFixture::Registry", "register")
        expect(signature).not_to be_nil
        expect(signature.samples).to eq(2)
      end
    end

    # `super` between two singleton methods: one call, two frames, both
    # reporting `tp.self == OverridingRegistry`. Pre-fix they collapsed
    # into a single symbol_id whose `parameter_types` was the position-wise
    # union of two different parameter lists -- reporting a second
    # positional parameter `OverridingRegistry.register` does not have, and
    # leaving `Registry.register` with no evidence at all.
    it "keeps a super-calling override and the method it calls as two separate symbols" do
      collector.start
      ObservationFixture::OverridingRegistry.register("x")
      collector.stop

      override = singleton_for(collector, "::ObservationFixture::OverridingRegistry", "register")
      parent = singleton_for(collector, "::ObservationFixture::Registry", "register")

      expect(override).not_to be_nil
      expect(override.parameter_types).to eq([Ovallsp::Types::Nominal.new(name: "String")])
      expect(override.samples).to eq(1)

      expect(parent).not_to be_nil
      expect(parent.parameter_types).to eq(
        [Ovallsp::Types::Nominal.new(name: "String"), Ovallsp::Types::Nominal.new(name: "Symbol")]
      )
      expect(parent.samples).to eq(1)
    end
  end

  # Also round 24, and the same class of bug review rounds 1-2 fixed in
  # BundleEnvironment: `#workspace_method?` tested containment with a bare
  # `start_with?(@workspace_root)`, so any sibling directory whose name
  # merely *begins with* the workspace root's name was treated as inside
  # it. Every method defined there was collected and reported as the
  # user's own workspace evidence -- the exact thing this filter exists to
  # prevent ("workspace外Gemイベントを既定で収集しない"). A vendored gem
  # dir (`app-vendor` next to `app`), a sibling engine, or any adjacent
  # checkout hits it.
  it "treats the workspace root as a path boundary, not a string prefix" do
    # spec/fixtures/observation_neighbor is a *sibling* of the collector's
    # workspace root (spec/fixtures/observation) whose path begins with it.
    expect(File.dirname(ObservationNeighbor::Outsider.instance_method(:helper).source_location.first))
      .to start_with(workspace_root)

    collector.start
    ObservationNeighbor::Outsider.new.helper(1)
    collector.stop

    owners = collector.results(run_id: "r1").map { |r| r.symbol_id.owner }
    expect(owners).not_to include("::ObservationNeighbor::Outsider")
  end

  # The boundary check builds its prefix as `"#{root}#{File::SEPARATOR}"`,
  # which would double the separator (and so match nothing at all) for a
  # root handed in with a trailing one. It doesn't, because `#initialize`
  # normalizes through `File.realpath` first -- which is a load-bearing
  # reason for that call, not just symlink resolution, and is what this
  # pins (round 25).
  it "normalizes a workspace root given with a trailing separator" do
    trailing = described_class.new(workspace_root: "#{workspace_root}#{File::SEPARATOR}")
    trailing.start
    ObservationFixture::Widget.new.combine("a", "b")
    trailing.stop

    expect(trailing.results(run_id: "r1").map { |r| r.symbol_id.owner })
      .to include("::ObservationFixture::Widget")
  end

  # Found by an independent review (round 25), and the same shape as rounds
  # 20-22 and 24: not lost evidence but confidently wrong evidence, fired by
  # ordinary application code.
  #
  # `#defined_method` resolved the executing frame's definition with
  # `tp.defined_class.instance_method(tp.method_id)`. That answers "what
  # would dispatch find starting here", not "what is this frame" -- and the
  # two differ for exactly one construct, `prepend`, which puts a module
  # *ahead of* a class in that class's own ancestor chain. So for the frame
  # CRuby reports as `defined_class = Patched`, the lookup handed back the
  # prepended wrapper's method, and the containment test, the fingerprint
  # and the parameter-name list all described the wrong definition.
  #
  # `prepend` is not exotic: it is how ActiveSupport and every
  # instrumentation/APM gem patch application code, and how applications
  # patch gems back.
  describe "a prepended module is not the frame's own definition (round 25)" do
    let(:sample_classes_digest) do
      Ovallsp::Observation::Fingerprint.file_digest(
        File.expand_path("../../fixtures/observation/sample_classes.rb", __dir__)
      )
    end

    # Pre-fix this signature was absent from the results entirely: the
    # lookup found ObservationNeighbor::Instrumentation#perform, whose
    # source_location is outside the workspace root, so a workspace method
    # a gem had prepended into was silently dropped from the whole run.
    it "records a workspace method a non-workspace module is prepended into" do
      collector.start
      ObservationFixture::Patched.new.perform("hello")
      collector.stop

      signature = collector.results(run_id: "r1").find do |r|
        r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::Patched", name: "perform")
      end

      expect(signature).not_to be_nil
      # One slot, its own -- not the two-parameter wrapper's. Pre-fix, a
      # method with a *different* prepended wrapper reported the wrapper's
      # slot count, both slots Types::UNKNOWN, since the wrapper's parameter
      # names do not resolve in the real frame's binding.
      expect(signature.parameter_types).to eq([Ovallsp::Types::Nominal.new(name: "String")])
      expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
      # Fingerprinted against its own source file, not the prepended
      # wrapper's -- Store#invalidate_changed compares this against the
      # digest of the file the *declaration* lives in, so a wrapper's digest
      # here means edits to the real method never invalidate its evidence.
      expect(signature.code_fingerprint).to start_with(sample_classes_digest)
    end

    it "does not record a non-workspace method the workspace prepends a module into" do
      collector.start
      ObservationNeighbor::Service.new.call("x")
      collector.stop

      owners = collector.results(run_id: "r1").map { |r| r.symbol_id.owner }

      # The gem's own method: reached through a class the workspace patched,
      # so pre-fix the lookup found the workspace's patch module and the gem
      # method was collected and reported as the user's own evidence --
      # round 24's containment defect again, by a different route.
      expect(owners).not_to include("::ObservationNeighbor::Service")
      # ...while the workspace's own patch module is still real workspace
      # code and must survive, so the fix cannot be "ignore anything
      # prepend-shaped".
      expect(owners).to include("::ObservationFixture::ServicePatch")
    end
  end

  # Also round 25. Ruby permits the same name in two positional slots and
  # binds only the first, so reading each slot back by name through
  # `Binding#local_variable_get` answered every one of them with the same
  # value. Measured pre-fix on `pair(1, "s")`: `[Integer, Integer]` -- a
  # confidently wrong class for a slot plainly holding a String.
  it "reports no type, rather than the wrong one, for a positional slot whose name is shadowed" do
    collector.start
    ObservationFixture::RepeatedParamNames.new.pair(1, "s")
    collector.stop

    signature = collector.results(run_id: "r1").find do |r|
      r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::RepeatedParamNames", name: "pair")
    end

    expect(signature).not_to be_nil
    # Both slots are kept, so every later slot stays at its own position --
    # they just carry no evidence, which is this module's stated preference
    # over fabricating one.
    expect(signature.parameter_types).to eq([Ovallsp::Types::UNKNOWN, Ovallsp::Types::UNKNOWN])
  end

  # Found by an independent review (round 26): round 25's fix counted the
  # repeat within the req/opt list it returns rather than over the whole
  # declaration, so a name shared with a parameter of a *filtered-out* kind
  # (`*rest`, `**kw`, `&blk`, `key:`) was still read by name. Ruby binds the
  # leftmost declaration, so when the duplicate is declared first -- which
  # only `*rest` can be, since every other filtered kind must follow the
  # positional slots -- the read answers with that parameter's value instead.
  #
  # Measured pre-fix on `trailing_after_rest(1, 2, "the-real-tail")`:
  # `[Array]` for the one slot reported, the trailing required parameter,
  # which plainly holds a String. Round 25's family exactly, one kind
  # boundary over.
  it "reports no type for a positional slot whose name is shadowed by a rest parameter" do
    collector.start
    ObservationFixture::RepeatedParamNames.new.trailing_after_rest(1, 2, "the-real-tail")
    collector.stop

    signature = collector.results(run_id: "r1").find do |r|
      r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::RepeatedParamNames", name: "trailing_after_rest")
    end

    expect(signature).not_to be_nil
    expect(signature.parameter_types).to eq([Ovallsp::Types::UNKNOWN])
  end

  # The control for the example above -- a `*rest` with no name collision
  # around it -- so the fix cannot be written as "blank every positional slot
  # of any method that has a rest parameter", which the example above alone
  # would accept.
  #
  # It doubles as the pin for the one imprecision round 25 documented as
  # deliberate and left in place: `ObservedSignature#parameter_types` has no
  # representation for rest parameters at all, so a req/opt parameter that
  # *follows* one is reported at the index it occupies after rest parameters
  # are dropped, not at its index in the declaration. `b` is declared third
  # and reported second. Each slot's *type* is still its own -- this is an
  # index shift, never a wrong class -- and no consumer joins the list
  # positionally against a declaration (`ovallsp/showTypeEvidence` renders it
  # as text; see Server#type_evidence_response). Asserted here rather than
  # only described in prose so that widening it into a wrong *type* would
  # fail rather than pass quietly.
  it "reports each positional slot's own type around a rest parameter, shifting only the index" do
    collector.start
    ObservationFixture::RepeatedParamNames.new.rest_between(1, :x, :y, "the-real-tail")
    collector.stop

    signature = collector.results(run_id: "r1").find do |r|
      r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::RepeatedParamNames", name: "rest_between")
    end

    expect(signature).not_to be_nil
    # `a` (Integer) and `b` (String) -- `b`'s own class, at index 1 rather
    # than its declared index 2. Never [Integer, Array].
    expect(signature.parameter_types).to eq(
      [Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::Nominal.new(name: "String")]
    )
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
    # a call stack, so this is zero for any implementation that doesn't
    # keep a registry of its own.
    #
    # A call stack must be recognized in *both* the shapes this code has
    # actually had: the bare Array it was before Task 022.2's redesign,
    # and the CallStackMachine it is after. Checking only for Array made
    # this example vacuous the moment the machine was extracted -- verified
    # by reintroducing the exact `@stacks[Thread.current.object_id] ||=`
    # registry round 20 removed and watching this file stay green.
    stack_like = lambda do |entry|
      entry.is_a?(Array) || entry.is_a?(Ovallsp::Observation::CallStackMachine)
    end
    retained_stacks = collector.instance_variables.sum do |name|
      case (value = collector.instance_variable_get(name))
      when Hash then value.count { |_, entry| stack_like.call(entry) }
      when Array then value.count { |entry| stack_like.call(entry) }
      else stack_like.call(value) ? 1 : 0
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

  # Real-code coverage for the CallStackMachine edge cases the redesign
  # (docs/design/tasks/022.2-collector-tracepoint-state-machine.md) is
  # explicit the abstract state machine has to handle even though its own
  # spec exercises them without any real Ruby call shape at all
  # (table rows 3-4 and 15).
  describe "recursion and Fiber isolation (state-machine redesign)" do
    def signature_for(collector, name)
      collector.results(run_id: "r1").find do |r|
        r.symbol_id == sym(kind: :instance_method, owner: "::ObservationFixture::Widget", name: name)
      end
    end

    # The one real-code shape where CallStackMachine#pop_matching's
    # matching-by-identity is load-bearing rather than redundant with
    # "push a frame for every :call". Everything else rounds 20-22 fixed
    # is caught by *either* mechanism alone (verified by reverting each
    # separately: with the other still in place, this whole file stays
    # green), so without this example a future simplification of
    # #pop_matching to a bare LIFO `pop` -- which the machine's own docs
    # explicitly invite by noting a bare pop gets table rows 1-10 right --
    # would reintroduce round 20's wrong-attribution bug with no test
    # failing anywhere.
    #
    # Collector's `:call` handling can raise (a class whose `name` raises,
    # here) and is then swallowed by #handle's blanket rescue *before*
    # CallStackMachine#push runs, while #handle_return pops unconditionally.
    # So a `:return` arrives with no matching push, in the middle of the
    # stack rather than at its outermost edge. Measured with a bare pop:
    # `calls_unnameable` reports Integer -- its callee's return value --
    # instead of the String it plainly returns.
    it "keeps a live frame when a :return arrives for a call that was never pushed" do
      collector.start
      ObservationFixture::Widget.new.calls_unnameable
      collector.stop

      signature = signature_for(collector, "calls_unnameable")

      expect(signature).not_to be_nil
      expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
      expect(signature.samples).to eq(1)
    end

    it "records direct recursion correctly, one sample per invocation" do
      collector.start
      ObservationFixture::Widget.new.factorial(4)
      collector.stop

      signature = signature_for(collector, "factorial")

      expect(signature).not_to be_nil
      expect(signature.samples).to eq(4) # factorial(4), (3), (2), (1)
      expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "Integer"))
    end

    it "records mutual recursion without either method's frame closing out the other's" do
      widget = ObservationFixture::Widget.new
      collector.start
      # mutual_a(4): a(4)->b(3)->a(2)->b(1)->a(0) [a's own base case, String],
      # passed through unchanged by every tail call above it -- a(4,2,0)
      # and b(3,1) all return String.
      widget.mutual_a(4)
      # mutual_a(3): a(3)->b(2)->a(1)->b(0) [b's own base case, Float],
      # passed through unchanged -- a(3,1) and b(2,0) all return Float.
      widget.mutual_a(3)
      collector.stop

      a_signature = signature_for(collector, "mutual_a")
      b_signature = signature_for(collector, "mutual_b")

      expect(a_signature.samples).to eq(5) # a(4), a(2), a(0), a(3), a(1)
      expect(b_signature.samples).to eq(4) # b(3), b(1), b(2), b(0)
      union = Ovallsp::Types.normalize_union(
        [Ovallsp::Types::Nominal.new(name: "String"), Ovallsp::Types::Nominal.new(name: "Float")]
      )
      expect(a_signature.return_type).to eq(union)
      expect(b_signature.return_type).to eq(union)
    end

    it "keeps a suspended Fiber's call stack isolated from the main fiber's own calls made while it's suspended" do
      collector.start
      ObservationFixture::Widget.new.fiber_worker(2)
      collector.stop

      # Both `combine` calls made inside the Fiber body and the ones made
      # on the main fiber between `resume`s must be attributed correctly
      # -- a shared/corrupted stack would misattribute at least one of
      # these four calls' return types or drop samples.
      combine_signature = signature_for(collector, "combine")
      fiber_worker_signature = signature_for(collector, "fiber_worker")

      expect(combine_signature.samples).to eq(4) # 2 inside the Fiber, 2 on the main fiber
      expect(combine_signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
      expect(fiber_worker_signature).not_to be_nil
      expect(fiber_worker_signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
    end
  end
end
