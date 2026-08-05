# frozen_string_literal: true

RSpec.describe Ovallsp::Semantic::MethodAnalyzer do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) { Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index) }
  let(:summary_store) { Ovallsp::Semantic::MethodSummaryStore.new }
  subject(:analyzer) do
    described_class.new(workspace_index: workspace_index, method_resolver: method_resolver, summary_store: summary_store)
  end

  def index_source(text, uri: "file:///a.rb", version: 1)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    summary
  end

  def method_symbol(owner, name, singleton: false)
    Ovallsp::Index::SymbolId.new(kind: singleton ? :singleton_method : :instance_method, owner: owner, name: name,
                                discriminator: nil)
  end

  # "method bodyから単純なNominal戻り値を推論できる"
  it "infers an implicit last-expression return type" do
    index_source("class UserFactory\n  def build_user\n    User.new\n  end\nend\n")

    summary = analyzer.summarize(symbol_id: method_symbol("::UserFactory", "build_user"))

    expect(summary.return_type.to_s).to eq("User")
    expect(summary.confidence).to eq(:high)
    expect(summary.status).to eq(:complete)
  end

  # A method's *return* type is a second reader of the same literal rules
  # `LocalInferencer` has, and it had no case for these -- so a method
  # ending in a range returned Unknown to every caller, and hovering the
  # local it was assigned to answered an empty popup. Nothing failed when
  # the cases were added, which is the other half of this example's job.
  {
    "a range" => ["1..5", "Range"],
    "a regular expression" => ["/abc/", "Regexp"],
    "a lambda" => ["->(n) { n }", "Proc"]
  }.each do |description, (source, expected)|
    it "infers the return type of a method ending in #{description}" do
      index_source("class Shapes\n  def build\n    #{source}\n  end\nend\n")

      summary = analyzer.summarize(symbol_id: method_symbol("::Shapes", "build"))

      expect(summary.return_type.to_s).to eq(expected)
    end
  end

  it "infers an explicit return" do
    index_source("class UserFactory\n  def build_user\n    return User.new\n  end\nend\n")

    summary = analyzer.summarize(symbol_id: method_symbol("::UserFactory", "build_user"))

    expect(summary.return_type.to_s).to eq("User")
  end

  # "複数return pathをUnionできる"
  it "unions multiple return paths (implicit fall-through plus an early explicit return)" do
    index_source("class UserFactory\n  def find_maybe(flag)\n    return nil unless flag\n    User.new\n  end\nend\n")

    summary = analyzer.summarize(symbol_id: method_symbol("::UserFactory", "find_maybe"))

    expect(summary.return_type).to eq(Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "User"), Ovallsp::Types::NIL]))
  end

  it "unions both arms of an if/else" do
    index_source(<<~RUBY)
      class UserFactory
        def branch_union(flag)
          if flag
            User.new
          else
            nil
          end
        end
      end
    RUBY

    summary = analyzer.summarize(symbol_id: method_symbol("::UserFactory", "branch_union"))

    expect(summary.return_type).to eq(Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "User"), Ovallsp::Types::NIL]))
  end

  it "does not union a branch that always returns early -- only its own value counts as an explicit exit" do
    index_source(<<~RUBY)
      class Guarded
        def go(flag)
          if flag
            return 1
          end
          "fallback"
        end
      end
    RUBY

    summary = analyzer.summarize(symbol_id: method_symbol("::Guarded", "go"))

    expect(summary.return_type).to eq(
      Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::Nominal.new(name: "String")])
    )
  end

  # "build_user.name`で`build_user`をUserとして解決できる" -- exercised at
  # the MethodResolver + MethodAnalyzer boundary: once build_user's own
  # summary says "User", resolving a *further* call on that result works
  # through ordinary MethodResolver#resolve against the returned type.
  it "produces a return type a subsequent call can be resolved against" do
    index_source("class User\n  def name\n  end\nend\n\nclass UserFactory\n  def build_user\n    User.new\n  end\nend\n")

    summary = analyzer.summarize(symbol_id: method_symbol("::UserFactory", "build_user"))
    candidates = method_resolver.resolve(receiver_type: summary.return_type, name: "name")

    expect(candidates.map(&:owner)).to eq(["::User"])
  end

  # "method chain途中の戻り値を次receiverへ渡せる" / "chain across 3+ methods"
  it "propagates return types through a 3+ method call chain" do
    index_source(<<~RUBY)
      class A
        def get_b
          B.new
        end
      end
      class B
        def get_c
          C.new
        end
      end
      class C
        def value
          1
        end
      end
      class Caller
        def chain
          A.new.get_b.get_c.value
        end
      end
    RUBY

    summary = analyzer.summarize(symbol_id: method_symbol("::Caller", "chain"))

    expect(summary.return_type.to_s).to eq("Integer")
    expect(summary.status).to eq(:complete)
    expect(summary.confidence).to eq(:high)
  end

  it "calls another method (dependency tracked) and keeps known evidence even when a later hop is Unknown" do
    index_source(<<~RUBY)
      class A
        def get_b
          B.new
        end
      end
      class B
      end
      class Caller
        def chain
          A.new.get_b.something_unresolvable
        end
      end
    RUBY

    summary = analyzer.summarize(symbol_id: method_symbol("::Caller", "chain"))

    expect(summary.return_type).to eq(Ovallsp::Types::UNKNOWN)
    expect(summary.confidence).to eq(:low) # degraded, but didn't raise or stop analyzing entirely
    expect(summary.dependencies).to include(method_symbol("::A", "get_b"))
  end

  # "self return"
  #
  # `SymbolId#owner` is always `::`-qualified -- that is the index's own
  # domain, enforced by `SymbolId.qualify_owner` -- and the type model's
  # is bare, which is what every other Nominal in this file asserts.
  # Spelling `self`'s type in the index's domain made it a *different*
  # Nominal from the one `Widget.new` produces, so a variable assigned
  # from both became a two-member union and the unknown-method check,
  # which needs a single Nominal, went quiet (0.1.12).
  it "resolves self to the owner's Nominal type in an instance method" do
    index_source("class Widget\n  def itself_typed\n    self\n  end\nend\n")

    summary = analyzer.summarize(symbol_id: method_symbol("::Widget", "itself_typed"))

    expect(summary.return_type).to eq(Ovallsp::Types::Nominal.new(name: "Widget"))
  end

  it "resolves self to ClassOf[Owner] in a singleton method" do
    index_source("class Widget\n  def self.itself_typed\n    self\n  end\nend\n")

    summary = analyzer.summarize(symbol_id: method_symbol("::Widget", "itself_typed", singleton: true))

    expect(summary.return_type).to eq(
      Ovallsp::Types::Generic.new(name: "ClassOf", type_arg: Ovallsp::Types::Nominal.new(name: "Widget"))
    )
  end

  # `self` and a constant receiver name the same class, so they must
  # produce the same Nominal -- the union is what the pair rules out.
  it "gives `self` and `Widget.new` one type, not a two-member union" do
    index_source(<<~RUBY)
      class Widget
        def either(flag)
          flag ? self : Widget.new
        end
      end
    RUBY

    summary = analyzer.summarize(symbol_id: method_symbol("::Widget", "either"))

    expect(summary.return_type).to eq(Ovallsp::Types::Nominal.new(name: "Widget"))
  end

  # `Prism::ConstantPathNode#full_name` answers `::Widget` for a
  # root-scoped receiver, and this fed it straight into the type model --
  # the untouched twin of the same fix in `LocalInferencer#resolve_call`.
  # Each of the three call names is a separate decision.
  it "types `::Widget.new` the same as `Widget.new`" do
    index_source("class Factory\n  def build\n    ::Widget.new\n  end\nend\n")

    summary = analyzer.summarize(symbol_id: method_symbol("::Factory", "build"))

    expect(summary.return_type).to eq(Ovallsp::Types::Nominal.new(name: "Widget"))
  end

  it "types `::Widget.find(1)` the same as `Widget.find(1)`" do
    index_source("class Factory\n  def fetch\n    ::Widget.find(1)\n  end\nend\n")

    summary = analyzer.summarize(symbol_id: method_symbol("::Factory", "fetch"))

    expect(summary.return_type).to eq(Ovallsp::Types::Nominal.new(name: "Widget"))
  end

  it "types `::Widget.find_by(...)` the same as `Widget.find_by(...)`" do
    index_source("class Factory\n  def lookup\n    ::Widget.find_by(id: 1)\n  end\nend\n")

    summary = analyzer.summarize(symbol_id: method_symbol("::Factory", "lookup"))

    expect(summary.return_type).to eq(
      Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "Widget"), Ovallsp::Types::NIL])
    )
  end

  # "direct recursion"
  it "terminates direct recursion within budget, widening to Unknown/low-confidence" do
    index_source("class Recur\n  def go\n    go\n  end\nend\n")

    summary = nil
    expect { summary = analyzer.summarize(symbol_id: method_symbol("::Recur", "go")) }.not_to raise_error

    expect(summary.status).to eq(:recursive_widened)
    expect(summary.confidence).to eq(:low)
  end

  # "mutual recursion"
  it "terminates mutual recursion within budget" do
    index_source("class Recur\n  def a\n    b\n  end\n  def b\n    a\n  end\nend\n")

    summary = nil
    expect { summary = analyzer.summarize(symbol_id: method_symbol("::Recur", "a")) }.not_to raise_error

    expect(summary.status).to eq(:recursive_widened)
  end

  # "timeout returns Unknown/partial instead of crash"
  it "widens instead of crashing or hanging when the call-chain budget is exceeded" do
    source = +"class Chain0\n  def go\n    1\n  end\nend\n"
    9.times { |i| source << "class Chain#{i + 1}\n  def go\n    Chain#{i}.new.go\n  end\nend\n" }
    index_source(source)

    summary = nil
    expect do
      summary = analyzer.summarize(symbol_id: method_symbol("::Chain9", "go"), budget: 3)
    end.not_to raise_error

    expect(summary.status).to eq(:timeout)
    expect(summary.confidence).to eq(:low)
  end

  # "summary依存先変更時に呼び出し元summaryが更新される" / "dependency invalidation"
  it "invalidates a caller's cached summary when a callee it depends on is invalidated" do
    index_source("class B\n  def value\n    1\n  end\nend\n\nclass A\n  def go\n    B.new.value\n  end\nend\n")

    a_id = method_symbol("::A", "go")
    b_id = method_symbol("::B", "value")
    analyzer.summarize(symbol_id: a_id)
    expect(summary_store.fetch(a_id)).not_to be_nil

    removed = summary_store.invalidate([b_id])

    expect(removed).to include(a_id, b_id)
    expect(summary_store.fetch(a_id)).to be_nil
  end

  # "method deletion"
  it "removes a deleted method's own cached summary via invalidate" do
    index_source("class Widget\n  def gone\n    1\n  end\nend\n")
    id = method_symbol("::Widget", "gone")
    analyzer.summarize(symbol_id: id)
    expect(summary_store.fetch(id)).not_to be_nil

    summary_store.invalidate([id])

    expect(summary_store.fetch(id)).to be_nil
  end

  # "overloaded declarations without RBS degrade conservatively"
  it "unions and lowers confidence across a reopened method with two different bodies" do
    index_source("class Widget\n  def value\n    1\n  end\nend\n", uri: "file:///a.rb")
    index_source("class Widget\n  def value\n    \"text\"\n  end\nend\n", uri: "file:///b.rb")

    summary = analyzer.summarize(symbol_id: method_symbol("::Widget", "value"))

    expect(summary.return_type).to eq(
      Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::Nominal.new(name: "String")])
    )
    expect(summary.confidence).to eq(:low)
  end

  it "returns a low-confidence, Unknown summary instead of raising for a method with no resolvable declaration" do
    bogus = method_symbol("::NoSuchClass", "no_such_method")

    expect { analyzer.summarize(symbol_id: bogus) }.not_to raise_error
    summary = analyzer.summarize(symbol_id: bogus)
    expect(summary.return_type).to eq(Ovallsp::Types::UNKNOWN)
    expect(summary.status).to eq(:partial)
  end

  it "carries evidence (dependencies), confidence, and generation on every summary" do
    index_source("class Widget\n  def value\n    1\n  end\nend\n")

    summary = analyzer.summarize(symbol_id: method_symbol("::Widget", "value"))

    expect(summary.dependencies).to eq([])
    expect(summary.confidence).to eq(:high)
    expect(summary.generation).to be_a(Integer)
  end

  describe "Rails DSL generated methods (Task 017)" do
    let(:generated_method_index) { Ovallsp::Semantic::GeneratedMethodIndex.new }
    let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
    subject(:analyzer) do
      described_class.new(workspace_index: workspace_index, method_resolver: method_resolver, summary_store: summary_store,
                           model_registry: model_registry, generated_method_index: generated_method_index)
    end

    def index_generated_source(text, uri: "file:///a.rb")
      summary = index_source(text, uri: uri)
      generated_method_index.replace_file(uri: uri, facts: summary.generated_method_facts)
      summary
    end

    it "returns an enum predicate's return type directly from the fact, without a real method body" do
      index_generated_source("class Widget\n  enum status: { active: 0, archived: 1 }\nend\n")

      summary = analyzer.summarize(symbol_id: method_symbol("::Widget", "active?"))

      expect(summary.return_type.to_s).to eq("Boolean")
      expect(summary.confidence).to eq(:high)
      expect(summary.status).to eq(:complete)
    end

    it "returns Relation[Model] for a scope" do
      index_generated_source("class Widget\n  scope :active, -> { where(active: true) }\nend\n")

      summary = analyzer.summarize(symbol_id: method_symbol("::Widget", "active", singleton: true))

      expect(summary.return_type.to_s).to eq("Relation[Widget]")
    end

    it "restores an earlier generated fact when a reopening file is removed" do
      first = index_generated_source(
        "class Widget\n  scope :active, -> { where(active: true) }\nend\n", uri: "file:///first.rb"
      )
      first_fact = first.generated_method_facts.first
      index_generated_source(
        "class Widget\n  scope :active, -> { where(visible: true) }\nend\n", uri: "file:///second.rb"
      )

      generated_method_index.remove_file("file:///second.rb")

      expect(generated_method_index.fact_for(method_symbol("::Widget", "active", singleton: true))).to eq(first_fact)
    end

    it "resolves a delegate's return type by chasing its target association's column" do
      model_registry.register_from_agent_response(
        "Widget",
        { tableName: "widgets", partial: false, columns: [],
          associations: [{ name: "company", macro: "belongs_to", className: "Company", optional: false }] }
      )
      model_registry.register_from_agent_response(
        "Company",
        { tableName: "companies", partial: false, columns: [{ name: "name", type: "string", null: false }],
          associations: [] }
      )
      index_generated_source("class Widget\n  delegate :name, to: :company\nend\n")

      summary = analyzer.summarize(symbol_id: method_symbol("::Widget", "name"))

      expect(summary.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
    end

    it "unions nil into a delegate's return type when allow_nil: true" do
      model_registry.register_from_agent_response(
        "Widget",
        { tableName: "widgets", partial: false, columns: [],
          associations: [{ name: "company", macro: "belongs_to", className: "Company", optional: true }] }
      )
      model_registry.register_from_agent_response(
        "Company",
        { tableName: "companies", partial: false, columns: [{ name: "name", type: "string", null: false }],
          associations: [] }
      )
      index_generated_source("class Widget\n  delegate :name, to: :company, allow_nil: true\nend\n")

      summary = analyzer.summarize(symbol_id: method_symbol("::Widget", "name"))

      expect(summary.return_type).to eq(
        Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "String"), Ovallsp::Types::NIL])
      )
    end

    it "widens a delegate to Unknown when its target isn't a known association" do
      index_generated_source("class Widget\n  delegate :name, to: :nonexistent_thing\nend\n")

      summary = analyzer.summarize(symbol_id: method_symbol("::Widget", "name"))

      expect(summary.return_type).to eq(Ovallsp::Types::UNKNOWN)
    end

    # The owner reached the registry through `split("::").last`, which is
    # match-by-simple-name: `Admin::Widget` is not a model at all, and it
    # borrowed the top-level `Widget`'s associations to answer with a
    # confident `String` (0.1.12). The pair is the point -- the same
    # `delegate :name, to: :company` line has to resolve in one namespace
    # and not in the other, which is what tells the two rules apart.
    it "does not resolve a namespaced class's delegate against the same-named top-level model" do
      model_registry.register_from_agent_response(
        "Widget",
        { tableName: "widgets", partial: false, columns: [],
          associations: [{ name: "company", macro: "belongs_to", className: "Company", optional: false }] }
      )
      model_registry.register_from_agent_response(
        "Company",
        { tableName: "companies", partial: false, columns: [{ name: "name", type: "string", null: false }],
          associations: [] }
      )
      index_generated_source("module Admin\n  class Widget\n    delegate :name, to: :company\n  end\nend\n")

      summary = analyzer.summarize(symbol_id: method_symbol("::Admin::Widget", "name"))

      expect(summary.return_type).to eq(Ovallsp::Types::UNKNOWN)
    end
  end
end
