# frozen_string_literal: true

RSpec.describe Ovallsp::LocalInferencer do
  subject(:inferencer) { described_class.new }

  # The deleted `#infer_ivars_for_method` was `find_method_node` -- a
  # first-match locator deleted along with it -- followed by
  # `#infer_ivars_for_method_node`. This helper goes through `method_nodes`
  # instead, which is what `Server` itself calls, so these examples
  # exercise the path that runs rather than a second copy of it. The two
  # locators do not agree on everything (`method_nodes` is
  # last-definition-wins), which is why one fixture below had to be
  # reordered to keep distinguishing what it claims to (024.1).
  def ivars_for_method(inferencer, document, owner_name:, method_name:, initial_env: {})
    node = inferencer.method_nodes(document, owner_name: owner_name)[method_name.to_s]
    inferencer.infer_ivars_for_method_node(node, initial_env: initial_env, self_type_name: owner_name)
  end

  def infer(source, line:, character:)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    inferencer.infer_at(document, { line: line, character: character })
  end

  it "infers Class.new as a Nominal reference to that class" do
    type = infer("user = User.new\n", line: 0, character: 1)

    expect(type).to eq(Ovallsp::Types::Nominal.new(name: "User"))
  end

  # Found while building Task 014's reference resolution, the first thing
  # to query #infer_at against realistic (class-nested) source instead of
  # deliberately top-level test fixtures: #locate had no case for
  # Prism::ClassNode/ModuleNode/SingletonClassNode at all, so it could
  # never descend past the *first* class/module wrapping the query
  # position -- meaning #infer_at only ever worked for bare top-level
  # statements. Since virtually every real Ruby file wraps its code in at
  # least one class/module, this made Hover/Completion/Definition/
  # SignatureHelp (all built across Tasks 004-013 and reviewed 3 times)
  # silently non-functional for realistic source the whole time.
  describe "positions nested inside a class/module body (found during Task 014)" do
    it "resolves a local variable's type inside a method nested in a class" do
      source = "class Foo\n  def bar\n    x = 1\n    x\n  end\nend\n"

      expect(infer(source, line: 3, character: 4).to_s).to eq("Integer")
    end

    it "resolves through a module body" do
      source = "module Foo\n  def self.bar\n    x = User.new\n    x\n  end\nend\n"

      expect(infer(source, line: 3, character: 4)).to eq(Ovallsp::Types::Nominal.new(name: "User"))
    end

    it "resolves through nested class/module namespaces" do
      source = "module Outer\n  class Inner\n    def bar\n      x = 1\n      x\n    end\n  end\nend\n"

      expect(infer(source, line: 4, character: 6).to_s).to eq("Integer")
    end

    it "resolves through a `class << self` body" do
      source = "class Foo\n  class << self\n    def bar\n      x = 1\n      x\n    end\n  end\nend\n"

      expect(infer(source, line: 4, character: 6).to_s).to eq("Integer")
    end

    it "does not leak an outer class body's locals into a nested `class << self` body's fresh scope" do
      # Verified against real Ruby: `class << self` cannot see an
      # enclosing class body's own locals.
      source = "class Foo\n  x = 1\n  class << self\n    x\n  end\nend\n"

      expect(infer(source, line: 3, character: 4)).to eq(Ovallsp::Types::UNKNOWN)
    end
  end

  # Found while building Task 017: #eval_call's `node.receiver.nil?`
  # branch left `receiver_type` as nil for an implicit-self call
  # (`active?` inside a method body, not `widget.active?`), so
  # #resolve_call never even tried #resolve_instance_level for it -- the
  # single most common shape of method call in real Ruby (calling a
  # sibling/private method from within the same class) never resolved to
  # anything through #infer_at, the same class of gap as the ClassNode/
  # ModuleNode fix above, one level deeper.
  describe "implicit-self method calls (found during Task 017)" do
    def wired_inferencer
      workspace_index = Ovallsp::WorkspaceIndex.new
      hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
      method_resolver = Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
      method_analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver, summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
      [workspace_index, hierarchy_index, described_class.new(method_resolver: method_resolver, method_analyzer: method_analyzer)]
    end

    def index(workspace_index, hierarchy_index, source, uri: "file:///a.rb")
      document = Ovallsp::TextDocument.new(uri: uri, text: source, version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)
      document
    end

    it "resolves an implicit-self call to a sibling instance method's own return type" do
      workspace_index, hierarchy_index, inferencer = wired_inferencer
      source = "class Widget\n  def a\n    1\n  end\n\n  def b\n    a\n  end\nend\n"
      document = index(workspace_index, hierarchy_index, source)

      type = inferencer.infer_at(document, { line: 6, character: 4 }) # inside "a" on the call site

      expect(type.to_s).to eq("Integer")
    end

    it "resolves an implicit-self call inside a `def self.x` singleton method" do
      workspace_index, hierarchy_index, inferencer = wired_inferencer
      source = "class Widget\n  def self.a\n    1\n  end\n\n  def self.b\n    a\n  end\nend\n"
      document = index(workspace_index, hierarchy_index, source)

      type = inferencer.infer_at(document, { line: 6, character: 4 })

      expect(type.to_s).to eq("Integer")
    end

    it "resolves an explicit constant-receiver call to an ordinary (non-Active-Record) singleton method" do
      workspace_index, hierarchy_index, inferencer = wired_inferencer
      source = "class Widget\n  def self.build\n    1\n  end\nend\n\nWidget.build\n"
      document = index(workspace_index, hierarchy_index, source)

      type = inferencer.infer_at(document, { line: 6, character: 8 })

      expect(type.to_s).to eq("Integer")
    end

    it "still resolves Unknown for an implicit-self call at true top level (no enclosing class)" do
      workspace_index, hierarchy_index, inferencer = wired_inferencer
      document = index(workspace_index, hierarchy_index, "some_bare_call\n")

      type = inferencer.infer_at(document, { line: 0, character: 0 })

      expect(type).to eq(Ovallsp::Types::UNKNOWN)
    end
  end

  describe "non-ASCII text preceding the query position (Task 008.5)" do
    it "does not let a multibyte comment/string on earlier lines shift node selection" do
      source = <<~RUBY
        # 日本語コメント
        message = "日本語"
        user = User.new
        user
      RUBY

      # Query the bare `user` reference on the last line. Before the
      # byte/char offset fix, comparing a Ruby *character* offset against
      # Prism's *byte*-offset node locations would pick the wrong node
      # once enough multibyte bytes had accumulated earlier in the file.
      type = infer(source, line: 3, character: 1)

      expect(type).to eq(Ovallsp::Types::Nominal.new(name: "User"))
    end

    it "resolves correctly when the query line itself mixes ASCII and Japanese" do
      source = "x = 1 # 日本語コメント\nuser = User.new\nuser\n"

      expect(infer(source, line: 2, character: 1)).to eq(Ovallsp::Types::Nominal.new(name: "User"))
    end

    it "resolves correctly past a line containing an astral emoji character" do
      source = "label = \"😀\"\nuser = User.new\nuser\n"

      expect(infer(source, line: 2, character: 1)).to eq(Ovallsp::Types::Nominal.new(name: "User"))
    end
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

    expect(type).to eq(Ovallsp::Types.normalize_union(
                          [Ovallsp::Types::Nominal.new(name: "User"), Ovallsp::Types::Nominal.new(name: "Company")]
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
    expect(type).to eq(Ovallsp::Types::Nominal.new(name: "User"))
  end

  it "removes nil from a local's type after a `return unless` guard clause" do
    source = "user = cond ? User.new : nil\nreturn unless user\nuser.name\n"

    before_guard = infer(source, line: 0, character: 1)
    after_guard = infer(source, line: 2, character: 1)

    expect(before_guard).to eq(Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "User"), Ovallsp::Types::NIL]))
    expect(after_guard).to eq(Ovallsp::Types::Nominal.new(name: "User"))
  end

  it "narrows via `if x.nil?` guarded by an unconditional return" do
    source = "user = cond ? User.new : nil\nreturn if user.nil?\nuser.name\n"

    expect(infer(source, line: 2, character: 1)).to eq(Ovallsp::Types::Nominal.new(name: "User"))
  end

  it "adds nil to the result of a safe-navigation call" do
    type = infer("user = User.new\nuser&.name\n", line: 1, character: 8)

    expect(type).to be_a(Ovallsp::Types::Union)
    expect(type.members).to include(Ovallsp::Types::NIL)
  end

  it "falls back to Unknown for calls it can't resolve" do
    expect(infer("x = foo\n", line: 0, character: 1)).to eq(Ovallsp::Types::UNKNOWN)
  end

  it "continues inference through a loaded stdlib RBS signature" do
    signatures = Ovallsp::Signatures::Environment.new
    signatures.load(workspace_root: nil)
    signature_inferencer = described_class.new(signatures: signatures)
    document = Ovallsp::TextDocument.new(
      uri: "file:///a.rb", text: "value = \"hello\".upcase\nvalue\n", version: 1, language_id: "ruby"
    )

    type = signature_inferencer.infer_at(document, { line: 1, character: 2 })

    expect(type.to_s).to eq("String")
  end

  # 024.12, and the last piece of 024.2: one kind of value, one rendering.
  # `[]` said `Array[Unknown]` and `Hash.new` said `Hash[Unknown]` while
  # `{}` said a bare `Hash`, so hovering two spellings of "a hash whose
  # contents I cannot see" gave two different answers.
  it "renders every container literal the same way, whichever spelling produced it" do
    signatures = Ovallsp::Signatures::Environment.new
    signatures.load(workspace_root: nil)
    inferencer = described_class.new(signatures: signatures)
    document = Ovallsp::TextDocument.new(
      uri: "file:///a.rb", text: "h = {}\na = []\nn = Hash.new\nf = { a: 1 }\n", version: 1, language_id: "ruby"
    )

    expect(inferencer.infer_at(document, { line: 0, character: 1 }).to_s).to eq("Hash[Unknown]")
    expect(inferencer.infer_at(document, { line: 1, character: 1 }).to_s).to eq("Array[Unknown]")
    expect(inferencer.infer_at(document, { line: 2, character: 1 }).to_s).to eq("Hash[Unknown]")
    # Not only the empty one: the rendering changed for every hash literal.
    expect(inferencer.infer_at(document, { line: 3, character: 1 }).to_s).to eq("Hash[Unknown]")
  end

  # A container value is an instance of its class, so a method the
  # workspace adds to that class resolves on it. `MethodResolver` learned
  # this in 0.1.8; `LocalInferencer`'s own instance-level path had the same
  # gap, and 024.12 is what drives traffic into it -- `{}` used to arrive
  # here as a plain `Hash` and resolve.
  #
  # The asymmetry is what makes it easy to miss: go-to-definition and
  # completion keep working (those go through MethodResolver), while hover
  # and anything chained off the call silently degrade to Unknown.
  it "resolves a workspace method added to a container class, called on a container value" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
    source = "class Hash\n  def deep_keys = \"x\"\nend\n\nh = {}\nh.deep_keys\n"
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    resolver = Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
    analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
      workspace_index: workspace_index, method_resolver: resolver,
      summary_store: Ovallsp::Semantic::MethodSummaryStore.new
    )
    inferencer = described_class.new(method_resolver: resolver, method_analyzer: analyzer)

    expect(inferencer.infer_at(document, { line: 5, character: 4 }).to_s).to eq("String")
  end

  # `Array` is the one name that is both a real class and a container the
  # built-in rules model, so it alone decides which of the two wins. Ruby's
  # answer: a workspace that reopens `Array` and defines its own `first`
  # has replaced the one the rules describe.
  it "prefers a workspace override of a container method over the built-in rule" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
    source = "class Array\n  def first = \"x\"\nend\n\na = []\na.first\n"
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    resolver = Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
    analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
      workspace_index: workspace_index, method_resolver: resolver,
      summary_store: Ovallsp::Semantic::MethodSummaryStore.new
    )
    inferencer = described_class.new(method_resolver: resolver, method_analyzer: analyzer)

    expect(inferencer.infer_at(document, { line: 5, character: 4 }).to_s).to eq("String")
  end

  # The shapes the engine mints are not classes, so a workspace class that
  # happens to share the name must never be resolved into. Pinned here as
  # well as in MethodResolver, because this is a second consumer of the
  # same reading and the guard lives in neither of them.
  it "does not resolve a relation value into a workspace class that shares the shape's name" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
    source = "class Relation\n  def tag = \"x\"\nend\n\nclass User\nend\n"
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    resolver = Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
    analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
      workspace_index: workspace_index, method_resolver: resolver,
      summary_store: Ovallsp::Semantic::MethodSummaryStore.new
    )
    inferencer = described_class.new(method_resolver: resolver, method_analyzer: analyzer)
    relation = Ovallsp::Types::Generic.new(name: "Relation", type_arg: Ovallsp::Types::Nominal.new(name: "User"))

    expect(inferencer.send(:resolve_instance_level, relation, "tag")).to be_nil
  end

  # Runtime evidence is recorded against the class, so it applies to a
  # value typed as that class' container form too. Same gap as the one
  # above, on the other path 024.12 newly routes traffic into.
  it "applies recorded runtime evidence to a container value" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
    source = "class Hash\n  def deep_keys\n  end\nend\n\nh = {}\nh.deep_keys\n"
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    resolver = Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
    analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
      workspace_index: workspace_index, method_resolver: resolver,
      summary_store: Ovallsp::Semantic::MethodSummaryStore.new
    )
    store = Ovallsp::Observation::Store.new
    store.replace_run([
      Ovallsp::Observation::ObservedSignature.new(
        symbol_id: Ovallsp::Index::SymbolId.new(
          kind: :instance_method, owner: "::Hash", name: "deep_keys", discriminator: nil
        ),
        parameter_types: [], return_type: Ovallsp::Types::Nominal.new(name: "Symbol"),
        samples: 2, run_id: "run", code_fingerprint: "fingerprint", created_at: Time.now
      )
    ])
    inferencer = described_class.new(method_resolver: resolver, method_analyzer: analyzer, observation_store: store)

    expect(inferencer.infer_at(document, { line: 6, character: 4 }).to_s).to eq("Symbol")
  end

  # The guard belongs to every consumer of the shared reading, not just the
  # one written first. Runtime evidence recorded against a workspace class
  # named `Relation` must not leak onto an Active Record relation, which is
  # a different thing that merely shares the name.
  it "does not apply a workspace class's runtime evidence to a relation that shares its name" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
    source = "class Relation\n  def tag\n  end\nend\n"
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    resolver = Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
    analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
      workspace_index: workspace_index, method_resolver: resolver,
      summary_store: Ovallsp::Semantic::MethodSummaryStore.new
    )
    store = Ovallsp::Observation::Store.new
    store.replace_run([
      Ovallsp::Observation::ObservedSignature.new(
        symbol_id: Ovallsp::Index::SymbolId.new(
          kind: :instance_method, owner: "::Relation", name: "tag", discriminator: nil
        ),
        parameter_types: [], return_type: Ovallsp::Types::Nominal.new(name: "Symbol"),
        samples: 2, run_id: "run", code_fingerprint: "fingerprint", created_at: Time.now
      )
    ])
    inferencer = described_class.new(method_resolver: resolver, method_analyzer: analyzer, observation_store: store)
    relation = Ovallsp::Types::Generic.new(name: "Relation", type_arg: Ovallsp::Types::Nominal.new(name: "User"))
    node = Prism.parse("x.tag").value.statements.body.first

    expect(inferencer.send(:resolve_observed_call, relation, node)).to be_nil
  end

  # The same answer has to survive going through a method summary, or the
  # inconsistency simply moves one call away: hovering `{}` would say one
  # thing and hovering a method that returns `{}` another.
  it "renders a container returned by a workspace method the same way as the literal" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
    source = "class Bag\n  def empty_hash = {}\n  def empty_array = []\nend\n\nBag.new.empty_hash\nBag.new.empty_array\n"
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    resolver = Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
    analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
      workspace_index: workspace_index, method_resolver: resolver,
      summary_store: Ovallsp::Semantic::MethodSummaryStore.new
    )
    inferencer = described_class.new(method_resolver: resolver, method_analyzer: analyzer)

    expect(inferencer.infer_at(document, { line: 5, character: 12 }).to_s).to eq("Hash[Unknown]")
    expect(inferencer.infer_at(document, { line: 6, character: 12 }).to_s).to eq("Array[Unknown]")
  end

  # The other half of 024.2. A container constructor resolves through
  # RBS with its type parameters unbound, which is `Hash[Unknown]` --
  # honest, and the same rendering `[]` already produces for an empty
  # array literal. Pinned here because the union rule in Types was
  # corrected to agree with *this*, so the two must be kept in step: if
  # this ever renders as a bare `Hash`, the union rule is now the odd one
  # out rather than the other way round.
  it "renders a container constructor with its element type unknown, the way an empty literal does" do
    signatures = Ovallsp::Signatures::Environment.new
    signatures.load(workspace_root: nil)
    signature_inferencer = described_class.new(signatures: signatures)
    document = Ovallsp::TextDocument.new(
      uri: "file:///a.rb", text: "h = Hash.new\ns = Set.new\n", version: 1, language_id: "ruby"
    )

    expect(signature_inferencer.infer_at(document, { line: 0, character: 1 }).to_s).to eq("Hash[Unknown]")
    expect(signature_inferencer.infer_at(document, { line: 1, character: 1 }).to_s).to eq("Set[Unknown]")
  end

  it "substitutes a generic receiver's element type into an RBS return type" do
    signatures = Ovallsp::Signatures::Environment.new
    signatures.load(workspace_root: nil)
    signature_inferencer = described_class.new(signatures: signatures)
    document = Ovallsp::TextDocument.new(
      uri: "file:///a.rb", text: "value = [\"hello\"].sample\nvalue\n", version: 1, language_id: "ruby"
    )

    type = signature_inferencer.infer_at(document, { line: 1, character: 2 })

    expect(type.to_s).to eq("String")
  end

  it "keeps block-aware generic inference ahead of a less-specific RBS overload" do
    signatures = Ovallsp::Signatures::Environment.new
    signatures.load(workspace_root: nil)
    signature_inferencer = described_class.new(signatures: signatures)
    document = Ovallsp::TextDocument.new(
      uri: "file:///a.rb", text: "value = [1].map { |item| item.to_s }\nvalue\n", version: 1, language_id: "ruby"
    )

    expect(signature_inferencer.infer_at(document, { line: 1, character: 2 }).to_s).to eq("Array[String]")
  end

  it "never leaks an unbound RBS TypeParameter into a final type" do
    signatures = Ovallsp::Signatures::Environment.new
    signatures.load(workspace_root: nil)
    signature_inferencer = described_class.new(signatures: signatures)
    document = Ovallsp::TextDocument.new(
      uri: "file:///a.rb", text: "value = { a: 1 }.keys\nvalue\n", version: 1, language_id: "ruby"
    )

    type = signature_inferencer.infer_at(document, { line: 1, character: 2 })
    expect(type.to_s).not_to match(/\b[KEUV]\b/)
  end

  # A project signature that says `untyped` says nothing, and the `.new`
  # branch already treated it that way -- it filtered an Unknown answer out
  # and carried on to the source. Every *other* singleton call returned the
  # signature's Unknown outright, so declaring `def self.build: (...) ->
  # untyped` anywhere in a project's own `sig/` silently switched that
  # method off: the class-level finder and the source declaration were
  # never reached (024.3). Needs a project-supplied signature, so it never
  # occurs with stdlib alone.
  it "falls through an untyped project signature to the source declaration, as `.new` already did" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "gadget.rbs"), "class Gadget\n  def self.build: () -> untyped\nend\n")
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      workspace_index = Ovallsp::WorkspaceIndex.new
      hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
      source = "class Widget\nend\n\nclass Gadget\n  def self.build = Widget.new\nend\n\nGadget.build\n"
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)
      resolver = Ovallsp::Semantic::MethodResolver.new(
        workspace_index: workspace_index, hierarchy_index: hierarchy_index
      )
      analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: resolver,
        summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
      inferencer = described_class.new(
        method_resolver: resolver, method_analyzer: analyzer, signatures: signatures
      )

      expect(inferencer.infer_at(document, { line: 7, character: 8 }).to_s).to eq("Widget")
    end
  end

  it "prefers an explicit project signature over a conflicting source-body inference" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "widget.rbs"), "class Widget\n  def value: () -> String\nend\n")
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      workspace_index = Ovallsp::WorkspaceIndex.new
      hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
      source = "class Widget\n  def value = 1\nend\nWidget.new.value\n"
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)
      resolver = Ovallsp::Semantic::MethodResolver.new(
        workspace_index: workspace_index, hierarchy_index: hierarchy_index
      )
      analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: resolver,
        summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
      signature_inferencer = described_class.new(
        method_resolver: resolver, method_analyzer: analyzer, signatures: signatures
      )

      expect(signature_inferencer.infer_at(document, { line: 3, character: 12 }).to_s).to eq("String")
    end
  end

  it "applies source/RBS authority independently to every Union receiver member" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(
        File.join(root, "sig", "values.rbs"),
        "class Widget\n  def value: () -> String\nend\nclass Gadget\nend\n"
      )
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      workspace_index = Ovallsp::WorkspaceIndex.new
      hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
      source = <<~RUBY
        class Widget
          def value = :source_is_shadowed
        end
        class Gadget
          def value = 1
        end
        receiver = condition ? Widget.new : Gadget.new
        receiver.value
      RUBY
      document = Ovallsp::TextDocument.new(uri: "file:///union.rb", text: source, version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)
      resolver = Ovallsp::Semantic::MethodResolver.new(
        workspace_index: workspace_index, hierarchy_index: hierarchy_index
      )
      analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: resolver,
        summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
      union_inferencer = described_class.new(
        method_resolver: resolver, method_analyzer: analyzer, signatures: signatures
      )

      type = union_inferencer.infer_at(document, { line: 7, character: 10 })

      expect(type.to_s.split(" | ")).to contain_exactly("String", "Integer")
    end
  end

  it "falls back to every RBS overload when a positional splat makes arity unknown" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(
        File.join(root, "sig", "picker.rbs"),
        "class Picker\n  def take: () -> String\n          | (Integer) -> Integer\nend\n"
      )
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      splat_inferencer = described_class.new(signatures: signatures)
      document = Ovallsp::TextDocument.new(
        uri: "file:///splat.rb",
        text: "args = []\nvalue = Picker.new.take(*args)\nvalue\n",
        version: 1,
        language_id: "ruby"
      )

      type = splat_inferencer.infer_at(document, { line: 2, character: 2 })

      expect(type.to_s.split(" | ")).to contain_exactly("String", "Integer")
    end
  end

  it "honors an explicit singleton .new signature before the nominal constructor fallback" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "widget.rbs"), "class Widget\n  def self.new: () -> String\nend\n")
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      document = Ovallsp::TextDocument.new(
        uri: "file:///a.rb", text: "value = Widget.new\nvalue\n", version: 1, language_id: "ruby"
      )

      type = described_class.new(signatures: signatures).infer_at(document, { line: 1, character: 2 })

      expect(type.to_s).to eq("String")
    end
  end

  # Regression: consulting RBS before the nominal-constructor fallback is
  # right, but an `untyped` RBS `.new` converts to an Unknown -- which is
  # truthy, so it won the race and `Struct.new(:x)`/`Data.new` degraded
  # from `Struct`/`Data` to `Unknown`. Unknown is "no answer", not an
  # answer. (Compared by type rather than against the constant:
  # Types::Unknown defines no value equality, so any Unknown that is not
  # the frozen constant would compare unequal to it. Every producer
  # returns the constant today, so that is a guard, not a live fix.)
  it "falls back to the nominal constructor when RBS types .new as untyped" do
    Dir.mktmpdir do |root|
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      inferencer = described_class.new(signatures: signatures)

      %w[Struct Data].each do |constant|
        document = Ovallsp::TextDocument.new(
          uri: "file:///a.rb", text: "value = #{constant}.new(:x)\nvalue\n", version: 1, language_id: "ruby"
        )

        expect(inferencer.infer_at(document, { line: 1, character: 2 }).to_s).to eq(constant)
      end
    end
  end

  # Regression: overload selection was only ever tested by calling
  # OverloadResolver directly with hand-written Symbol keyword names.
  # Driven through the inferencer instead -- i.e. with the keyword names
  # Prism actually produces, which are Strings -- no keyword-bearing
  # overload could ever match, so every keyword call silently degraded to
  # the union of all overloads.
  it "selects the overload matching the call's keyword, through real Prism-parsed source" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(
        File.join(root, "sig", "picker.rbs"),
        "class Picker\n  def take: (?id: Integer) -> String\n         | (?name: String) -> Integer\nend\n"
      )
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      document = Ovallsp::TextDocument.new(
        uri: "file:///a.rb", text: "value = Picker.new.take(id: 1)\nvalue\n", version: 1, language_id: "ruby"
      )

      type = described_class.new(signatures: signatures).infer_at(document, { line: 1, character: 2 })

      expect(type.to_s).to eq("String")
    end
  end

  # Regression: `...` forwards positionals, keywords and a block, so arity
  # is not statically countable. Prism models it as a single
  # ForwardingArgumentsNode element, which was counted as one positional
  # argument -- narrowing to whichever overload takes exactly one, rather
  # than falling back to the union the way `*args` already did.
  it "does not narrow to a single overload when arguments are forwarded with `...`" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(
        File.join(root, "sig", "picker.rbs"),
        "class Picker\n  def take: () -> String\n         | (Integer) -> Integer\nend\n"
      )
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      document = Ovallsp::TextDocument.new(
        uri: "file:///a.rb",
        text: "def g(...)\n  value = Picker.new.take(...)\n  value\nend\n",
        version: 1, language_id: "ruby"
      )

      type = described_class.new(signatures: signatures).infer_at(document, { line: 2, character: 3 })

      expect(type.to_s).to eq("Integer | String")
    end
  end

  it "prefers a source override over an RBS method inherited by the receiver" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "widget.rbs"), "class Widget\nend\nclass Gadget\nend\n")
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      workspace_index = Ovallsp::WorkspaceIndex.new
      hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
      source = <<~RUBY
        class Widget
          def to_s = 1
        end
        class Gadget
          def self.new = "custom"
        end
        Widget.new.to_s
        Gadget.new
      RUBY
      document = Ovallsp::TextDocument.new(
        uri: "file:///a.rb", text: source, version: 1, language_id: "ruby"
      )
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)
      resolver = Ovallsp::Semantic::MethodResolver.new(
        workspace_index: workspace_index, hierarchy_index: hierarchy_index
      )
      analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: resolver,
        summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
      source_first = described_class.new(
        signatures: signatures, method_resolver: resolver, method_analyzer: analyzer
      )

      expect(source_first.infer_at(document, { line: 6, character: 11 }).to_s).to eq("Integer")
      expect(source_first.infer_at(document, { line: 7, character: 8 }).to_s).to eq("String")
    end
  end

  it "does not bind a method type parameter from a same-named receiver parameter" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(
        File.join(root, "sig", "box.rbs"),
        "class Box[A]\n  def receiver_value: () -> A\n  def method_value: [A] () -> A\nend\n"
      )
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      signature_inferencer = described_class.new(signatures: signatures)
      receiver = Ovallsp::Types::Generic.new(
        name: "Box", type_arg: Ovallsp::Types::Nominal.new(name: "String")
      )
      receiver_call = Prism.parse("box.receiver_value").value.statements.body.first
      method_call = Prism.parse("box.method_value").value.statements.body.first

      expect(signature_inferencer.send(:resolve_signature_call, receiver, receiver_call).to_s).to eq("String")
      expect(signature_inferencer.send(:resolve_signature_call, receiver, method_call)).to eq(Ovallsp::Types::UNKNOWN)
    end
  end

  # Regression: a Generic carries exactly one type argument, and
  # TypeConverter#convert_class_type fills it from the *last* RBS
  # argument -- `Hash[K, V]` keeps `V`. Binding it to the receiver's
  # first declared parameter therefore bound `V`'s type to `K`, which is
  # worse than answering nothing: `.keys` reported a concrete, confidently
  # wrong element type while `.values`/`.fetch` lost the answer the model
  # actually had.
  it "binds a receiver type argument to the parameter the converter kept it from" do
    document = Ovallsp::TextDocument.new(
      uri: "file:///a.rb",
      text: "tallied = [\"a\"].tally\nvalues = tallied.values\nkeys = tallied.keys\nfetched = tallied.fetch(\"a\")\n",
      version: 1, language_id: "ruby"
    )
    inferencer = described_class.new(
      signatures: Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) }
    )

    expect(inferencer.infer_at(document, { line: 0, character: 2 }).to_s).to eq("Hash[Integer]")
    expect(inferencer.infer_at(document, { line: 1, character: 2 }).to_s).to eq("Array[Integer]")
    expect(inferencer.infer_at(document, { line: 3, character: 2 }).to_s).to eq("Integer")
    # No `K` binding exists, so the honest answer is Unknown -- never
    # `Array[Integer]`, which is what binding the wrong parameter produced.
    expect(inferencer.infer_at(document, { line: 2, character: 2 }).to_s).to eq("Array[Unknown]")
  end

  # The sibling of the Struct/Data guard: an `untyped` RBS `.new` on a
  # *superclass* also converts to an Unknown, which is truthy, so without
  # the filter it wins over the nominal-constructor fallback and every
  # subclass of that base degrades to Unknown. `def self.new: (*untyped)
  # -> untyped` on a base class is ordinary in gem RBS/RBI, so this takes
  # out whole hierarchies at once.
  it "falls back to the nominal constructor when only an inherited RBS .new is untyped" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(
        File.join(root, "sig", "base.rbs"),
        "class Base\n  def self.new: () -> untyped\nend\n\nclass Child < Base\nend\n"
      )
      signatures = Ovallsp::Signatures::Environment.new
      signatures.load(workspace_root: root)
      inferencer = described_class.new(signatures: signatures)
      document = Ovallsp::TextDocument.new(
        uri: "file:///a.rb", text: "value = Child.new\nvalue\n", version: 1, language_id: "ruby"
      )

      expect(inferencer.infer_at(document, { line: 1, character: 0 }).to_s).to eq("Child")
    end
  end

  # MethodMapLocator's `class << self` guard, pinned here directly rather
  # than only through the views spec. (It once had a twin in a second
  # locator that nothing enforced; 024.1 deleted that duplicate along with
  # the callback chain it served.) A `class << self` body's `def`s are
  # receiverless exactly like instance methods, so without the guard a
  # same-named singleton method is indistinguishable from the real action
  # and can be picked as its body -- handing the view the wrong ivars.
  #
  # The singleton `show` comes *last* deliberately. MethodMapLocator is
  # last-definition-wins, so with the singleton first an unguarded locator
  # registers it and then overwrites it with the real one -- the same
  # answer either way, and the example would pass with the guard deleted.
  # (The order was the other way round when this covered the deleted
  # first-match locator, where it did distinguish them.)
  it "does not mistake a `class << self` method for the same-named instance method's body" do
    document = Ovallsp::TextDocument.new(
      uri: "file:///c.rb",
      text: <<~RUBY,
        class UsersController
          def show
            @actor = User.new
          end

          class << self
            def show
              @actor = Admin.new
            end
          end
        end
      RUBY
      version: 1, language_id: "ruby"
    )

    ivars = ivars_for_method(inferencer, document, owner_name: "::UsersController", method_name: "show")

    expect(ivars[:@actor].to_s).to eq("User")
  end

  # `arguments.pop` operated on the array Prism owns, not a copy, so
  # reading a `before_action` declaration destroyed its own `only:`/
  # `except:` selector. Nothing noticed while every caller re-parsed the
  # document first -- the tree was fresh each time -- but that is a
  # property of the callers, not of this code, and the first thing to
  # cache or re-walk a tree would have inherited a silent wrong answer.
  #
  # Asserted through the consequence rather than by inspecting the node:
  # visited twice, the same tree must say the same thing. It did not --
  # the selector was gone by the second pass, so a callback scoped to
  # `only: [:show]` was applied to `index` as well.
  it "does not consume a before_action's selector by reading it" do
    finder_class = described_class.const_get(:BeforeActionFinder)
    tree = Prism.parse(<<~RUBY).value
      class UsersController
        before_action :set_user, only: [:show]
      end
    RUBY

    first = finder_class.new("::UsersController", "index")
    tree.accept(first)
    second = finder_class.new("::UsersController", "index")
    tree.accept(second)

    expect(first.operations).to be_empty
    expect(second.operations).to eq(first.operations)
  end

  it "uses opt-in observed return evidence only when static source and RBS remain Unknown" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
    source = "class Widget\n  def value\n    unknown_runtime_value\n  end\nend\n\nWidget.new.value\n"
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    method_resolver = Ovallsp::Semantic::MethodResolver.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index
    )
    method_analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
      workspace_index: workspace_index, method_resolver: method_resolver,
      summary_store: Ovallsp::Semantic::MethodSummaryStore.new
    )
    store = Ovallsp::Observation::Store.new
    symbol_id = Ovallsp::Index::SymbolId.new(
      kind: :instance_method, owner: "::Widget", name: "value", discriminator: nil
    )
    store.replace_run([
      Ovallsp::Observation::ObservedSignature.new(
        symbol_id: symbol_id, parameter_types: [], return_type: Ovallsp::Types::Nominal.new(name: "String"),
        samples: 2, run_id: "run", code_fingerprint: "fingerprint", created_at: Time.now
      )
    ])
    observed_inferencer = described_class.new(
      method_resolver: method_resolver, method_analyzer: method_analyzer, observation_store: store
    )

    type = observed_inferencer.infer_at(document, { line: 6, character: 12 })

    expect(type.to_s).to eq("String")
  end

  it "finds observed evidence on the inherited method that Ruby lookup resolves" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
    source = <<~RUBY
      class Base
        def value = unknown_runtime_value
      end
      class Child < Base; end
      Child.new.value
    RUBY
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    resolver = Ovallsp::Semantic::MethodResolver.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index
    )
    analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
      workspace_index: workspace_index, method_resolver: resolver,
      summary_store: Ovallsp::Semantic::MethodSummaryStore.new
    )
    store = Ovallsp::Observation::Store.new
    store.replace_run([
      Ovallsp::Observation::ObservedSignature.new(
        symbol_id: Ovallsp::Index::SymbolId.new(
          kind: :instance_method, owner: "::Base", name: "value", discriminator: nil
        ),
        parameter_types: [], return_type: Ovallsp::Types::Nominal.new(name: "String"),
        samples: 1, run_id: "run", code_fingerprint: "fingerprint", created_at: Time.now
      )
    ])
    observed_inferencer = described_class.new(
      method_resolver: resolver, method_analyzer: analyzer, observation_store: store
    )

    expect(observed_inferencer.infer_at(document, { line: 4, character: 12 }).to_s).to eq("String")
  end
  it "returns Unknown, not an exception, once the step budget is exceeded" do
    tiny_budget = described_class.new(max_steps: 5)
    source = (1..50).map { |i| "v#{i} = #{i}" }.join("\n") + "\n"
    document = Ovallsp::TextDocument.new(uri: "file:///b.rb", text: source, version: 1, language_id: "ruby")

    expect { tiny_budget.infer_at(document, { line: 49, character: 1 }) }.not_to raise_error
    expect(tiny_budget.infer_at(document, { line: 49, character: 1 })).to eq(Ovallsp::Types::UNKNOWN)
  end

  it "returns Unknown for unparsable source instead of raising" do
    document = Ovallsp::TextDocument.new(uri: "file:///c.rb", text: "def broken(\n", version: 1, language_id: "ruby")

    expect { inferencer.infer_at(document, { line: 0, character: 5 }) }.not_to raise_error
  end

  describe "Active Record model resolution (Task 007)" do
    let(:model_registry) do
      registry = Ovallsp::Models::ModelRegistry.new
      registry.register_from_agent_response(
        "User",
        { tableName: "users", partial: false, columns: [],
          associations: [{ name: "company", macro: "belongs_to", className: "Company", optional: true }] }
      )
      registry.register_from_agent_response(
        "Company",
        { tableName: "companies", partial: false, columns: [{ name: "name", type: "string", null: false }],
          associations: [{ name: "orders", macro: "has_many", className: "Order", optional: false }] }
      )
      registry.register_from_agent_response(
        "Order",
        { tableName: "orders", partial: false,
          columns: [{ name: "total", type: "decimal", null: false }], associations: [] }
      )
      registry
    end
    let(:inferencer) { described_class.new(model_registry: model_registry) }

    it "infers Model.find as the model itself" do
      expect(infer("user = User.find(1)\n", line: 0, character: 1)).to eq(Ovallsp::Types::Nominal.new(name: "User"))
    end

    it "infers Model.find_by as an optional model" do
      type = infer("user = User.find_by(id: 1)\n", line: 0, character: 1)
      expect(type).to eq(Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "User"), Ovallsp::Types::NIL]))
    end

    it "infers Model.where/.all as Relation[Model]" do
      expect(infer("x = User.where(id: 1)\n", line: 0, character: 1).to_s).to eq("Relation[User]")
      expect(infer("x = User.all\n", line: 0, character: 1).to_s).to eq("Relation[User]")
    end

    it "infers a belongs_to association through a Union receiver (user.company.orders)" do
      source = "user = User.find(1)\nuser.company.orders\n"
      expect(infer(source, line: 1, character: 13).to_s).to eq("CollectionProxy[Order]")
    end

    it "infers CollectionProxy[T]#first as T | nil, matching the README MVP example" do
      source = "user = User.find(1)\nuser.company.orders.first\n"
      type = infer(source, line: 1, character: 20)
      expect(type).to eq(Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "Order"), Ovallsp::Types::NIL]))
    end

    it "infers CollectionProxy[T]#first! as T (no nil)" do
      source = "user = User.find(1)\nuser.company.orders.first!\n"
      expect(infer(source, line: 1, character: 20)).to eq(Ovallsp::Types::Nominal.new(name: "Order"))
    end

    it "infers a DB column accessor by its mapped Ruby type" do
      source = "company = User.find(1).company\ncompany.name\n"
      expect(infer(source, line: 1, character: 9).to_s).to eq("String")
    end

    it "adds nil via safe navigation on top of an already-nilable association" do
      source = "user = User.find(1)\nuser.company&.orders\n"
      expect(infer(source, line: 1, character: 15).to_s).to eq("CollectionProxy[Order] | nil")
    end

    it "does not resolve members on an unknown model" do
      expect(infer("x = Ghost.find(1)\n", line: 0, character: 1)).to eq(Ovallsp::Types::UNKNOWN)
    end

    it "adds nil to a nullable DB column's type instead of discarding the Agent's null flag (Task 008.5)" do
      model_registry.register_from_agent_response(
        "Note",
        { tableName: "notes", partial: false,
          columns: [{ name: "body", type: "string", null: true }], associations: [] }
      )
      source = "note = Note.find(1)\nnote.body\n"

      expect(infer(source, line: 1, character: 5).to_s).to eq("String | nil")
    end
  end

  describe "Generic types and block inference (Task 011)" do
    it "infers an array literal's element type from a homogeneous literal" do
      expect(infer("xs = [User.new]\n", line: 0, character: 1).to_s).to eq("Array[User]")
    end

    it "unions element types for a heterogeneous array literal" do
      type = infer("xs = [User.new, Admin.new]\n", line: 0, character: 1)
      expect(type.to_s).to eq("Array[Admin | User]")
    end

    it "widens an empty array literal's element type to Unknown rather than guessing" do
      expect(infer("xs = []\n", line: 0, character: 1).to_s).to eq("Array[Unknown]")
    end

    # "type argument explosion widening"
    it "widens a very large array literal's element type instead of building an unbounded Union" do
      elements = (1..50).map { |i| "T#{i}.new" }.join(", ")
      type = infer("xs = [#{elements}]\n", line: 0, character: 1)
      expect(type.to_s).to eq("Array[Unknown]")
    end

    # "Array[User]#map`のblock引数がUser" / "map結果がblock戻り値のArrayになる"
    it "binds a map block's parameter to the array's element type, and the result to Array[block return]" do
      source = "xs = [User.new]\nxs.map { |user| user }\n"

      block_param_type = infer(source, line: 1, character: 10) # inside `|user|`
      result_type = infer(source, line: 1, character: 3) # the `xs.map { ... }` call itself

      expect(block_param_type.to_s).to eq("User")
      expect(result_type.to_s).to eq("Array[User]")
    end

    # Regression: these three bind their result from a seed argument or
    # from the block's returned collection, not from the receiver's
    # element type. With no rule of their own they fell through to RBS --
    # whose method-level type parameters this engine does not bind -- and
    # collapsed to a bare `Unknown` once overload narrowing began picking
    # the block-taking overload. `reduce` especially is common enough
    # that an `Unknown` hover is a visible regression.
    it "binds reduce/inject to the seed argument's type, not the block's element type" do
      expect(infer("xs = [1, 2]\nxs.reduce(0) { |acc, x| acc }\n", line: 1, character: 3).to_s).to eq("Integer")
      expect(infer("xs = [1, 2]\nxs.inject(\"\") { |acc, x| acc }\n", line: 1, character: 3).to_s).to eq("String")
    end

    # Regression: both specs above return the accumulator unchanged from
    # their blocks, so neither could tell "seed wins" from "block wins" --
    # and the implementation had chosen seed-wins, which is backwards.
    # Ruby returns the *block's* last value; the seed survives only for an
    # empty receiver. `line_items.reduce(0) { |sum, i| sum + i.amount }`
    # therefore answered `Integer` for a BigDecimal sum: confidently
    # wrong, and worse than the Unknown the rule replaced. Both outcomes
    # are reachable at runtime, so the honest answer is their union.
    it "unions the block's return type into reduce's result, rather than letting the seed win" do
      source = "xs = [1, 2]\nxs.reduce(0) { |acc, x| User.new }\n"

      expect(infer(source, line: 1, character: 3).to_s.split(" | ")).to contain_exactly("Integer", "User")
    end

    # Every other spec for these rules hovers the *call*, which goes
    # through #resolve. The block parameters are answered by a separate
    # path (#block_parameter_types), and it binding arguments differently
    # is exactly the inconsistency this exists to prevent: hovering
    # `reduce(0)` said Integer while hovering its own `acc` said Unknown,
    # and the body was walked with the accumulator unbound.
    it "binds an argument-seeded block's parameters the same way the call itself resolves" do
      accumulator = infer("xs = [1, 2]\nxs.reduce(0) { |acc, x| acc }\n", line: 1, character: 18)
      memo = infer("xs = [1, 2]\nxs.each_with_object(User.new) { |x, memo| memo }\n", line: 1, character: 38)

      expect(accumulator.to_s).to eq("Integer")
      expect(memo.to_s).to eq("User")
    end

    # Unioning the block's result with the seed must drop an Unknown the
    # way every other union site in this engine does. `X | Unknown` is
    # strictly less informative than either member -- it shows the user
    # two alternatives when the truth is "unconstrained" -- and it is the
    # commonest shape there is, since `acc << x` on an untyped
    # accumulator, or any call the engine cannot resolve, lands here. It
    # also degrades completion: QueryService marks a member conditional
    # unless it is available on *every* union member, and nothing is ever
    # available on Unknown, so the whole list greys out.
    it "does not fold an unresolved block result into the seed's type" do
      source = "xs = [1, 2]\nxs.reduce(0) { |acc, x| acc.no_such_method }\n"

      expect(infer(source, line: 1, character: 3).to_s).to eq("Integer")
    end

    it "binds each_with_object to the object passed in" do
      source = "xs = [1, 2]\nxs.each_with_object(User.new) { |x, memo| memo }\n"

      expect(infer(source, line: 1, character: 3).to_s).to eq("User")
    end

    # The other direction, and the reason this is not simply "the block
    # always wins": Ruby discards an each_with_object block's value, so a
    # block returning something else must not change the answer.
    it "ignores an each_with_object block's return type, which Ruby discards" do
      source = "xs = [1, 2]\nxs.each_with_object(User.new) { |x, memo| Admin.new }\n"

      expect(infer(source, line: 1, character: 3).to_s).to eq("User")
    end

    it "does not crash and returns Unknown for a call with a block syntax error, degrading partially" do
      source = "xs = [User.new]\nxs.map { |user\n"

      expect { infer(source, line: 1, character: 0) }.not_to raise_error
    end

    it "infers each's numbered parameter (_1)" do
      expect(infer("xs = [User.new]\nxs.map { _1 }\n", line: 1, character: 9).to_s).to eq("User")
    end

    it "infers select/filter_map results" do
      expect(infer("xs = [1]\nxs.select { |x| x }\n", line: 1, character: 3).to_s).to eq("Array[Integer]")
      expect(infer("xs = [1]\nxs.filter_map { |x| x.to_s }\n", line: 1, character: 3).to_s).to eq("Array[Unknown]")
    end

    it "infers find as element type or nil" do
      type = infer("xs = [User.new]\nxs.find { |x| x }\n", line: 1, character: 3)
      expect(type).to eq(Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "User"), Ovallsp::Types::NIL]))
    end

    it "keeps outer block bindings intact across a nested block (does not clobber outer parameter names)" do
      source = "xs = [1]\nys = [\"a\"]\nresult = xs.map { |x| ys.map { |y| x } }\n"

      expect(infer(source, line: 2, character: 35).to_s).to eq("Integer") # inner block body still sees outer x
      expect(infer(source, line: 2, character: 12).to_s).to eq("Array[Array[Integer]]")
    end

    describe "Active Record generic rules" do
      let(:model_registry) do
        registry = Ovallsp::Models::ModelRegistry.new
        registry.register_from_agent_response(
          "User", { tableName: "users", partial: false, columns: [],
                    associations: [{ name: "company", macro: "belongs_to", className: "Company", optional: true }] }
        )
        registry.register_from_agent_response(
          "Company", { tableName: "companies", partial: false, columns: [],
                       associations: [{ name: "orders", macro: "has_many", className: "Order", optional: false }] }
        )
        registry
      end
      let(:inferencer) { described_class.new(model_registry: model_registry) }

      # "Relation[Order]が`first`が`Order | nil`" (verified generically for Relation[User] here)
      it "infers Relation[T]#first as T | nil, matching Array/CollectionProxy" do
        source = "users = User.where(id: 1)\nusers.first\n"
        type = infer(source, line: 1, character: 8)
        expect(type).to eq(Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "User"), Ovallsp::Types::NIL]))
      end

      it "infers Relation[T]#map with a block through the same generic rule as Array" do
        source = "users = User.where(id: 1)\nusers.map { |u| u }\n"
        expect(infer(source, line: 1, character: 6).to_s).to eq("Array[User]")
      end

      # "実際の戻り値と一致するようRails APIをfixtureで確認する": Relation#find_each
      # returns nil in real Rails (a batched, void-ish iteration method,
      # unlike #each).
      it "infers Relation[T]#find_each as nil" do
        source = "result = User.where(id: 1).find_each { |u| u }\n"
        expect(infer(source, line: 0, character: 0)).to eq(Ovallsp::Types::NIL)
      end

      # "CollectionProxy[Order]#build`がOrder"
      it "infers CollectionProxy[T]#build as T" do
        source = "orders = User.find(1).company.orders\norders.build\n"
        expect(infer(source, line: 1, character: 9)).to eq(Ovallsp::Types::Nominal.new(name: "Order"))
      end

      it "infers CollectionProxy[T]#to_a as Array[T] (generic substitution in a chained call)" do
        source = "orders = User.find(1).company.orders\norders.to_a\n"
        expect(infer(source, line: 1, character: 9).to_s).to eq("Array[Order]")
      end

      it "infers CollectionProxy[T]#each as the receiver's own type unchanged" do
        source = "orders = User.find(1).company.orders\norders.each { |o| o }\n"
        expect(infer(source, line: 1, character: 9).to_s).to eq("CollectionProxy[Order]")
      end
    end
  end

  describe "#infer_ivars_for_method_node (Task 008)" do
    def document(source)
      Ovallsp::TextDocument.new(uri: "file:///controller.rb", text: source, version: 1, language_id: "ruby")
    end

    it "returns the type of each instance variable assigned in the method" do
      source = <<~RUBY
        class UsersController
          def show
            @user = User.new
            @count = 1
          end
        end
      RUBY

      ivars = ivars_for_method(inferencer, document(source), owner_name: "::UsersController", method_name: "show")

      expect(ivars[:@user]).to eq(Ovallsp::Types::Nominal.new(name: "User"))
      expect(ivars[:@count].to_s).to eq("Integer")
    end

    it "only returns the ivar's final type when reassigned" do
      source = <<~RUBY
        class UsersController
          def show
            @user = 1
            @user = "later"
          end
        end
      RUBY

      ivars = ivars_for_method(inferencer, document(source), owner_name: "::UsersController", method_name: "show")

      expect(ivars[:@user].to_s).to eq("String")
    end

    it "returns {} for a method that doesn't exist" do
      source = "class UsersController\n  def show\n  end\nend\n"

      ivars = ivars_for_method(inferencer, document(source), owner_name: "::UsersController", method_name: "index")

      expect(ivars).to eq({})
    end

    it "returns {} rather than raising for unparsable source" do
      ivars = ivars_for_method(inferencer, document("def broken(\n"), owner_name: "::X", method_name: "y")

      expect(ivars).to eq({})
    end

    it "seeds a method with ivars inferred by an earlier callback" do
      source = <<~RUBY
        class UsersController
          def show
            @copy = @user
          end
        end
      RUBY
      user_type = Ovallsp::Types::Nominal.new(name: "User")

      ivars = ivars_for_method(inferencer,
        document(source), owner_name: "::UsersController", method_name: "show", initial_env: { :@user => user_type }
      )

      expect(ivars).to include(:@user => user_type, :@copy => user_type)
    end
  end

  describe "conditional branch environment merging (Task 008.5)" do
    def ivars_for(source)
      document = Ovallsp::TextDocument.new(uri: "file:///controller.rb", text: source, version: 1, language_id: "ruby")
      ivars_for_method(inferencer, document, owner_name: "::UsersController", method_name: "show")
    end

    def union(*names)
      Ovallsp::Types.normalize_union(names.map { |name| Ovallsp::Types::Nominal.new(name: name) })
    end

    it "unions an ivar assigned differently in each branch of if/else" do
      source = <<~RUBY
        class UsersController
          def show
            if cond
              @user = User.new
            else
              @user = Admin.new
            end
          end
        end
      RUBY

      expect(ivars_for(source)[:@user]).to eq(union("User", "Admin"))
    end

    it "unions with nil when the ivar is only assigned in the if branch" do
      source = <<~RUBY
        class UsersController
          def show
            if cond
              @user = User.new
            end
          end
        end
      RUBY

      expect(ivars_for(source)[:@user]).to eq(Ovallsp::Types.normalize_union(
                                                 [Ovallsp::Types::Nominal.new(name: "User"), Ovallsp::Types::NIL]
                                               ))
    end

    it "unions an ivar assigned differently in each branch of unless/else" do
      source = <<~RUBY
        class UsersController
          def show
            unless cond
              @user = User.new
            else
              @user = Admin.new
            end
          end
        end
      RUBY

      expect(ivars_for(source)[:@user]).to eq(union("User", "Admin"))
    end

    it "checks each elsif's own predicate rather than skipping straight to its body" do
      source = <<~RUBY
        class UsersController
          def show
            if a
              @user = User.new
            elsif b
              @user = Admin.new
            else
              @user = Guest.new
            end
          end
        end
      RUBY

      expect(ivars_for(source)[:@user]).to eq(union("User", "Admin", "Guest"))
    end

    it "unions across a modifier if assignment (implicit nil else)" do
      source = <<~RUBY
        class UsersController
          def show
            @user = User.new if cond
          end
        end
      RUBY

      expect(ivars_for(source)[:@user]).to eq(Ovallsp::Types.normalize_union(
                                                 [Ovallsp::Types::Nominal.new(name: "User"), Ovallsp::Types::NIL]
                                               ))
    end

    it "unions across a modifier unless assignment (implicit nil else)" do
      source = <<~RUBY
        class UsersController
          def show
            @user = User.new unless cond
          end
        end
      RUBY

      expect(ivars_for(source)[:@user]).to eq(Ovallsp::Types.normalize_union(
                                                 [Ovallsp::Types::Nominal.new(name: "User"), Ovallsp::Types::NIL]
                                               ))
    end

    it "only keeps the else branch's assignment when the if branch unconditionally returns" do
      source = <<~RUBY
        class UsersController
          def show
            if cond
              return
            else
              @user = Admin.new
            end
          end
        end
      RUBY

      expect(ivars_for(source)[:@user]).to eq(Ovallsp::Types::Nominal.new(name: "Admin"))
    end

    it "only keeps the if branch's assignment when the else branch unconditionally raises" do
      source = <<~RUBY
        class UsersController
          def show
            if cond
              @user = User.new
            else
              raise "no user"
            end
          end
        end
      RUBY

      expect(ivars_for(source)[:@user]).to eq(Ovallsp::Types::Nominal.new(name: "User"))
    end

    it "keeps a separately-assigned ivar out of the merge when only one branch touches it" do
      source = <<~RUBY
        class UsersController
          def show
            @count = 1
            if cond
              @user = User.new
            else
              @user = Admin.new
            end
          end
        end
      RUBY

      ivars = ivars_for(source)
      expect(ivars[:@user]).to eq(union("User", "Admin"))
      expect(ivars[:@count].to_s).to eq("Integer")
    end
  end

  describe "#static_render_target_for_node (Task 008)" do
    def document(source)
      Ovallsp::TextDocument.new(uri: "file:///controller.rb", text: source, version: 1, language_id: "ruby")
    end

    it "finds a literal symbol render target" do
      source = "class PostsController\n  def update\n    render :edit\n  end\nend\n"

      target = inferencer.static_render_target_for_node(inferencer.method_nodes(document(source), owner_name: "::PostsController")["update"])

      expect(target).to eq("edit")
    end

    it "finds a literal string render target" do
      source = "class PostsController\n  def update\n    render \"posts/edit\"\n  end\nend\n"

      target = inferencer.static_render_target_for_node(inferencer.method_nodes(document(source), owner_name: "::PostsController")["update"])

      expect(target).to eq("posts/edit")
    end

    it "returns nil when the method has no render call" do
      source = "class PostsController\n  def update\n    @x = 1\n  end\nend\n"

      target = inferencer.static_render_target_for_node(inferencer.method_nodes(document(source), owner_name: "::PostsController")["update"])

      expect(target).to be_nil
    end
  end

  # A follow-up review of Tasks 009-013 found MethodAnalyzer/MethodSummaryStore
  # (Task 010) built and unit-tested, but never actually consulted by
  # LocalInferencer -- a plain (non-Active-Record) method call resolved to
  # Unknown even when its return type was staticly inferable, silently
  # defeating "current_user.company.orders.first.total"-style call chains
  # everywhere except through Active Record's own DSL surface.
  describe "resolving a plain source-declared method call through MethodResolver/MethodAnalyzer (Task 013 review fix)" do
    def wired_inferencer(source, uri: "file:///a.rb")
      document = Ovallsp::TextDocument.new(uri: uri, text: source, version: 1, language_id: "ruby")
      workspace_index = Ovallsp::WorkspaceIndex.new
      hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)

      method_resolver = Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
      summary_store = Ovallsp::Semantic::MethodSummaryStore.new
      method_analyzer = Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver, summary_store: summary_store
      )

      described_class.new(method_resolver: method_resolver, method_analyzer: method_analyzer)
    end

    it "resolves a method call's type through its body's return-type analysis, not just Active Record columns" do
      source = <<~RUBY
        class Company
          def name
            "acme"
          end
        end

        class Widget
          def company
            Company.new
          end
        end

        widget = Widget.new
        widget.company
      RUBY

      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
      type = wired_inferencer(source).infer_at(document, { line: 13, character: 9 }) # inside "widget.company"

      expect(type).to eq(Ovallsp::Types::Nominal.new(name: "Company"))
    end

    it "resolves a full call chain, one hop at a time, through plain methods" do
      source = <<~RUBY
        class Company
          def name
            "acme"
          end
        end

        class Widget
          def company
            Company.new
          end
        end

        widget = Widget.new
        widget.company.name
      RUBY

      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
      type = wired_inferencer(source).infer_at(document, { line: 13, character: 17 }) # inside "...company.name"

      expect(type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
    end

    it "still resolves Unknown for a plain method call when method_resolver/method_analyzer aren't wired up (default behavior unchanged)" do
      source = "class Widget\n  def build\n    1\n  end\nend\n\nWidget.new.build\n"
      type = infer(source, line: 6, character: 13)

      expect(type).to eq(Ovallsp::Types::UNKNOWN)
    end
  end

  # Completion from a bare prefix needs the *names* in scope, not the
  # type of one expression, and nothing exposed them: `locate` already
  # threads an environment down to the cursor exactly as `eval_type`
  # would, but `infer_at` throws it away and returns only the type it
  # arrived at. `scope_at` returns that environment instead (0.2.0).
  describe "#scope_at (0.2.0)" do
    def document(source)
      Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    end

    # Line/character of the `HERE` marker, which is removed from the
    # source. Not `|`: a block parameter list contains one, and the first
    # fixture with a block silently measured a position inside `|entry|`
    # instead of inside the body.
    def scope_for(source)
      line = source.lines.index { |l| l.include?("HERE") }
      character = source.lines[line].index("HERE")
      inferencer.scope_at(document(source.sub("HERE", "")), { line: line, character: character })
    end

    it "reports a local assigned before the cursor, with its inferred type" do
      scope = scope_for(<<~RUBY)
        user = User.new
        HERE
      RUBY

      expect(scope.locals["user"].to_s).to eq("User")
    end

    it "does not report a local assigned only after the cursor" do
      scope = scope_for(<<~RUBY)
        HERE
        later = User.new
      RUBY

      expect(scope.locals).not_to have_key("later")
    end

    it "reports the enclosing method's parameters" do
      scope = scope_for(<<~RUBY)
        class UsersController
          def show(id, scope: nil)
            HERE
          end
        end
      RUBY

      expect(scope.locals.keys).to include("id", "scope")
    end

    it "does not leak a local out of the method that declared it" do
      scope = scope_for(<<~RUBY)
        class UsersController
          def show
            inner = User.new
          end

          def index
            HERE
          end
        end
      RUBY

      expect(scope.locals).not_to have_key("inner")
    end

    it "reports the enclosing class as the self type" do
      scope = scope_for(<<~RUBY)
        class UsersController
          def show
            HERE
          end
        end
      RUBY

      expect(scope.self_type.to_s).to eq("UsersController")
    end

    it "reports ClassOf for a singleton method's self type" do
      scope = scope_for(<<~RUBY)
        class UsersController
          def self.build
            HERE
          end
        end
      RUBY

      expect(scope.self_type.to_s).to eq("ClassOf[UsersController]")
    end

    it "reports a block parameter bound by the enclosing block" do
      scope = scope_for(<<~RUBY)
        users = [User.new]
        users.each do |entry|
          HERE
        end
      RUBY

      expect(scope.locals.keys).to include("entry")
    end

    # `locals` feeds completion for a bare prefix, and `@user` is never
    # what a bare prefix means -- an ivar is typed with its own sigil, and
    # offering it here puts it in front of a user who typed `us`.
    it "does not report an instance variable as a local" do
      scope = scope_for(<<~RUBY)
        class UsersController
          def show
            @user = User.new
            HERE
          end
        end
      RUBY

      expect(scope.locals).not_to have_key("@user")
      expect(scope.locals).not_to have_key(:@user)
    end

    # `capture_scope` copies the whole environment, and `locate` calls it
    # once per step of the descent. `infer_at` walks the same path and
    # wants none of it, so the flag is a cost decision -- it changes no
    # answer, which is why nothing else here can distinguish it.
    it "does not build scope snapshots for an ordinary #infer_at" do
      doc = document("class UsersController\n  def show\n    user = User.new\n    user\n  end\nend\n")

      expect(inferencer).not_to receive(:capture_scope)

      inferencer.infer_at(doc, { line: 3, character: 5 })
    end

    it "reports no self type at the top level of a file" do
      scope = scope_for(<<~RUBY)
        user = User.new
        HERE
      RUBY

      expect(scope.self_type).to be_nil
    end
  end

  describe "#infer_at max_steps override (Task 013 review fix)" do
    it "uses the per-call max_steps instead of the constructor default when given" do
      # A long chain of statements, each one costing at least one #step! --
      # comfortably exceeds a tiny per-call budget while staying well under
      # the constructor's own (much larger) default.
      source = (["x = 1"] * 50).join("\n") + "\nx\n"

      type = infer(source, line: 50, character: 0)
      expect(type.to_s).to eq("Integer") # plenty of budget by default

      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
      widened = inferencer.infer_at(document, { line: 50, character: 0 }, max_steps: 3)
      expect(widened).to eq(Ovallsp::Types::UNKNOWN) # budget exhausted -> degrades, doesn't raise
    end
  end

  # `parameter_env` listed requireds, optionals, keywords, rest, keyword
  # rest and block -- and not `posts`, the required parameters that come
  # *after* a splat. `def go(a, *rest, z)` is legal Ruby and `z` was
  # missing from the locals completion offers.
  it "offers a required parameter that follows a splat" do
    document = Ovallsp::TextDocument.new(
      uri: "file:///a.rb", version: 1, language_id: "ruby",
      text: "def go(alpha, *rest, omega)\n  \nend\n"
    )

    locals = described_class.new.scope_at(document, { line: 1, character: 2 }).locals

    expect(locals.keys.map(&:to_s)).to include("omega")
  end

  # `infer_at` parses the document, and the argument-type check asks it
  # once per positional argument, so the parse is remembered. The key has
  # to be the document, not merely "there is a cached tree": two files
  # open at once, both at version 1, would otherwise answer each other's
  # question -- and a hover would report a type from a different file.
  describe "the remembered parse" do
    def doc(uri, text) = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")

    it "does not answer one document's question from another's tree" do
      inferencer = described_class.new
      first = doc("file:///a.rb", "x = 1\nx\n")
      second = doc("file:///b.rb", "y = \"s\"\ny\n")

      inferencer.infer_at(first, { line: 1, character: 0 })

      expect(inferencer.infer_at(second, { line: 1, character: 0 }).to_s).to eq("String")
    end

    # The point of remembering it: the argument-type check asks for a type
    # at each positional argument of each call, and each ask parsed the
    # whole file again.
    it "parses the document once however many times it is asked" do
      inferencer = described_class.new
      document = doc("file:///a.rb", "x = 1\nx\n")
      parses = 0
      allow(Prism).to receive(:parse).and_wrap_original do |original, *args|
        parses += 1
        original.call(*args)
      end

      5.times { inferencer.infer_at(document, { line: 1, character: 0 }) }

      expect(parses).to eq(1)
    end

    it "re-parses when the same document's text changes" do
      inferencer = described_class.new
      before = doc("file:///a.rb", "x = 1\nx\n")
      after = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: "x = \"s\"\nx\n", version: 1,
                                        language_id: "ruby")

      inferencer.infer_at(before, { line: 1, character: 0 })

      expect(inferencer.infer_at(after, { line: 1, character: 0 }).to_s).to eq("String")
    end
  end
end
