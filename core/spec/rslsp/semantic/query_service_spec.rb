# frozen_string_literal: true

RSpec.describe Rslsp::Semantic::QueryService do
  let(:workspace_index) { Rslsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Rslsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) { Rslsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index) }
  let(:model_registry) { Rslsp::Models::ModelRegistry.new }
  let(:local_inferencer) { Rslsp::LocalInferencer.new(model_registry: model_registry) }
  let(:signatures) { Rslsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) } }

  subject(:service) do
    described_class.new(
      local_inferencer: local_inferencer, method_resolver: method_resolver, model_registry: model_registry,
      signatures: signatures, workspace_index: workspace_index
    )
  end

  def index_source(text, uri: "file:///a.rb", version: 1)
    document = Rslsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
    summary = Rslsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  def nominal(name) = Rslsp::Types::Nominal.new(name: name)

  describe "#type_at" do
    it "delegates straight to LocalInferencer, so hover/completion never see different receiver types for the same expression" do
      document = Rslsp::TextDocument.new(uri: "file:///a.rb", text: "user = User.new\n", version: 1, language_id: "ruby")

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

      union = Rslsp::Types.normalize_union([nominal("User"), nominal("Admin")])
      members = service.members_of(union, prefix: "")

      superpowers = members.find { |m| m.name == "superpowers" }
      name = members.find { |m| m.name == "name" }
      expect(superpowers.conditional).to be(true)
      expect(name.conditional).to be(false)
      expect(members.index(name)).to be < members.index(superpowers)
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
  end

  describe "#explain" do
    it "reports high confidence for a resolved type" do
      document = Rslsp::TextDocument.new(uri: "file:///a.rb", text: "user = User.new\n", version: 1, language_id: "ruby")

      result = service.explain(document, { line: 0, character: 1 })

      expect(result[:type]).to eq(nominal("User"))
      expect(result[:confidence]).to eq(:high)
    end

    it "reports low confidence for an unresolved type" do
      document = Rslsp::TextDocument.new(uri: "file:///a.rb", text: "user = nope\n", version: 1, language_id: "ruby")

      result = service.explain(document, { line: 0, character: 7 })

      expect(result[:confidence]).to eq(:low)
    end
  end

  describe "with no optional dependencies wired" do
    subject(:bare_service) { described_class.new(local_inferencer: local_inferencer) }

    it "still answers #type_at" do
      document = Rslsp::TextDocument.new(uri: "file:///a.rb", text: "1\n", version: 1, language_id: "ruby")

      expect(bare_service.type_at(document, { line: 0, character: 0 })).to eq(Rslsp::Types::Nominal.new(name: "Integer"))
    end

    it "degrades to an empty list rather than raising for members/definitions/signatures" do
      expect(bare_service.members_of(nominal("Widget"))).to eq([])
      expect(bare_service.definitions_of(nominal("Widget"), "build")).to eq([])
      expect(bare_service.signatures_of(nominal("Widget"), "build")).to eq([])
    end
  end
end
