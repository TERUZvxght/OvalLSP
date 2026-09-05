# frozen_string_literal: true

require "tmpdir"

# **A constant this workspace declares is not an unresolved constant**
# (`024.330`).
#
# `#unresolved_constant_findings` decides by
# `WorkspaceIndex#resolve_type_name`, whose candidate filter is
# `%i[class module]`. A plain assignment is indexed with `kind: :constant`
# and can therefore never match, so *every* reference to one was reported:
#
#     class K
#       A = [1].freeze
#       def go = A          # cannot resolve constant `A`
#     end
#
# Measured on actionpack 8.1.3.1/lib before the fix: 1,613 constant
# references failed type resolution, and 427 of them had a workspace
# `:constant` declaration by simple name.
#
# The check is gated at mode >= `standard`, and `061` records that the
# extension sends no `diagnosticsMode`, so no user meets this today. Per
# release 0.4.0's per-check severity it becomes reachable, and a check
# cannot be offered to a user in this state.
RSpec.describe "a constant the workspace declares (024.330)" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  around do |example|
    Dir.mktmpdir do |root|
      @workspace_root = root
      example.run
    end
  end

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) do
    Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: @workspace_root) }
  end

  def context
    Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
      method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
      model_registry: model_registry, route_registry: Ovallsp::Routes::RouteRegistry.new,
      signatures: signatures, generation: 1
    )
  end

  def index(text, uri:)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    document
  end

  def unresolved(text, uri: "file:///use.rb")
    engine.analyze(document: index(text, uri: uri), semantic_context: context, mode: :standard)
          .select { |finding| finding.code == "unresolved-constant" }
          .map { |finding| finding.message[/constant `(.+)`/, 1] }
  end

  it "does not report a constant read in the body that declared it" do
    expect(unresolved("class K\n  A = [1].freeze\n  A.each { |x| x }\nend\n")).to be_empty
  end

  it "does not report a constant read from a method of the class that declared it" do
    expect(unresolved("class K\n  A = [1].freeze\n  def go = A\nend\n")).to be_empty
  end

  # Ruby resolves a constant written *before* its assignment at parse time
  # only if the assignment has run by then; for this check the question is
  # whether the workspace declares the name at all, and it does.
  it "does not report a constant declared later in the same body" do
    expect(unresolved("class K\n  def go = C\n  C = 3\nend\n")).to be_empty
  end

  it "does not report a namespaced constant another file declares" do
    index("module Config\n  TIMEOUT = 30\nend\n", uri: "file:///config.rb")

    expect(unresolved("Config::TIMEOUT\n")).to be_empty
  end

  it "does not report a top-level constant another file declares" do
    index("LIMIT = 5\n", uri: "file:///limit.rb")

    expect(unresolved("LIMIT\n")).to be_empty
  end

  # **The control.** Without it a rule that resolved every constant would
  # pass every example above, which is `024.148`'s shape.
  it "still reports a constant nothing declares" do
    expect(unresolved("class K\n  def go = DEFINITELY_ABSENT\nend\n")).to include("DEFINITELY_ABSENT")
  end

  it "still reports a namespaced constant under a namespace that declares no such name" do
    index("module Config\n  TIMEOUT = 30\nend\n", uri: "file:///config.rb")

    expect(unresolved("Config::DEFINITELY_ABSENT\n")).to include("Config::DEFINITELY_ABSENT")
  end

  # A class is already resolved by `#resolve_type_name`; this is the
  # example that would notice a fix which replaced that route rather than
  # adding beside it.
  it "still resolves a class the workspace declares" do
    index("class Widget\nend\n", uri: "file:///widget.rb")

    expect(unresolved("Widget\n")).to be_empty
  end

  # **A candidate of the right simple name is not evidence.** The first
  # version of this fix asked only whether the workspace declared *a*
  # constant of that simple name anywhere, so a bare name was accepted on
  # the strength of an unrelated class's constant, and the `nesting:` it
  # took made no difference to the answer it returned. Ruby, 3.4.10:
  #
  #   $ ruby -e '
  #   module NS
  #     class Parent; LIMIT = 3; end
  #     class Child < Parent; def go = LIMIT; end
  #   end
  #   module Foreign; LIMIT = 9; end
  #   class Consumer; def go = LIMIT; end
  #   p NS::Child.new.go
  #   p NS::Child::LIMIT
  #   begin; Consumer.new.go; rescue NameError => e; puts e.message; end
  #   '
  #   # => 3
  #   #    3
  #   #    uninitialized constant Consumer::LIMIT
  #   # ruby 3.4.10
  #
  # Both directions are wrong and they are the same mistake: the simple
  # name was standing in for a lookup nobody performed. Found by the
  # 2026-09-05 critical review, R09.
  describe "the lookup, not the simple name" do
    let(:elsewhere) { "module Foreign\n  LIMIT = 9\nend\n" }

    it "reports a bare name only another namespace declares" do
      index(elsewhere, uri: "file:///foreign.rb")

      expect(unresolved("class Consumer\n  def go = LIMIT\nend\n")).to include("LIMIT")
    end

    it "does not report a constant an ancestor declares" do
      index("class Parent\n  LIMIT = 3\nend\n", uri: "file:///parent.rb")

      expect(unresolved("class Child < Parent\n  def go = LIMIT\nend\n")).to be_empty
    end

    it "does not report a qualified name an ancestor declares" do
      index("class Parent\n  LIMIT = 3\nend\nclass Child < Parent\nend\n", uri: "file:///pair.rb")

      expect(unresolved("Child::LIMIT\n")).to be_empty
    end

    # A name written inside a namespace means that namespace's constant
    # first, and the enclosing frames after it -- Ruby's own order.
    it "does not report a constant an enclosing namespace declares" do
      source = "module NS\n  INSIDE = 2\n  class Deep\n    def go = INSIDE\n  end\nend\n"

      expect(unresolved(source)).to be_empty
    end

    it "does not report a top-level constant another file declares" do
      index("LIMIT = 5\n", uri: "file:///top.rb")

      expect(unresolved("class Consumer\n  def go = LIMIT\nend\n")).to be_empty
    end

    # **Declines rather than reports** where the chain cannot be built. A
    # superclass that is an expression leaves the ancestry unbounded, so
    # "no ancestor declares it" is an answer to a question that could not
    # be asked -- the same refusal `#ancestor_names` makes.
    it "declines when the ancestry cannot be built" do
      index(elsewhere, uri: "file:///foreign.rb")

      expect(unresolved("class Odd < Struct.new(:a)\n  def go = LIMIT\nend\n")).to be_empty
    end

    # Its control: with the ancestry buildable, the same bare name *is*
    # reported. Without this, a fix that declined on every receiver would
    # pass the example above.
    it "still reports the same name when the ancestry is ordinary" do
      index(elsewhere, uri: "file:///foreign.rb")

      expect(unresolved("class Ordinary\n  def go = LIMIT\nend\n")).to include("LIMIT")
    end
  end
end
