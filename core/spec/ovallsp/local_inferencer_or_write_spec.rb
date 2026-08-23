# frozen_string_literal: true

# `024.131`. `a ||= b` is `a || (a = b)`, so the type after it is the
# union of `a`'s non-nil part and the type of `b`. `#eval_type` had cases
# for `LocalVariableWriteNode` and `InstanceVariableWriteNode` and none
# for the `OrWrite` forms, so the write was never seen and whatever the
# variable held before stood unchallenged.
#
# **The entry described this as "hovers nothing" until 0.2.14 round 3
# drove it.** It answers `nil` — a wrong answer where the entry claimed
# an absent one, which section 0 ranks the other way up. Verified
# against Ruby before the expectation was written:
#
#     b = nil
#     b ||= "x"
#     b.class    # => String
#
#     c = 1
#     c ||= "x"
#     c.class    # => Integer   (the `||=` does not run)
#
# The second is why this is a union and not a replacement: a variable
# that is definitely non-nil keeps its own type, and one that may be nil
# gains the right-hand side's.
RSpec.describe "Ovallsp::LocalInferencer and `||=`" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:stack) do
    build_analysis_stack(workspace_index: workspace_index, model_registry: Ovallsp::Models::ModelRegistry.new,
                         signatures: Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) })
  end

  def type_after(source, line:, character: 0)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    stack.local_inferencer.infer_at(document, { line: line, character: character }).to_s
  end

  it "types a nil local as the right-hand side after `||=`" do
    expect(type_after("b = nil\nb ||= \"x\"\nb\n", line: 2)).to eq("String")
  end

  it "keeps a definitely-non-nil local's own type, because the write does not run" do
    expect(type_after("c = 1\nc ||= \"x\"\nc\n", line: 2)).to eq("Integer")
  end

  # The shape the fix must not lose: a local that *may* be nil gains the
  # right-hand side without losing what it already had.
  it "unions when the local may be either" do
    source = "d = cond ? nil : 1\nd ||= \"x\"\nd\n"

    expect(type_after(source, line: 2)).to include("String")
  end

  it "does the same for an instance variable" do
    expect(type_after("@e = nil\n@e ||= \"x\"\n@e\n", line: 2)).to eq("String")
  end
end
