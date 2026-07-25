# frozen_string_literal: true

RSpec.describe Ovallsp::Observation::Runner do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:fixtures_root) { File.expand_path("../../fixtures/observation_runner", __dir__) }

  subject(:runner) { described_class.new(logger: logger) }

  def sym(kind:, owner:, name:) = Ovallsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil)

  it "observes a real, separately-spawned Ruby process running the workspace's own test command" do
    results = runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)

    signature = results.find { |r| r.symbol_id == sym(kind: :instance_method, owner: "::Calculator", name: "add") }
    expect(signature).not_to be_nil
    expect(signature.parameter_types).to eq([Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::Nominal.new(name: "Integer")])
    expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "Integer"))
  end

  it "returns an empty array, without raising, when the test command itself crashes" do
    results = nil
    expect { results = runner.run(command: "ruby", args: ["crash.rb"], workspace_root: fixtures_root) }.not_to raise_error

    expect(results).to eq([])
  end

  it "kills a hung test command past the timeout and returns an empty array, without raising" do
    results = nil
    expect do
      results = runner.run(command: "ruby", args: ["hang.rb"], workspace_root: fixtures_root, timeout_seconds: 1)
    end.not_to raise_error

    expect(results).to eq([])
  end

  it "never lets the spawned process' stdout/stderr reach this process' own real stdio" do
    captured = Tempfile.new("ovallsp-observation-runner-stdio")
    original_stdout_fd = STDOUT.dup
    begin
      STDOUT.reopen(captured.path, "w")
      runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)
    ensure
      STDOUT.reopen(original_stdout_fd)
      original_stdout_fd.close
    end

    captured.rewind
    expect(captured.read).not_to include("fixture test command ran")
  end
end
