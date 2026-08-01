# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Ovallsp::Signatures::Environment do
  subject(:environment) { described_class.new }

  let(:fixtures_root) { File.expand_path("../../fixtures/signatures", __dir__) }

  def sym(owner, name, kind: :instance_method)
    Ovallsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil)
  end

  describe "stdlib" do
    before { environment.load(workspace_root: nil) }

    it "resolves a stdlib Array method's return type instead of leaving it Unknown" do
      sm = environment.method_signatures(sym("::Array", "first"))

      expect(sm).not_to be_nil
      expect(sm.overloads.map(&:return_type)).to include(
        Ovallsp::Types::Generic.new(name: "Array", type_arg: Ovallsp::Types::TypeParameter.new(name: "Elem"))
      )
    end

    it "resolves a stdlib Hash method" do
      sm = environment.method_signatures(sym("::Hash", "keys"))

      expect(sm).not_to be_nil
      expect(sm.overloads).not_to be_empty
    end

    it "returns nil for a method that doesn't exist on a known stdlib type" do
      expect(environment.method_signatures(sym("::String", "not_a_real_method_xyz"))).to be_nil
    end

    it "returns nil for a type unknown to the loaded environment" do
      expect(environment.method_signatures(sym("::TotallyUnknownType", "foo"))).to be_nil
    end

    it "resolves a generic method (Array#map) with a substitutable element-type parameter and block" do
      sm = environment.method_signatures(sym("::Array", "map"))
      block_overload = sm.overloads.find(&:block_required)

      expect(block_overload).not_to be_nil
      element_param = block_overload.block_type.parameters.first
      bound = Ovallsp::Types.substitute(element_param, { "Elem" => Ovallsp::Types::Nominal.new(name: "User") })
      expect(bound).to eq(Ovallsp::Types::Nominal.new(name: "User"))

      return_bound = Ovallsp::Types.substitute(
        block_overload.return_type, { "U" => Ovallsp::Types::Nominal.new(name: "User") }
      )
      expect(return_bound).to eq(Ovallsp::Types::Generic.new(name: "Array", type_arg: Ovallsp::Types::Nominal.new(name: "User")))
    end

    it "reports class/module ancestors sourced from RBS" do
      expect(environment.ancestors("::String")).to include("String", "Comparable", "Object", "Kernel", "BasicObject")
    end

    it "resolves a singleton method" do
      sm = environment.method_signatures(sym("::Array", "new", kind: :singleton_method))

      expect(sm).not_to be_nil
    end
  end

  describe "#member_names" do
    before { environment.load(workspace_root: nil) }

    it "lists every method (including inherited ones) starting with the given prefix" do
      names = environment.member_names("::String", prefix: "up")

      expect(names).to include("upcase", "upcase!", "upto")
    end

    it "returns [] for a type unknown to the loaded environment" do
      expect(environment.member_names("::TotallyUnknownType", prefix: "")).to eq([])
    end
  end

  describe "project sig/" do
    it "loads a project's sig/ directory and its methods take priority as project-authored signatures" do
      environment.load(workspace_root: File.join(fixtures_root, "project_workspace"))

      sm = environment.method_signatures(sym("::Widget", "name"))

      expect(sm).not_to be_nil
      expect(sm.source_kind).to eq(:rbs)
      expect(sm.overloads.first.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
    end

    it "still resolves stdlib methods alongside a project sig/" do
      environment.load(workspace_root: File.join(fixtures_root, "project_workspace"))

      expect(environment.method_signatures(sym("::String", "upcase"))).not_to be_nil
    end
  end

  describe "project RBI" do
    it "loads a minimal Sorbet RBI and exposes it through the shared environment" do
      Dir.mktmpdir do |root|
        rbi_dir = File.join(root, "sorbet", "rbi")
        FileUtils.mkdir_p(rbi_dir)
        File.write(
          File.join(rbi_dir, "widget.rbi"),
          "class Widget\n  sig { returns(String) }\n  def label; end\nend\n"
        )

        environment.load(workspace_root: root)
        sm = environment.method_signatures(sym("::Widget", "label"))

        expect(sm.source_kind).to eq(:rbi)
        expect(sm.overloads.first.return_type.to_s).to eq("String")
        expect(environment.member_names("::Widget", prefix: "lab")).to include("label")
      end
    end

    # What the user actually sees. Sorbet's `params(...)` names its
    # entries whatever the `def`'s parameters are called, and the parser
    # used to file all of them as required *keywords* -- harmless while
    # nothing rendered keywords, and a direct instruction to type `x:`
    # into a positional method once 0.1.12's label did (0.1.12, round 5).
    it "labels an RBI-declared positional method with positionals, not keywords" do
      Dir.mktmpdir do |root|
        rbi_dir = File.join(root, "sorbet", "rbi")
        FileUtils.mkdir_p(rbi_dir)
        File.write(
          File.join(rbi_dir, "widget.rbi"),
          "class Widget\n  sig { params(x: Integer, y: String).returns(Integer) }\n  def combine(x, y); end\nend\n"
        )
        environment.load(workspace_root: root)

        query_service = Ovallsp::Semantic::QueryService.new(
          local_inferencer: Ovallsp::LocalInferencer.new, signatures: environment
        )
        label = query_service.signatures_of(Ovallsp::Types::Nominal.new(name: "Widget"), "combine").first[:label]

        expect(label).to eq("combine(Integer, String) -> Integer")
      end
    end
  end

  describe "Gem signature fixture" do
    it "loads a Gem's own sig/ directory supplied via bundle_context" do
      environment.load(workspace_root: nil, bundle_context: [File.join(fixtures_root, "gem_sig")])

      sm = environment.method_signatures(sym("::Gadget", "serial"))

      expect(sm).not_to be_nil
      expect(sm.overloads.first.return_type).to eq(Ovallsp::Types::Nominal.new(name: "Integer"))
    end
  end

  describe "broken RBS file" do
    it "does not raise, and still resolves stdlib afterward" do
      expect do
        environment.load(workspace_root: File.join(fixtures_root, "broken_workspace"))
      end.not_to raise_error

      expect(environment.method_signatures(sym("::String", "upcase"))).not_to be_nil
      expect(environment.diagnostics).not_to be_empty
    end
  end

  describe "absent rbs_collection / no bundle_context" do
    it "loads successfully with bundle_context: nil (the default)" do
      expect { environment.load(workspace_root: nil) }.not_to raise_error
      expect(environment.diagnostics).to eq([])
    end
  end

  describe "signature reload after file change" do
    it "bumps generation and drops stale cached entries on every #load" do
      environment.load(workspace_root: nil)
      first_generation = environment.generation
      environment.method_signatures(sym("::String", "upcase")) # populate the cache

      environment.load(workspace_root: nil)

      expect(environment.generation).to eq(first_generation + 1)
      sm = environment.method_signatures(sym("::String", "upcase"))
      expect(sm.generation).to eq(environment.generation)
    end

    # The type-parameter cache is memoized per type name and has to be
    # dropped with the others: it feeds the receiver binding in generic
    # calls, so a stale entry survives a `.rbs` edit and keeps binding a
    # container's element type from the *previous* declaration.
    it "drops the cached type parameters of a class whose RBS declaration changed" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "sig"))
        signature = File.join(root, "sig", "box.rbs")
        File.write(signature, "class Box[A]\nend\n")
        environment.load(workspace_root: root)
        expect(environment.type_parameters("Box")).to eq(["A"])

        File.write(signature, "class Box[K, V]\nend\n")
        environment.load(workspace_root: root)

        expect(environment.type_parameters("Box")).to eq(%w[K V])
      end
    end
  end
end
