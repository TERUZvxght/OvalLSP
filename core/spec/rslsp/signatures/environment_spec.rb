# frozen_string_literal: true

RSpec.describe Rslsp::Signatures::Environment do
  subject(:environment) { described_class.new }

  let(:fixtures_root) { File.expand_path("../../fixtures/signatures", __dir__) }

  def sym(owner, name, kind: :instance_method)
    Rslsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil)
  end

  describe "stdlib" do
    before { environment.load(workspace_root: nil) }

    it "resolves a stdlib Array method's return type instead of leaving it Unknown" do
      sm = environment.method_signatures(sym("::Array", "first"))

      expect(sm).not_to be_nil
      expect(sm.overloads.map(&:return_type)).to include(
        Rslsp::Types::Generic.new(name: "Array", type_arg: Rslsp::Types::TypeParameter.new(name: "Elem"))
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
      bound = Rslsp::Types.substitute(element_param, { "Elem" => Rslsp::Types::Nominal.new(name: "User") })
      expect(bound).to eq(Rslsp::Types::Nominal.new(name: "User"))

      return_bound = Rslsp::Types.substitute(
        block_overload.return_type, { "U" => Rslsp::Types::Nominal.new(name: "User") }
      )
      expect(return_bound).to eq(Rslsp::Types::Generic.new(name: "Array", type_arg: Rslsp::Types::Nominal.new(name: "User")))
    end

    it "reports class/module ancestors sourced from RBS" do
      expect(environment.ancestors("::String")).to include("String", "Comparable", "Object", "Kernel", "BasicObject")
    end

    it "resolves a singleton method" do
      sm = environment.method_signatures(sym("::Array", "new", kind: :singleton_method))

      expect(sm).not_to be_nil
    end
  end

  describe "project sig/" do
    it "loads a project's sig/ directory and its methods take priority as project-authored signatures" do
      environment.load(workspace_root: File.join(fixtures_root, "project_workspace"))

      sm = environment.method_signatures(sym("::Widget", "name"))

      expect(sm).not_to be_nil
      expect(sm.source_kind).to eq(:rbs)
      expect(sm.overloads.first.return_type).to eq(Rslsp::Types::Nominal.new(name: "String"))
    end

    it "still resolves stdlib methods alongside a project sig/" do
      environment.load(workspace_root: File.join(fixtures_root, "project_workspace"))

      expect(environment.method_signatures(sym("::String", "upcase"))).not_to be_nil
    end
  end

  describe "Gem signature fixture" do
    it "loads a Gem's own sig/ directory supplied via bundle_context" do
      environment.load(workspace_root: nil, bundle_context: [File.join(fixtures_root, "gem_sig")])

      sm = environment.method_signatures(sym("::Gadget", "serial"))

      expect(sm).not_to be_nil
      expect(sm.overloads.first.return_type).to eq(Rslsp::Types::Nominal.new(name: "Integer"))
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
  end
end
