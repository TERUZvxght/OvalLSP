# frozen_string_literal: true

RSpec.describe Ovallsp::Semantic::ReferenceResolver do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry) }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:method_resolver) { stack.method_resolver }
  let(:local_inferencer) { stack.local_inferencer }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
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

  # **`#resolve` is a filter_map, and until 0.3.2 nothing said so.** A
  # candidate that resolves to nothing is dropped, so the result is
  # shorter than the input and index `n` of one is not index `n` of the
  # other. Six callers respect that today by shape rather than by having
  # been told -- four pass a single-element array, two iterate -- and the
  # first to zip the two lists would be wrong on the first declining
  # candidate, in a workspace where something declines and nowhere else.
  # `024.308`.
  it "answers about the candidates it could resolve, not one entry per candidate" do
    index_source("class User\nend\n", uri: "file:///user.rb")
    # The uses live in a second file, so `User` is one candidate here
    # rather than two: a declaration is a candidate as well.
    document, summary = index_source("User.new\nDefinitelyNotDeclared.new\n", uri: "file:///uses.rb")
    candidates = summary.reference_candidates.select { |c| c.kind == :constant }

    # The control: both names are there to be asked about, so the shorter
    # answer below is the resolver declining rather than the parser
    # having found one of them.
    expect(candidates.map(&:name)).to contain_exactly("User", "DefinitelyNotDeclared")

    resolved = resolver.resolve(document, candidates, uri: "file:///uses.rb", generation: 1)

    expect(resolved.length).to eq(1)
    expect(resolved.first.symbol_id.name).to eq("::User")
  end

  it "resolves a constant reference to the class it names" do
    document, summary = index_source("class User\nend\n\nUser.new\n")

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    constant_ref = refs.find { |r| r.kind == :constant && r.location[:start][:line] == 3 }

    expect(constant_ref.symbol_id).to eq(sym(kind: :class, owner: nil, name: "::User"))
    expect(constant_ref.confidence).to eq(:high)
  end

  # **The identity a use resolves to is the identity the declaration is
  # stored under, or it names nothing.** `024.244`. A class written
  # inside a `module` body is declared with that module as its owner, and
  # this rebuilt a SymbolId from a resolved *name* and a *kind* -- two
  # projections that carry no owner -- so it had to supply one, and the
  # `nil` it supplied is right only for the compact spelling. The rebuilt
  # id matched no declaration, `Rename::Planner` found none, and
  # prepareRename refused the class outright while the identical caret on
  # the compact spelling was offered.
  #
  # Both spellings are in the one fixture so each is the other's control:
  # the compact one was already right and has to stay right, and the two
  # expected owners differ, so a fix that answered one owner for every
  # class fails here rather than passing.
  it "resolves a use of a nested class to the identity its declaration is stored under" do
    document, summary = index_source(<<~RUBY)
      module Api
        class Widget
        end
      end

      class Api2::Widget2
      end

      Api::Widget.new
      Api2::Widget2.new
    RUBY

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    nested = sym(kind: :class, owner: "::Api", name: "::Api::Widget")
    compact = sym(kind: :class, owner: nil, name: "::Api2::Widget2")

    expect(refs.select { |r| r.symbol_id.name == "::Api::Widget" }.map(&:symbol_id).uniq).to eq([nested])
    expect(refs.select { |r| r.symbol_id.name == "::Api2::Widget2" }.map(&:symbol_id).uniq).to eq([compact])
    # The half a name-only assertion cannot make: the index really holds
    # a declaration under each of those two ids.
    expect(workspace_index.declarations(nested).size).to eq(1)
    expect(workspace_index.declarations(compact).size).to eq(1)
  end

  # **A leading `::` is the whole meaning of the reference**, so the
  # nesting must not rewrite it -- the decision the constant path now
  # depends on, pinned where it is observable rather than at the guard
  # that expresses it. Both directions are Ruby's, not this engine's:
  #
  #   $ ruby -e '
  #   class Widget; def self.who = :top_level; end
  #   module Api
  #     class Widget; def self.who = :in_api; end
  #     class Caller
  #       def rooted = ::Widget.who
  #       def bare = Widget.who
  #     end
  #   end
  #   p [Api::Caller.new.rooted, Api::Caller.new.bare]
  #   '
  #   # => [:top_level, :in_api]
  #   # ruby 3.4.10
  #
  # The unrooted spelling in the same fixture is the control, and has to
  # resolve the other way.
  it "keeps a rooted constant reference rooted, whatever namespace it is written inside" do
    document, summary = index_source(<<~RUBY)
      class Widget
      end

      module Api
        class Widget
        end

        class Caller
          def rooted
            ::Widget.new
          end

          def bare
            Widget.new
          end
        end
      end
    RUBY

    refs = resolver.resolve(document, summary.reference_candidates, uri: document.uri, generation: 1)
    at = ->(line) { refs.find { |r| r.kind == :constant && r.location[:start][:line] == line }.symbol_id }

    expect(at.call(9)).to eq(sym(kind: :class, owner: nil, name: "::Widget"))
    expect(at.call(13)).to eq(sym(kind: :class, owner: "::Api", name: "::Api::Widget"))
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
