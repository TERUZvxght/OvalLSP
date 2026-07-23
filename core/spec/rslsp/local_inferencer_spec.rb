# frozen_string_literal: true

RSpec.describe Rslsp::LocalInferencer do
  subject(:inferencer) { described_class.new }

  def infer(source, line:, character:)
    document = Rslsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    inferencer.infer_at(document, { line: line, character: character })
  end

  it "infers Class.new as a Nominal reference to that class" do
    type = infer("user = User.new\n", line: 0, character: 1)

    expect(type).to eq(Rslsp::Types::Nominal.new(name: "User"))
  end

  it "infers literals as their base class" do
    expect(infer("x = 1\n", line: 0, character: 1).to_s).to eq("Integer")
    expect(infer("x = 1.5\n", line: 0, character: 1).to_s).to eq("Float")
    expect(infer("x = \"s\"\n", line: 0, character: 1).to_s).to eq("String")
    expect(infer("x = :sym\n", line: 0, character: 1).to_s).to eq("Symbol")
    expect(infer("x = true\n", line: 0, character: 1).to_s).to eq("Boolean")
    expect(infer("x = nil\n", line: 0, character: 1).to_s).to eq("nil")
  end

  it "unions ternary branches" do
    type = infer("value = cond ? User.new : Company.new\n", line: 0, character: 1)

    expect(type).to eq(Rslsp::Types.normalize_union(
                          [Rslsp::Types::Nominal.new(name: "User"), Rslsp::Types::Nominal.new(name: "Company")]
                        ))
  end

  it "unions full if/else branches the same way as a ternary" do
    source = <<~RUBY
      if cond
        value = User.new
      else
        value = Company.new
      end
    RUBY

    type = infer(source, line: 1, character: 3)
    expect(type).to eq(Rslsp::Types::Nominal.new(name: "User"))
  end

  it "removes nil from a local's type after a `return unless` guard clause" do
    source = "user = cond ? User.new : nil\nreturn unless user\nuser.name\n"

    before_guard = infer(source, line: 0, character: 1)
    after_guard = infer(source, line: 2, character: 1)

    expect(before_guard).to eq(Rslsp::Types.normalize_union([Rslsp::Types::Nominal.new(name: "User"), Rslsp::Types::NIL]))
    expect(after_guard).to eq(Rslsp::Types::Nominal.new(name: "User"))
  end

  it "narrows via `if x.nil?` guarded by an unconditional return" do
    source = "user = cond ? User.new : nil\nreturn if user.nil?\nuser.name\n"

    expect(infer(source, line: 2, character: 1)).to eq(Rslsp::Types::Nominal.new(name: "User"))
  end

  it "adds nil to the result of a safe-navigation call" do
    type = infer("user = User.new\nuser&.name\n", line: 1, character: 8)

    expect(type).to be_a(Rslsp::Types::Union)
    expect(type.members).to include(Rslsp::Types::NIL)
  end

  it "falls back to Unknown for calls it can't resolve" do
    expect(infer("x = foo\n", line: 0, character: 1)).to eq(Rslsp::Types::UNKNOWN)
  end

  it "returns Unknown, not an exception, once the step budget is exceeded" do
    tiny_budget = described_class.new(max_steps: 5)
    source = (1..50).map { |i| "v#{i} = #{i}" }.join("\n") + "\n"
    document = Rslsp::TextDocument.new(uri: "file:///b.rb", text: source, version: 1, language_id: "ruby")

    expect { tiny_budget.infer_at(document, { line: 49, character: 1 }) }.not_to raise_error
    expect(tiny_budget.infer_at(document, { line: 49, character: 1 })).to eq(Rslsp::Types::UNKNOWN)
  end

  it "returns Unknown for unparsable source instead of raising" do
    document = Rslsp::TextDocument.new(uri: "file:///c.rb", text: "def broken(\n", version: 1, language_id: "ruby")

    expect { inferencer.infer_at(document, { line: 0, character: 5 }) }.not_to raise_error
  end
end
