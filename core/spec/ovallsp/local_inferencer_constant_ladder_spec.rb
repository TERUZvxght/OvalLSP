# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# Two call-resolution ladders answered one question, and they did not
# have the same rungs.
#
# `#resolve_call` reaches the signature environment by two routes: one
# when the receiver is *written* as a constant (`Zoo.pick(1)`), decided
# on the AST; one when the receiver is a *value* whose type is a class
# object (`k = Zoo; k.pick(1)`), decided on the value. Both end in
# `#resolve_signature_call`, whose `env:` keyword is what lets it read
# the argument types at the call site and pick the overload RBS keyed on
# them (the mechanism the narrowing spec next door covers).
#
# `env:` was **optional**, defaulting to nil, and exactly one of the five
# call sites omitted it — the constant-receiver rung. So the same call
# written two ways got two different answers:
#
#     Zoo.pick(1)          # => String | Symbol   (no env: every overload
#                          #                       of the right arity)
#     k = Zoo; k.pick(1)   # => String            (env: the declared one)
#
# The union is not merely the wider of two answers. A reader cannot tell
# which of the two spellings they are being told about, and the engine
# asserts `Symbol` is possible for a call RBS says returns `String`.
#
# Ruby, which has no such distinction — a constant held in a local is the
# same object and dispatches identically:
#
#     $ ruby -e '
#     class Zoo
#       def self.pick(x) = x.is_a?(Integer) ? "s" : :sym
#     end
#     k = Zoo
#     p [Zoo.equal?(k), Zoo.pick(1).class, k.pick(1).class, k.pick("a").class]
#     '
#     # => [true, String, String, Symbol]
#     # ruby 3.4.10
#
# The fix passes `env:` at the rung that omitted it and makes the keyword
# **required**, so no future site can leave it off while its twin passes
# it. A regression test pins this one call; the required keyword is what
# stops the next one.
RSpec.describe "Ovallsp::LocalInferencer constant and value receiver ladders" do
  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "zoo.rbs"), <<~RBS)
        class Zoo
          def self.pick: (Integer) -> String
                       | (String) -> Symbol
          def self.count_of: (Integer) -> Float
        end
      RBS
      @root = root
      example.run
    end
  end

  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: @root) } }
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, signatures: signatures) }

  def type_of(source, line, character = 0)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    stack.local_inferencer.infer_at(document, { line: line, character: character }).to_s
  end

  # The defect. Written as a constant, the declared `(Integer) -> String`
  # overload is the one that applies, and it was the union that came back.
  it "narrows on the argument type when the receiver is written as a constant" do
    expect(type_of("t = Zoo.pick(1)\nt\n", 1)).to eq("String")
  end

  # The other spelling, which already answered — asserted here so the two
  # ladders are pinned as agreeing rather than each pinned alone.
  it "narrows the same way when the constant arrives through a local" do
    expect(type_of("k = Zoo\nt = k.pick(1)\nt\n", 2)).to eq("String")
  end

  it "gives the two spellings of one call the same answer" do
    constant = type_of("t = Zoo.pick(1)\nt\n", 1)
    through_local = type_of("k = Zoo\nt = k.pick(1)\nt\n", 2)

    expect(constant).to eq(through_local)
  end

  # Control, and the one that makes the two above mean something. If the
  # fix had merely made the constant rung answer the *first* declared
  # overload, or answer `String` for anything, this comes out "String"
  # and the pair above still passes. It is the second overload, keyed on
  # a String argument, and it must be selected on the argument's type.
  it "picks the String-argument overload for a String argument" do
    expect(type_of("t = Zoo.pick(\"a\")\nt\n", 1)).to eq("Symbol")
    expect(type_of("k = Zoo\nt = k.pick(\"a\")\nt\n", 2)).to eq("Symbol")
  end

  # Control, and the most important one here: **no narrowing on
  # information that is not there.** With the argument's type unknown,
  # `OverloadResolver#narrow_by_argument_types` returns its matches
  # untouched by design, so both declared returns stand. That is the
  # answer before this fix and after it, on both spellings — a category
  # the change must not move.
  #
  # It is what tells "the constant rung now reads argument types" apart
  # from "the constant rung now answers whatever the first overload
  # says". Had the fix narrowed here it would be inventing a return from
  # an argument nobody typed.
  #
  # `character: 2` puts the position on the `t`, not on the indentation.
  # Written as `character: 0` first, this example measured column 0 —
  # which is a space, and a position on whitespace answers Unknown
  # whatever the ladder does. It agreed with an expectation that was
  # also wrong, and the two errors cancelled.
  it "keeps both declared returns when the argument's type is unknown" do
    source = "def f(x)\n  t = Zoo.pick(x)\n  t\nend\n"

    expect(type_of(source, 2, 2)).to eq("String | Symbol")
  end

  # The same absence of information through the other spelling — pinned
  # so the two ladders are held together where they decline to narrow,
  # not only where they answer.
  it "keeps both declared returns through a local when the argument's type is unknown" do
    source = "def f(x)\n  k = Zoo\n  t = k.pick(x)\n  t\nend\n"

    expect(type_of(source, 3, 2)).to eq("String | Symbol")
  end

  # Control: the fix is about which overload is chosen, not about
  # whether the signature environment is reached at all. A method with a
  # single declared overload must still answer it, by both spellings —
  # a positive statement that the constant rung still consults RBS,
  # where the two examples below say only that it declines.
  it "still answers a single-overload signature by both spellings" do
    expect(type_of("t = Zoo.count_of(1)\nt\n", 1)).to eq("Float")
    expect(type_of("k = Zoo\nt = k.count_of(1)\nt\n", 2)).to eq("Float")
  end

  # The countermeasure itself, pinned.
  #
  # Every example above tests an *answer*, and none of them can see this:
  # restore `env:` to defaulting to nil and they all still pass, because
  # the call site now passes it either way. What the default cost was the
  # ability to omit it silently, so what has to be pinned is that
  # omitting it is no longer possible — the one statement that fails if
  # somebody makes the keyword optional again.
  #
  # This is the difference between pinning the fix and pinning the reason
  # the defect could exist. A regression test does the first; only this
  # does the second.
  # The inferencer comes from `build_analysis_stack`, not from a
  # constructor written here: `spec/meta/analysis_stack_spec.rb` requires
  # it, because a harness that assembles its own stack is a harness that
  # can differ from the server's, and two findings were once measured
  # against one that did. This example asks about a keyword rather than
  # an answer, so it would have been the easiest place to forget that.
  it "refuses a signature lookup that does not say what environment to read arguments in" do
    call = Prism.parse("Zoo.pick(1)").value.statements.body.first

    expect { stack.local_inferencer.send(:resolve_signature_call, Ovallsp::Types::Nominal.new(name: "Zoo"), call) }
      .to raise_error(ArgumentError, /env/)
  end

  # Control: the fix is about which overload is chosen, not about whether
  # the signature environment is consulted at all. An undeclared method
  # on the same receiver must still answer nothing, by both spellings.
  it "still declines a method the signature does not declare" do
    expect(type_of("t = Zoo.nope(1)\nt\n", 1)).to eq("Unknown")
    expect(type_of("k = Zoo\nt = k.nope(1)\nt\n", 2)).to eq("Unknown")
  end
end
