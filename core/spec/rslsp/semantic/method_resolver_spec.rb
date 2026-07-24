# frozen_string_literal: true

RSpec.describe Rslsp::Semantic::MethodResolver do
  let(:workspace_index) { Rslsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Rslsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  subject(:resolver) { described_class.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index) }

  def index_source(text, uri: "file:///a.rb", version: 1)
    document = Rslsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
    summary = Rslsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    summary
  end

  def nominal(name) = Rslsp::Types::Nominal.new(name: name)

  # "Admin < UserでAdmin.new.nameがUser#nameへ解決される"
  it "resolves a method not declared on the receiver's own class to its superclass' declaration" do
    index_source("class User\n  def name\n  end\nend\n\nclass Admin < User\nend\n")

    candidates = resolver.resolve(receiver_type: nominal("Admin"), name: "name")

    expect(candidates.size).to eq(1)
    expect(candidates.first.owner).to eq("::User")
    expect(candidates.first.origin).to eq(:superclass)
  end

  # "prepend methodがclass methodより先に解決される"
  it "resolves a prepended module's method before the class' own method, ranked first" do
    index_source(<<~RUBY)
      module Loud
        def name
        end
      end

      class Widget
        prepend Loud

        def name
        end
      end
    RUBY

    candidates = resolver.resolve(receiver_type: nominal("Widget"), name: "name")

    expect(candidates.map(&:owner)).to eq(%w[::Loud ::Widget])
    expect(candidates.first.lookup_rank).to be < candidates.last.lookup_rank
  end

  # "included moduleのmethodへdefinitionできる" -- the candidate carries
  # real declaration locations a definition handler can jump to.
  it "gives a location-bearing candidate for a method reached only through an included module" do
    index_source("module Greetable\n  def greet\n  end\nend\n\nclass User\n  include Greetable\nend\n")

    candidates = resolver.resolve(receiver_type: nominal("User"), name: "greet")

    expect(candidates.size).to eq(1)
    expect(candidates.first.owner).to eq("::Greetable")
    expect(candidates.first.declarations.map(&:first)).to eq(["file:///a.rb"])
    expect(candidates.first.declarations.first.last.location).to be_a(Hash)
  end

  # "extendされたmodule methodをclass receiverで補完できる"
  it "completes an extended module's method on the class' own (singleton) receiver" do
    index_source("module Helpers\n  def find_config\n  end\nend\n\nclass Widget\n  extend Helpers\nend\n")

    names = resolver.complete(receiver_type: nominal("Widget"), prefix: "find", context: { singleton: true })

    expect(names.map { |r| r[:name] }).to eq(["find_config"])
  end

  # "private methodを不正な明示receiver候補として上位表示しない"
  it "excludes a private method from completion when the receiver is explicit" do
    index_source(<<~RUBY)
      class Widget
        def public_thing
        end

        private

        def private_thing
        end
      end
    RUBY

    explicit = resolver.complete(receiver_type: nominal("Widget"), prefix: "", context: { implicit_self: false })
    implicit = resolver.complete(receiver_type: nominal("Widget"), prefix: "", context: { implicit_self: true })

    expect(explicit.map { |r| r[:name] }).to contain_exactly("public_thing")
    expect(implicit.map { |r| r[:name] }).to contain_exactly("public_thing", "private_thing")
  end

  # "class reopen後も同一classのmethod集合として統合される"
  it "unifies methods from a class reopened across two files into one method set" do
    index_source("class Widget\n  def a\n  end\nend\n", uri: "file:///a.rb")
    index_source("class Widget\n  def b\n  end\nend\n", uri: "file:///b.rb")

    names = resolver.complete(receiver_type: nominal("Widget"), prefix: "")

    expect(names.map { |r| r[:name] }).to contain_exactly("a", "b")
  end

  # "ancestor変更時にstale lookupが残らない"
  it "reflects an ancestor change (a removed include) immediately, with no stale candidate left behind" do
    index_source("module Greetable\n  def greet\n  end\nend\n\nclass User\n  include Greetable\nend\n", uri: "file:///user.rb")
    expect(resolver.resolve(receiver_type: nominal("User"), name: "greet")).not_to be_empty

    index_source("class User\nend\n", uri: "file:///user.rb") # include removed

    expect(resolver.resolve(receiver_type: nominal("User"), name: "greet")).to be_empty
  end

  # "unresolved ancestorでCoreが落ちず、取得可能な候補だけ返す"
  it "returns whatever is resolvable, without raising, when an ancestor is an unresolved external constant" do
    index_source("class Sub < TotallyUnknownExternalClass\n  def own_method\n  end\nend\n")

    expect { resolver.resolve(receiver_type: nominal("Sub"), name: "own_method") }.not_to raise_error
    candidates = resolver.resolve(receiver_type: nominal("Sub"), name: "own_method")
    expect(candidates.first.owner).to eq("::Sub")
  end

  describe "Union receivers" do
    it "does not mark a method available on every union member as conditional" do
      index_source(<<~RUBY)
        class User
          def name
          end
        end

        class Admin
          def name
          end
        end
      RUBY

      union = Rslsp::Types.normalize_union([nominal("User"), nominal("Admin")])
      candidates = resolver.resolve(receiver_type: union, name: "name")

      expect(candidates).to all(have_attributes(conditional: false))
      expect(candidates.map(&:owner)).to contain_exactly("::User", "::Admin")
    end

    it "marks a method available on only some union members as conditional, without omitting it" do
      index_source("class User\n  def admin_only\n  end\nend\n\nclass Admin\nend\n")
      # Rename: User happens to have a method Admin doesn't.
      union = Rslsp::Types.normalize_union([nominal("User"), nominal("Admin")])

      candidates = resolver.resolve(receiver_type: union, name: "admin_only")

      expect(candidates.size).to eq(1)
      expect(candidates.first.conditional).to be(true)
    end

    it "sorts unconditional completion names before conditional ones" do
      index_source(<<~RUBY)
        class User
          def shared
          end

          def user_only
          end
        end

        class Admin
          def shared
          end
        end
      RUBY

      union = Rslsp::Types.normalize_union([nominal("User"), nominal("Admin")])
      results = resolver.complete(receiver_type: union, prefix: "")

      expect(results.first[:name]).to eq("shared")
      expect(results.first[:conditional]).to be(false)
      expect(results.find { |r| r[:name] == "user_only" }[:conditional]).to be(true)
    end
  end

  describe "alias/alias_method" do
    it "resolves a call to the alias' new name to the same declaration as the original method" do
      index_source("class Widget\n  def name\n  end\n  alias short_name name\nend\n")

      candidates = resolver.resolve(receiver_type: nominal("Widget"), name: "short_name")

      expect(candidates.size).to eq(1)
      expect(candidates.first.symbol_id.name).to eq("name")
    end

    it "resolves alias_method's symbol-argument form the same way" do
      index_source("class Widget\n  def name\n  end\n  alias_method :sn, :name\nend\n")

      candidates = resolver.resolve(receiver_type: nominal("Widget"), name: "sn")

      expect(candidates.size).to eq(1)
      expect(candidates.first.symbol_id.name).to eq("name")
    end
  end

  it "returns no candidates for a non-Nominal, non-Union receiver (e.g. Unknown) instead of raising" do
    expect { resolver.resolve(receiver_type: Rslsp::Types::UNKNOWN, name: "anything") }.not_to raise_error
    expect(resolver.resolve(receiver_type: Rslsp::Types::UNKNOWN, name: "anything")).to eq([])
  end
end
