# frozen_string_literal: true

RSpec.describe Ovallsp::Semantic::MethodResolver do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  subject(:resolver) { described_class.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index) }

  def index_source(text, uri: "file:///a.rb", version: 1)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    summary
  end

  def nominal(name) = Ovallsp::Types::Nominal.new(name: name)

  # "Admin < UserでAdmin.new.nameがUser#nameへ解決される"
  it "resolves a method not declared on the receiver's own class to its superclass' declaration" do
    index_source("class User\n  def name\n  end\nend\n\nclass Admin < User\nend\n")

    candidates = resolver.resolve(receiver_type: nominal("Admin"), name: "name")

    expect(candidates.size).to eq(1)
    expect(candidates.first.owner).to eq("::User")
    expect(candidates.first.origin).to eq(:superclass)
  end

  # A container's own methods live on its class, whatever its element type
  # is. Before this, only `ClassOf[X]` was unwrapped and every other
  # Generic fell through to `[]` -- so a workspace that reopens `Hash` got
  # definition and completion on `{}` (a Nominal) and neither on
  # `Hash.new` or on anything the container rules returned (a Generic).
  #
  # Found by independent review of 0.1.8: settling 024.2 on the generic
  # form moved values from the branch the resolver handles to the branch
  # it did not, which turned a rendering inconsistency into a lost
  # capability. The resolver is the thing that was wrong.
  it "resolves a method on a generic receiver against the class it is generic over" do
    index_source("class Hash\n  def deep_symbolize!\n  end\nend\n")
    generic = Ovallsp::Types::Generic.new(name: "Hash", type_arg: Ovallsp::Types::UNKNOWN)

    candidates = resolver.resolve(receiver_type: generic, name: "deep_symbolize!")

    expect(candidates.map(&:owner)).to eq(["::Hash"])
  end

  it "completes a generic receiver's members the same way it completes the plain type" do
    index_source("class Hash\n  def deep_symbolize!\n  end\nend\n")
    generic = Ovallsp::Types::Generic.new(name: "Hash", type_arg: Ovallsp::Types::UNKNOWN)

    generic_names = resolver.complete(receiver_type: generic, prefix: "deep").map { |r| r[:name] }

    expect(generic_names).to eq(resolver.complete(receiver_type: nominal("Hash"), prefix: "deep").map { |r| r[:name] })
    expect(generic_names).to include("deep_symbolize!")
  end

  # `Relation` and `CollectionProxy` are this engine's names for Active
  # Record shapes, not classes anyone declares. Reading them as class
  # names sends every `Model.where(...)` receiver into whatever a
  # workspace happens to call `Relation` -- a plausible name for an app to
  # use, and go-to-definition would land inside it.
  it "does not read an engine-internal generic name as a workspace class" do
    index_source("class Relation\n  def bogus_only_here\n  end\nend\n")
    relation = Ovallsp::Types::Generic.new(name: "Relation", type_arg: nominal("User"))

    expect(resolver.resolve(receiver_type: relation, name: "bogus_only_here")).to be_empty
    expect(resolver.complete(receiver_type: relation, prefix: "bog")).to be_empty
  end

  # A Union member the resolver cannot place used to be dropped, leaving
  # the remaining candidates unconditional. Reading every Generic as a
  # class made `Relation[User]` a member it *could* place -- against
  # nothing -- so `present_count < per_type.size` and the real candidate
  # came back conditional. Conditional lowers the reference's confidence
  # below what Find References and Rename require, so the call site went
  # missing from both, silently.
  it "does not make a candidate conditional because of an engine-internal generic member" do
    index_source("class User\n  def name\n  end\nend\n")
    union = Ovallsp::Types.normalize_union(
      [nominal("User"), Ovallsp::Types::Generic.new(name: "Relation", type_arg: nominal("User"))]
    )

    candidates = resolver.resolve(receiver_type: union, name: "name")

    expect(candidates.map(&:owner)).to eq(["::User"])
    expect(candidates.map(&:conditional)).to eq([false])
  end

  it "does not make a candidate conditional because of a ClassOf member" do
    index_source("class User\n  def name\n  end\nend\n\nclass Widget\nend\n")
    union = Ovallsp::Types.normalize_union(
      [nominal("User"), Ovallsp::Types::Generic.new(name: "ClassOf", type_arg: nominal("Widget"))]
    )

    candidates = resolver.resolve(receiver_type: union, name: "name")

    expect(candidates.map(&:conditional)).to eq([false])
  end

  # The one Generic that must NOT be read as its own name: `ClassOf[X]` is
  # the class object of X, so its members are X's singleton methods, and
  # reading it as a class literally called "ClassOf" would find nothing.
  it "still treats ClassOf as the class object rather than as a class named ClassOf" do
    index_source("class Widget\n  def self.build\n  end\nend\n")
    class_of = Ovallsp::Types::Generic.new(name: "ClassOf", type_arg: nominal("Widget"))

    candidates = resolver.resolve(receiver_type: class_of, name: "build")

    expect(candidates.map(&:owner)).to eq(["::Widget"])
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

      union = Ovallsp::Types.normalize_union([nominal("User"), nominal("Admin")])
      candidates = resolver.resolve(receiver_type: union, name: "name")

      expect(candidates).to all(have_attributes(conditional: false))
      expect(candidates.map(&:owner)).to contain_exactly("::User", "::Admin")
    end

    it "marks a method available on only some union members as conditional, without omitting it" do
      index_source("class User\n  def admin_only\n  end\nend\n\nclass Admin\nend\n")
      # Rename: User happens to have a method Admin doesn't.
      union = Ovallsp::Types.normalize_union([nominal("User"), nominal("Admin")])

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

      union = Ovallsp::Types.normalize_union([nominal("User"), nominal("Admin")])
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
    expect { resolver.resolve(receiver_type: Ovallsp::Types::UNKNOWN, name: "anything") }.not_to raise_error
    expect(resolver.resolve(receiver_type: Ovallsp::Types::UNKNOWN, name: "anything")).to eq([])
  end
end
