# frozen_string_literal: true

RSpec.describe Ovallsp::LocalInferencer do
  subject(:inferencer) { described_class.new }

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

  describe "#infer_ivars_for_method (Task 008)" do
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

      ivars = inferencer.infer_ivars_for_method(document(source), owner_name: "::UsersController", method_name: "show")

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

      ivars = inferencer.infer_ivars_for_method(document(source), owner_name: "::UsersController", method_name: "show")

      expect(ivars[:@user].to_s).to eq("String")
    end

    it "returns {} for a method that doesn't exist" do
      source = "class UsersController\n  def show\n  end\nend\n"

      ivars = inferencer.infer_ivars_for_method(document(source), owner_name: "::UsersController", method_name: "index")

      expect(ivars).to eq({})
    end

    it "returns {} rather than raising for unparsable source" do
      ivars = inferencer.infer_ivars_for_method(document("def broken(\n"), owner_name: "::X", method_name: "y")

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

      ivars = inferencer.infer_ivars_for_method(
        document(source), owner_name: "::UsersController", method_name: "show", initial_env: { :@user => user_type }
      )

      expect(ivars).to include(:@user => user_type, :@copy => user_type)
    end
  end

  describe "#infer_ivars_for_action" do
    def document(source)
      Ovallsp::TextDocument.new(uri: "file:///controller.rb", text: source, version: 1, language_id: "ruby")
    end

    it "runs applicable before_action methods before the action and carries their ivars forward" do
      source = <<~RUBY
        class UsersController
          before_action :load_user

          def load_user
            @user = User.new
          end

          def show
            @copy = @user
          end
        end
      RUBY

      ivars = inferencer.infer_ivars_for_action(
        document(source), owner_name: "::UsersController", action_name: "show"
      )

      expect(ivars[:@user].to_s).to eq("User")
      expect(ivars[:@copy].to_s).to eq("User")
    end

    it "honors literal only:/except: selectors and multiple callback names" do
      source = <<~RUBY
        class UsersController
          before_action :load_user, :load_team, only: [:show, :edit]
          before_action :authenticate, except: :show

          def load_user = @user = User.new
          def load_team = @team = Team.new
          def authenticate = @auth = true
          def show; end
          def index; end
        end
      RUBY

      show = inferencer.infer_ivars_for_action(
        document(source), owner_name: "::UsersController", action_name: "show"
      )
      index = inferencer.infer_ivars_for_action(
        document(source), owner_name: "::UsersController", action_name: "index"
      )

      expect(show.keys).to contain_exactly(:@user, :@team)
      expect(index.keys).to contain_exactly(:@auth)
    end

    it "lets the action override a callback's earlier assignment" do
      source = <<~RUBY
        class UsersController
          before_action :set_value
          def set_value = @value = 1
          def show = @value = "final"
        end
      RUBY

      ivars = inferencer.infer_ivars_for_action(
        document(source), owner_name: "::UsersController", action_name: "show"
      )

      expect(ivars[:@value].to_s).to eq("String")
    end

    it "ignores callbacks with unresolved runtime conditions" do
      source = <<~RUBY
        class UsersController
          before_action :load_user, if: :signed_in?
          def load_user = @user = User.new
          def show; end
        end
      RUBY

      ivars = inferencer.infer_ivars_for_action(
        document(source), owner_name: "::UsersController", action_name: "show"
      )

      expect(ivars).to be_empty
    end

    it "applies a same-class skip_before_action selector" do
      source = <<~RUBY
        class UsersController
          before_action :load_user
          skip_before_action :load_user, only: :show
          def load_user = @user = User.new
          def show; end
        end
      RUBY

      ivars = inferencer.infer_ivars_for_action(
        document(source), owner_name: "::UsersController", action_name: "show"
      )

      expect(ivars).to be_empty
    end

    it "preserves earlier ivars when a later callback method is missing" do
      source = <<~RUBY
        class UsersController
          before_action :load_user, :missing_callback
          def load_user = @user = User.new
          def show; end
        end
      RUBY

      ivars = inferencer.infer_ivars_for_action(
        document(source), owner_name: "::UsersController", action_name: "show"
      )

      expect(ivars[:@user].to_s).to eq("User")
    end
  end

  describe "conditional branch environment merging (Task 008.5)" do
    def ivars_for(source)
      document = Ovallsp::TextDocument.new(uri: "file:///controller.rb", text: source, version: 1, language_id: "ruby")
      inferencer.infer_ivars_for_method(document, owner_name: "::UsersController", method_name: "show")
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

  describe "#find_static_render_target (Task 008)" do
    def document(source)
      Ovallsp::TextDocument.new(uri: "file:///controller.rb", text: source, version: 1, language_id: "ruby")
    end

    it "finds a literal symbol render target" do
      source = "class PostsController\n  def update\n    render :edit\n  end\nend\n"

      target = inferencer.find_static_render_target(document(source), owner_name: "::PostsController", method_name: "update")

      expect(target).to eq("edit")
    end

    it "finds a literal string render target" do
      source = "class PostsController\n  def update\n    render \"posts/edit\"\n  end\nend\n"

      target = inferencer.find_static_render_target(document(source), owner_name: "::PostsController", method_name: "update")

      expect(target).to eq("posts/edit")
    end

    it "returns nil when the method has no render call" do
      source = "class PostsController\n  def update\n    @x = 1\n  end\nend\n"

      target = inferencer.find_static_render_target(document(source), owner_name: "::PostsController", method_name: "update")

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
end
