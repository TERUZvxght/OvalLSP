# frozen_string_literal: true

RSpec.describe Ovallsp::Semantic::QueryService do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index, signatures: signatures) }
  let(:method_resolver) { Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index) }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:local_inferencer) { Ovallsp::LocalInferencer.new(model_registry: model_registry) }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) } }

  subject(:service) do
    described_class.new(
      local_inferencer: local_inferencer, method_resolver: method_resolver, model_registry: model_registry,
      signatures: signatures, workspace_index: workspace_index
    )
  end

  def index_source(text, uri: "file:///a.rb", version: 1)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  def nominal(name) = Ovallsp::Types::Nominal.new(name: name)

  describe "#type_at" do
    it "delegates straight to LocalInferencer, so hover/completion never see different receiver types for the same expression" do
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: "user = User.new\n", version: 1, language_id: "ruby")

      type = service.type_at(document, { line: 0, character: 1 })

      expect(type).to eq(nominal("User"))
    end
  end

  describe "#members_of" do
    it "ranks source-declared members first, ahead of a same-named RBS/stdlib member" do
      index_source("class Widget\n  def upcase\n  end\nend\n")

      members = service.members_of(nominal("Widget"), prefix: "up")

      expect(members.first.name).to eq("upcase")
      expect(members.first.origin).to eq(:source)
    end

    it "includes Active Record column/association members for a known model" do
      model_registry.register_from_agent_response(
        "User",
        { tableName: "users", partial: false,
          columns: [{ name: "email", type: "string", nullable: false }],
          associations: [{ name: "company", macro: "belongs_to", className: "Company", optional: true }] }
      )

      members = service.members_of(nominal("User"), prefix: "")
      names = members.map(&:name)

      expect(names).to include("email", "company")
      expect(members.find { |m| m.name == "email" }.origin).to eq(:model_column)
      expect(members.find { |m| m.name == "company" }.origin).to eq(:model_association)
    end

    it "falls back to RBS/stdlib members when nothing else has a match" do
      members = service.members_of(nominal("String"), prefix: "upca")

      expect(members.map(&:name)).to include("upcase")
      expect(members.find { |m| m.name == "upcase" }.origin).to eq(:signature)
    end

    it "marks a member absent from every Union member as conditional and sorts it after unconditional ones" do
      index_source("class User\n  def name\n  end\nend\n\nclass Admin\n  def name\n  end\n  def superpowers\n  end\nend\n")

      union = Ovallsp::Types.normalize_union([nominal("User"), nominal("Admin")])
      members = service.members_of(union, prefix: "")

      superpowers = members.find { |m| m.name == "superpowers" }
      name = members.find { |m| m.name == "name" }
      expect(superpowers.conditional).to be(true)
      expect(name.conditional).to be(false)
      expect(members.index(name)).to be < members.index(superpowers)
    end

    it "marks Active Record and RBS members conditional when only one Union member has them" do
      model_registry.register_from_agent_response(
        "User",
        { tableName: "users", partial: false, columns: [{ name: "email", type: "string", nullable: false }],
          associations: [] }
      )

      union = Ovallsp::Types.normalize_union([nominal("User"), nominal("String")])
      members = service.members_of(union, prefix: "")

      expect(members.find { |member| member.name == "email" }.conditional).to be(true)
      expect(members.find { |member| member.name == "upcase" }.conditional).to be(true)
    end

    it "keeps members conditional on a nilable receiver" do
      index_source("class User\n  def name\n  end\nend\n")
      receiver = Ovallsp::Types.normalize_union([nominal("User"), Ovallsp::Types::NIL])

      name = service.members_of(receiver, prefix: "name").find { |member| member.name == "name" }

      expect(name.conditional).to be(true)
    end

    # `conditional` asks how many *branches* of the Union have the name,
    # which is not the same question as how many owners declare it: `Bag`
    # reaches RBS twice and both `Array` and `Enumerable` declare `map`
    # themselves, while nothing in `Symbol`'s chain does. Anything that
    # counts declarations rather than branches calls this member
    # unconditional on the strength of one branch's ancestors alone.
    it "marks a signature member only one Union branch has conditional, however many of that branch's ancestors declare it" do
      index_source("class Bag < Array\n  include Enumerable\nend\n")

      union = Ovallsp::Types.normalize_union([nominal("Bag"), nominal("Symbol")])

      member = service.members_of(union, prefix: "map").find { |candidate| candidate.name == "map" }

      expect(member.conditional).to be(true)
    end

    # 0.2.1 taught the *diagnostics engine* that a bare name RBS declares
    # is not answered by a workspace class that merely shares its last
    # segment, and stopped there. Resolution kept substituting, so the
    # three readers went on disagreeing -- the diagnostic fell silent
    # while completion on a string literal offered the workspace class's
    # members and omitted every String method, and hover said `String`
    # the whole time. The rule belongs where the name is resolved.
    it "completes a core class's own members, not those of a workspace class sharing its last segment" do
      index_source("module Serializer\n  module Elements\n    class String\n      def emit\n      end\n    end\n  end\nend\n")

      names = service.members_of(nominal("String"), prefix: "").map(&:name)

      expect(names).to include("upcase")
      expect(names).not_to include("emit")
    end

    # The boundary: a workspace that genuinely reopens `String` at the top
    # level is the same name, not a substitution, and must keep answering.
    it "still answers with a workspace class that reopens the core one under its own name" do
      index_source("class String\n  def shout\n  end\nend\n")

      names = service.members_of(nominal("String"), prefix: "").map(&:name)

      expect(names).to include("shout", "upcase")
    end

    it "treats a same-named member from different origins as available across the Union" do
      model_registry.register_from_agent_response(
        "User",
        { tableName: "users", partial: false, columns: [{ name: "hash", type: "integer", nullable: false }],
          associations: [] }
      )

      union = Ovallsp::Types.normalize_union([nominal("User"), nominal("String")])
      member = service.members_of(union, prefix: "hash").find { |candidate| candidate.name == "hash" }

      expect(member.conditional).to be(false)
    end
  end

  describe "#definitions_of" do
    it "resolves to the source declaration when one exists" do
      index_source("class Widget\n  def build\n  end\nend\n", uri: "file:///widget.rb")

      locations = service.definitions_of(nominal("Widget"), "build")

      expect(locations.size).to eq(1)
      expect(locations.first[:uri]).to eq("file:///widget.rb")
    end

    it "falls back to the signature's own location for an RBS-only method" do
      locations = service.definitions_of(nominal("String"), "upcase")

      expect(locations).not_to be_empty
      expect(locations.first[:uri]).to match(/string\.rbs\z/)
    end

    it "falls back to the owning model's class declaration for a generated Active Record association" do
      index_source("class Company\nend\n", uri: "file:///company.rb")
      model_registry.register_from_agent_response(
        "Company",
        { tableName: "companies", partial: false, columns: [],
          associations: [{ name: "orders", macro: "has_many", className: "Order", optional: false }] }
      )

      locations = service.definitions_of(nominal("Company"), "orders")

      expect(locations.size).to eq(1)
      expect(locations.first[:uri]).to eq("file:///company.rb")
    end

    # This reconstructed a `SymbolId` with `owner: nil` and looked the
    # class up by that key, which is exactly what `find_controller_uri`
    # was moved off in this release: `SymbolId#owner` is recorded
    # *lexically*, so `module Admin; class Company` indexes under owner
    # `::Admin` and the reconstructed key misses it. The nesting form is
    # the point of the pair -- the compact form happened to work, which
    # is why nobody saw it (0.1.12, round 5).
    it "falls back to the model's class declaration when it is written inside a `module` block" do
      index_source("module Admin\n  class Company\n  end\nend\n", uri: "file:///admin/company.rb")
      model_registry.register_from_agent_response(
        "Admin::Company",
        { tableName: "companies", partial: false, columns: [],
          associations: [{ name: "orders", macro: "has_many", className: "Order", optional: false }] }
      )

      locations = service.definitions_of(nominal("Admin::Company"), "orders")

      expect(locations.size).to eq(1)
      expect(locations.first[:uri]).to eq("file:///admin/company.rb")
    end

    it "falls back to the same declaration when the model is written in the compact form" do
      index_source("class Admin::Company\nend\n", uri: "file:///admin/company.rb")
      model_registry.register_from_agent_response(
        "Admin::Company",
        { tableName: "companies", partial: false, columns: [],
          associations: [{ name: "orders", macro: "has_many", className: "Order", optional: false }] }
      )

      locations = service.definitions_of(nominal("Admin::Company"), "orders")

      expect(locations.size).to eq(1)
      expect(locations.first[:uri]).to eq("file:///admin/company.rb")
    end
  end

  describe "#signatures_of" do
    it "builds a label from a source declaration's parameters" do
      index_source("class Widget\n  def build(name, count)\n  end\nend\n")

      signatures_result = service.signatures_of(nominal("Widget"), "build")

      expect(signatures_result.first[:label]).to eq("build(name, count)")
    end

    it "falls back to an RBS overload label when there is no source declaration" do
      signatures_result = service.signatures_of(nominal("String"), "upcase")

      expect(signatures_result).not_to be_empty
      expect(signatures_result.first[:label]).to start_with("upcase(")
    end

    # A parameter written after an optional one is required, and the
    # label has to say where it sits. It was dropped from the model
    # entirely, so `(String, ?Integer, Symbol)` rendered as two
    # parameters and signature help told the user the method takes at
    # most two arguments.
    it "shows a trailing positional, in its own position" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "sig"))
        File.write(File.join(root, "sig", "gadget.rbs"),
                   "class Gadget\n  def span: (String first, ?Integer middle, Symbol last) -> void\nend\n")
        signatures.load(workspace_root: root)

        signatures_result = service.signatures_of(nominal("Gadget"), "span")

        expect(signatures_result.first[:label]).to eq("span(String, ?Integer, Symbol) -> Unknown")
      end
    end

    it "prefers an explicit RBS signature over a conflicting source declaration" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "sig"))
        File.write(File.join(root, "sig", "widget.rbs"), "class Widget\n  def build: () -> String\nend\n")
        signatures.load(workspace_root: root)
        index_source("class Widget\n  def build(count)\n  end\nend\n")

        result = service.signatures_of(nominal("Widget"), "build")

        expect(result.first[:label]).to include("-> String")
      end
    end

    # Rewritten: the previous version wrote an RBS declaring no `to_s` at
    # all, so there was never a signature to outrank -- it passed
    # identically against the old unconditional `source || rbs` order and
    # constrained nothing about the direct/inherited split it claimed to
    # document.
    #
    # Only this direction is actually assertable. The ladder is
    # `rbs(direct) || source || rbs(inherited)`, whose rungs 1 and 3
    # together reproduce the old `source || rbs` for everything except a
    # *directly declared* RBS signature -- so "source beats inherited" is
    # not a state the design can fail, and a spec for it would pass
    # against any implementation.
    it "prefers a directly-declared RBS signature over a source declaration of the same method" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "sig"))
        File.write(File.join(root, "sig", "widget.rbs"), "class Widget\n  def render: (Integer size) -> String\nend\n")
        signatures.load(workspace_root: root)
        index_source("class Widget\n  def render(from_source)\n  end\nend\n")

        result = service.signatures_of(nominal("Widget"), "render")

        expect(result.first[:label]).to include("-> String")
      end
    end

    it "keeps authoritative signatures from every Union receiver member" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "sig"))
        File.write(
          File.join(root, "sig", "values.rbs"),
          "class Widget\n  def value: () -> String\nend\nclass Gadget\nend\n"
        )
        signatures.load(workspace_root: root)
        index_source(<<~RUBY)
          class Widget
            def value(source_argument)
            end
          end
          class Gadget
            def value(count)
            end
          end
        RUBY

        result = service.signatures_of(
          Ovallsp::Types.normalize_union([nominal("Widget"), nominal("Gadget")]), "value"
        )

        expect(result.map { |signature| signature[:label] }).to include(
          a_string_including("-> String"), "value(count)"
        )
      end
    end
  end

  describe "#explain" do
    it "reports high confidence for a resolved type" do
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: "user = User.new\n", version: 1, language_id: "ruby")

      result = service.explain(document, { line: 0, character: 1 })

      expect(result[:type]).to eq(nominal("User"))
      expect(result[:confidence]).to eq(:high)
    end

    it "reports low confidence for an unresolved type" do
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: "user = nope\n", version: 1, language_id: "ruby")

      result = service.explain(document, { line: 0, character: 7 })

      expect(result[:confidence]).to eq(:low)
    end
  end

  describe "with no optional dependencies wired" do
    subject(:bare_service) { described_class.new(local_inferencer: local_inferencer) }

    it "still answers #type_at" do
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: "1\n", version: 1, language_id: "ruby")

      expect(bare_service.type_at(document, { line: 0, character: 0 })).to eq(Ovallsp::Types::Nominal.new(name: "Integer"))
    end

    it "degrades to an empty list rather than raising for members/definitions/signatures" do
      expect(bare_service.members_of(nominal("Widget"))).to eq([])
      expect(bare_service.definitions_of(nominal("Widget"), "build")).to eq([])
      expect(bare_service.signatures_of(nominal("Widget"), "build")).to eq([])
    end
  end
end
