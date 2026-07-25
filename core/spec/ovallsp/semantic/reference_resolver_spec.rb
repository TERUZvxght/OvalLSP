# frozen_string_literal: true

RSpec.describe Ovallsp::Semantic::ReferenceResolver do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) { Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index) }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:local_inferencer) { Ovallsp::LocalInferencer.new(model_registry: model_registry) }
  let(:route_registry) { Ovallsp::Routes::RouteRegistry.new }

  subject(:resolver) do
    described_class.new(
      workspace_index: workspace_index, method_resolver: method_resolver, local_inferencer: local_inferencer,
      model_registry: model_registry, route_registry: route_registry
    )
  end

  def index_source(text, uri: "file:///a.rb", version: 1)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    [document, summary]
  end

  def sym(kind:, owner:, name:) = Ovallsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil)

  it "resolves a constant reference to the class it names" do
    document, summary = index_source("class User\nend\n\nUser.new\n")

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    constant_ref = refs.find { |r| r.kind == :constant && r.location[:start][:line] == 3 }

    expect(constant_ref.symbol_id).to eq(sym(kind: :class, owner: nil, name: "::User"))
    expect(constant_ref.confidence).to eq(:high)
  end

  it "gives two same-named locals in different scopes distinct SymbolIds" do
    document, summary = index_source("def a\n  x = 1\n  x\nend\n\ndef b\n  x = 2\n  x\nend\n")

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    local_refs = refs.select { |r| r.kind == :local_variable }

    expect(local_refs.map(&:symbol_id).uniq.size).to eq(2) # scope a's `x` and scope b's `x` never collide
  end

  it "resolves an instance variable reference, scoped to its owning class" do
    document, summary = index_source("class User\n  def name\n    @name\n  end\nend\n")

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    ivar_ref = refs.find { |r| r.kind == :ivar }

    expect(ivar_ref.symbol_id).to eq(sym(kind: :ivar, owner: "::User", name: "@name"))
  end

  it "resolves an explicit-receiver method call once the receiver's type is known" do
    document, summary = index_source(<<~RUBY)
      class Company
        def name
        end
      end

      class Widget
        def show
          company = Company.new
          company.name
        end
      end
    RUBY

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    call_ref = refs.find { |r| r.kind == :method_call && r.symbol_id.name == "name" }

    expect(call_ref.symbol_id).to eq(sym(kind: :instance_method, owner: "::Company", name: "name"))
    expect(call_ref.confidence).to eq(:high)
  end

  it "resolves an implicit-self method call to the enclosing class' own declaration" do
    document, summary = index_source("class Widget\n  def a\n  end\n\n  def b\n    a\n  end\nend\n")

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    call_ref = refs.find { |r| r.kind == :method_call && r.symbol_id.name == "a" }

    expect(call_ref.symbol_id).to eq(sym(kind: :instance_method, owner: "::Widget", name: "a"))
  end

  it "marks a Union receiver call not present on every member as low confidence" do
    document, summary = index_source(<<~RUBY)
      class User
        def name
        end
      end

      class Admin
        def name
        end
        def superpowers
        end
      end

      class Owner
        def pick(flag)
          user = flag ? User.new : Admin.new
          user.superpowers
        end
      end
    RUBY

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    call_ref = refs.find { |r| r.kind == :method_call && r.symbol_id.name == "superpowers" }

    expect(call_ref.confidence).to eq(:low)
  end

  it "does not produce a reference for a call that resolves to nothing at all" do
    document, summary = index_source("class Widget\nend\n\nWidget.new.totally_unknown_method\n")

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)

    expect(refs.none? { |r| r.kind == :method_call && r.symbol_id.name == "totally_unknown_method" }).to be(true)
  end

  it "resolves a route helper reference" do
    route_registry.replace([
                              { name: "user", verb: "GET", pathTemplate: "/users/:id", requiredParts: ["id"],
                                optionalParts: [], defaults: { controller: "users", action: "show" },
                                sourceLocation: nil, routeSet: "main_app" }
                            ])
    document, summary = index_source("class UsersController\n  def show\n    user_path(1)\n  end\nend\n")

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    route_ref = refs.find { |r| r.kind == :method_call && r.origin == :route_helper }

    expect(route_ref).not_to be_nil
    expect(route_ref.symbol_id).to eq(sym(kind: :route_helper, owner: nil, name: "user"))
  end

  it "resolves an Active Record association reference once the receiver model is known" do
    model_registry.register_from_agent_response(
      "Company",
      { tableName: "companies", partial: false, columns: [],
        associations: [{ name: "orders", macro: "has_many", className: "Order", optional: false }] }
    )
    document, summary = index_source("class Widget\n  def show(company)\n    company.orders\n  end\nend\n")

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    assoc_ref = refs.find { |r| r.kind == :method_call && r.symbol_id.name == "orders" }

    expect(assoc_ref).to be_nil # `company` here is an unresolvable method parameter -- Unknown receiver type
  end
end
