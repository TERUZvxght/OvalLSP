# frozen_string_literal: true

require_relative "../../fixtures/observation/sample_classes"

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

  it "does not raise even when TracePoint observes something Collector can't classify cleanly" do
    collector.start
    expect { Class.new.new.instance_eval { 1 + 1 } }.not_to raise_error
    collector.stop
  end
end
