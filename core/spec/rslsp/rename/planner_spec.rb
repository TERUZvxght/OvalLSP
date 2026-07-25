# frozen_string_literal: true

RSpec.describe Rslsp::Rename::Planner do
  let(:workspace_index) { Rslsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Rslsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) { Rslsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index) }
  let(:model_registry) { Rslsp::Models::ModelRegistry.new }
  let(:local_inferencer) do
    Rslsp::LocalInferencer.new(
      model_registry: model_registry, method_resolver: method_resolver,
      method_analyzer: Rslsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver, summary_store: Rslsp::Semantic::MethodSummaryStore.new
      )
    )
  end
  let(:reference_index) { Rslsp::Semantic::ReferenceIndex.new }
  let(:reference_resolver) do
    Rslsp::Semantic::ReferenceResolver.new(
      workspace_index: workspace_index, method_resolver: method_resolver, local_inferencer: local_inferencer,
      model_registry: model_registry
    )
  end

  subject(:planner) { described_class.new(workspace_index: workspace_index, reference_index: reference_index) }

  def index_source(text, uri: "file:///a.rb")
    document = Rslsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Rslsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    references = reference_resolver.resolve(document, summary.reference_candidates, uri: uri, generation: 1)
    reference_index.replace_file(uri: uri, references: references)
    document
  end

  def sym(kind:, owner:, name:) = Rslsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil)

  it "returns an empty (no-op) plan when target is nil" do
    plan = planner.plan(nil, new_name: "whatever", generation: 1)

    expect(plan.target).to be_nil
    expect(plan.confirmed_edits).to eq([])
  end

  describe "local variable rename" do
    it "renames only the references sharing this local's exact scope" do
      index_source("def a\n  x = 1\n  x\nend\n\ndef b\n  x = 2\n  x\nend\n")
      # Resolve the real target's SymbolId rather than guessing its scope id.
      document = Rslsp::TextDocument.new(uri: "file:///a.rb", text: "def a\n  x = 1\n  x\nend\n\ndef b\n  x = 2\n  x\nend\n", version: 1, language_id: "ruby")
      summary = Rslsp::ParserService.new.summarize(document)
      candidate = summary.reference_candidates.find { |c| c.kind == :local_variable && c.location[:start][:line] == 1 }
      resolved = reference_resolver.resolve(document, [candidate], uri: "file:///a.rb", generation: 1).first

      plan = planner.plan(resolved.symbol_id, new_name: "y", generation: 1)

      lines = plan.confirmed_edits.map { |e| e[:range][:start][:line] }
      expect(lines).to contain_exactly(1, 2) # scope `a`'s `x` only, never scope `b`'s
      expect(plan.confirmed_edits).to all(include(new_text: "y"))
    end

    it "refuses an invalid local variable name" do
      index_source("x = 1\nx\n")
      document = Rslsp::TextDocument.new(uri: "file:///a.rb", text: "x = 1\nx\n", version: 1, language_id: "ruby")
      summary = Rslsp::ParserService.new.summarize(document)
      candidate = summary.reference_candidates.find { |c| c.kind == :local_variable }
      resolved = reference_resolver.resolve(document, [candidate], uri: "file:///a.rb", generation: 1).first

      plan = planner.plan(resolved.symbol_id, new_name: "NotValid!", generation: 1)

      expect(plan.confirmed_edits).to eq([])
      expect(plan.refused?).to be(true)
    end
  end

  describe "constant rename" do
    it "renames the class declaration and every resolved reference" do
      index_source("class Widget\nend\n\nWidget.new\n")

      plan = planner.plan(sym(kind: :class, owner: nil, name: "::Widget"), new_name: "Gadget", generation: 1)

      expect(plan.confirmed_edits.size).to eq(2) # the declaration + the "Widget.new" reference
      expect(plan.confirmed_edits).to all(include(new_text: "Gadget"))
    end

    it "refuses when the new constant name collides with an existing type" do
      index_source("class Widget\nend\n\nclass Gadget\nend\n")

      plan = planner.plan(sym(kind: :class, owner: nil, name: "::Widget"), new_name: "Gadget", generation: 1)

      expect(plan.confirmed_edits).to eq([])
      expect(plan.conflicts).not_to be_empty
    end
  end

  describe "method rename" do
    it "renames an implicit-self call along with its declaration" do
      index_source("class Widget\n  def a\n  end\n\n  def b\n    a\n  end\nend\n")

      plan = planner.plan(sym(kind: :instance_method, owner: "::Widget", name: "a"), new_name: "renamed", generation: 1)

      expect(plan.confirmed_edits.size).to eq(2) # `def a` + the `a` call inside `b`
      expect(plan.confirmed_edits).to all(include(new_text: "renamed"))
    end

    it "renames only this exact declaration, never a same-named method on an unrelated class (override chain safety)" do
      index_source(<<~RUBY)
        class Company
          def name
          end
        end

        class Widget
          def name
          end
        end
      RUBY

      plan = planner.plan(sym(kind: :instance_method, owner: "::Company", name: "name"), new_name: "title", generation: 1)

      expect(plan.confirmed_edits.size).to eq(1) # only Company#name's own declaration, not Widget#name
    end

    it "refuses when the new method name is already declared on the same owner" do
      index_source("class Widget\n  def a\n  end\n\n  def b\n  end\nend\n")

      plan = planner.plan(sym(kind: :instance_method, owner: "::Widget", name: "a"), new_name: "b", generation: 1)

      expect(plan.confirmed_edits).to eq([])
      expect(plan.conflicts).not_to be_empty
    end
  end

  describe "generated Rails method refusal" do
    it "refuses to rename a route helper" do
      target = sym(kind: :route_helper, owner: nil, name: "user")

      plan = planner.plan(target, new_name: "person", generation: 1)

      expect(plan.confirmed_edits).to eq([])
      expect(plan.warnings.first).to include("route")
    end

    it "refuses to rename an Active Record association" do
      target = sym(kind: :active_record_association, owner: "Company", name: "orders")

      plan = planner.plan(target, new_name: "purchases", generation: 1)

      expect(plan.confirmed_edits).to eq([])
      expect(plan.warnings.first).to include("association")
    end
  end

  describe "#prepare" do
    it "returns a placeholder for a renameable symbol" do
      index_source("class Widget\nend\n")

      result = planner.prepare(sym(kind: :class, owner: nil, name: "::Widget"))

      expect(result).to eq({ placeholder: "Widget" })
    end

    it "returns nil for a generated Rails method" do
      result = planner.prepare(sym(kind: :route_helper, owner: nil, name: "user"))

      expect(result).to be_nil
    end

    it "returns nil for a symbol with no known locations" do
      result = planner.prepare(sym(kind: :class, owner: nil, name: "::NeverIndexed"))

      expect(result).to be_nil
    end

    it "returns nil for a nil target" do
      expect(planner.prepare(nil)).to be_nil
    end
  end
end
