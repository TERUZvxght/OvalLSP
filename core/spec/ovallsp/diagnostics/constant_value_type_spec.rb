# frozen_string_literal: true

require "tmpdir"

# `024.84`. Every constant read as a **class object named after itself**:
# `MAX_RETRIES = 3` then `r = MAX_RETRIES` hovered `ClassOf[MAX_RETRIES]`,
# and so did a String, an Array, a Float and a frozen Hash.
#
# It is an assertion rather than a decline — hover tells the reader the
# constant is a class — and it propagates: anything assigned from the
# constant inherits it, `DEFAULT_NAME.` offers nothing, and the
# undefined-method check says nothing at any use.
#
# **The case that was supposed to be right was wrong too.** `ClassOf[X]`
# exists so `Widget.new` knows `Widget` is a class object. Written
# `KLASS = Widget`, the answer was `ClassOf[KLASS]` — the constant's own
# name rather than the class it holds — so even the intended behaviour
# named the wrong thing.
#
# The rule follows the assigned value where the workspace can see it.
# Where it cannot — a constant from an unread gem — `ClassOf` stays,
# because that is what makes `SomeGem::Thing.new` work and nothing here
# knows better.
RSpec.describe "the type of a constant that holds a value" do
  def hover_type(source, line, character, files: {})
    Dir.mktmpdir("constant-value-") do |root|
      signatures = Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: root) }
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index, signatures: signatures)
      parser = Ovallsp::ParserService.new
      subject_document = nil
      files.merge("subject.rb" => source).each do |name, text|
        document = Ovallsp::TextDocument.new(uri: "file://#{root}/#{name}", text: text, version: 1,
                                             language_id: "ruby")
        subject_document = document if name == "subject.rb"
        summary = parser.summarize(document)
        workspace_index.replace_file(summary)
        stack.hierarchy_index.replace_file(summary)
      end
      stack.local_inferencer.infer_at(subject_document, { line: line, character: character })&.to_s
    end
  end

  {
    "an Integer" => ["class C\n  MAX = 3\n  def go\n    r = MAX\n    r\n  end\nend\n", "Integer"],
    "a String" => ["class C\n  NAME = \"s\"\n  def go\n    n = NAME\n    n\n  end\nend\n", "String"],
    "a Float" => ["class C\n  RATE = 1.5\n  def go\n    x = RATE\n    x\n  end\nend\n", "Float"],
    "an Array" => ["class C\n  LIST = %w[a b]\n  def go\n    l = LIST\n    l\n  end\nend\n", "Array[String]"],
    "a Symbol" => ["class C\n  KEY = :k\n  def go\n    k = KEY\n    k\n  end\nend\n", "Symbol"]
  }.each do |label, (source, expected)|
    it "follows the assigned value for #{label}" do
      expect(hover_type(source, 3, 8)).to eq(expected)
    end
  end

  # **The control that `ClassOf` still exists for.** A constant that
  # names a class is a class object, and it must name the *class* rather
  # than the constant.
  it "still answers a class object for a constant that names a class, and names the class" do
    source = "class C\n  KLASS = Widget\n  def go\n    k = KLASS\n    k\n  end\nend\n"

    expect(hover_type(source, 3, 8, files: { "w.rb" => "class Widget\nend\n" })).to eq("ClassOf[Widget]")
  end

  # And the second control: a bare class name is still a class object.
  # Without this, "constants are values now" passes every example above
  # and breaks `Widget.new`.
  it "still answers a class object for the class name itself" do
    source = "class C\n  def go\n    k = Widget\n    k\n  end\nend\n"

    expect(hover_type(source, 2, 8, files: { "w.rb" => "class Widget\nend\n" })).to eq("ClassOf[Widget]")
  end

  # The third: a constant the workspace has never seen keeps the guess it
  # had, because that is what makes an unread gem's `Thing.new` work.
  it "still answers a class object for a constant it cannot see" do
    source = "class C\n  def go\n    k = SomeGem::Thing\n    k\n  end\nend\n"

    expect(hover_type(source, 2, 8)).to start_with("ClassOf[")
  end
end
