# frozen_string_literal: true

RSpec.describe Ovallsp::Rename::Planner do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry) }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:method_resolver) { stack.method_resolver }
  let(:local_inferencer) { stack.local_inferencer }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:reference_index) { Ovallsp::Semantic::ReferenceIndex.new }
  let(:reference_resolver) do
    Ovallsp::Semantic::ReferenceResolver.new(
      workspace_index: workspace_index, method_resolver: method_resolver, local_inferencer: local_inferencer,
      model_registry: model_registry
    )
  end

  subject(:planner) { described_class.new(workspace_index: workspace_index, reference_index: reference_index) }

  def index_source(text, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    references = reference_resolver.resolve(document, summary.reference_candidates, uri: uri, generation: 1)
    reference_index.replace_file(uri: uri, references: references)
    document
  end

  def sym(kind:, owner:, name:) = Ovallsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil)

  it "returns an empty (no-op) plan when target is nil" do
    plan = planner.plan(nil, new_name: "whatever", generation: 1)

    expect(plan.target).to be_nil
    expect(plan.confirmed_edits).to eq([])
  end

  describe "local variable rename" do
    it "renames only the references sharing this local's exact scope" do
      index_source("def a\n  x = 1\n  x\nend\n\ndef b\n  x = 2\n  x\nend\n")
      # Resolve the real target's SymbolId rather than guessing its scope id.
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: "def a\n  x = 1\n  x\nend\n\ndef b\n  x = 2\n  x\nend\n", version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      candidate = summary.reference_candidates.find { |c| c.kind == :local_variable && c.location[:start][:line] == 1 }
      resolved = reference_resolver.resolve(document, [candidate], uri: "file:///a.rb", generation: 1).first

      plan = planner.plan(resolved.symbol_id, new_name: "y", generation: 1)

      lines = plan.confirmed_edits.map { |e| e[:range][:start][:line] }
      expect(lines).to contain_exactly(1, 2) # scope `a`'s `x` only, never scope `b`'s
      expect(plan.confirmed_edits).to all(include(new_text: "y"))
    end

    it "refuses an invalid local variable name" do
      index_source("x = 1\nx\n")
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: "x = 1\nx\n", version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
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

    it "renames only the class's own identifier in a compact-nested declaration, leaving it inside its namespace" do
      # Found by the Task 014-018 independent review: `class Foo::Bar`'s
      # name_location previously spanned the whole "Foo::Bar" text, so
      # applying this edit replaced it wholesale -- `class Foo::Bar`
      # became `class Container`, silently dropping the class out of the
      # `Foo` namespace instead of renaming just the `Bar` identifier.
      text = "module Foo\nend\n\nclass Foo::Bar\nend\n"
      index_source(text)

      plan = planner.plan(sym(kind: :class, owner: nil, name: "::Foo::Bar"), new_name: "Container", generation: 1)

      decl_edit = plan.confirmed_edits.find { |e| e[:range][:start][:line] == 3 }
      expect(decl_edit).not_to be_nil
      before = decl_edit[:range][:start][:character]
      after = decl_edit[:range][:end][:character]
      expect(text.lines[3][0...before]).to eq("class Foo::")
      expect(text.lines[3][before...after]).to eq("Bar")
    end

    it "renames only the identifier segment of a compact-nested constant reference, keeping its namespace prefix intact" do
      text = "module Foo\n  class Bar\n  end\nend\n\nFoo::Bar.new\n"
      index_source(text)

      plan = planner.plan(sym(kind: :class, owner: nil, name: "::Foo::Bar"), new_name: "Container", generation: 1)

      ref_edit = plan.confirmed_edits.find { |e| e[:range][:start][:line] == 5 }
      expect(ref_edit).not_to be_nil
      before = ref_edit[:range][:start][:character]
      after = ref_edit[:range][:end][:character]
      expect(text.lines[5][0...before]).to eq("Foo::")
      expect(text.lines[5][before...after]).to eq("Bar")
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

  # 0.1.14 made `attr_reader`/`attr_accessor` declare methods, and those
  # declarations carry no `name_location` -- there is no identifier token
  # to rewrite, only a symbol argument. `locations_for` silently drops
  # such a declaration, so rename produced a plan that rewrote every
  # *call site* and left `attr_accessor :name` alone: a WorkspaceEdit that
  # breaks the file, with no warning. Before 0.1.14 no declaration existed
  # and `prepareRename` refused outright, which was the safe answer.
  #
  # The same hole pre-existed for `enum`/`scope`/`delegate`; it was
  # confined to Rails DSLs until `attr_*` put it in ordinary Ruby.
  # `#prepare`'s own comment already said nil means "a generated/DSL-origin
  # symbol" -- this makes that true.
  describe "a method declared by a DSL rather than a `def`" do
    before do
      index_source("class Widget\n  attr_accessor :name\n\n  def describe = name\nend\n")
    end

    let(:target) { sym(kind: :instance_method, owner: "::Widget", name: "name") }

    it "refuses to start the rename" do
      expect(planner.prepare(target)).to be_nil
    end

    it "refuses with a reason rather than emitting a partial edit" do
      plan = planner.plan(target, new_name: "title", generation: 1)

      expect(plan.confirmed_edits).to eq([])
      expect(plan.warnings.join).to include("declared by a macro rather than a `def`", "cannot be renamed in place")
    end

    # A plugin's declaration also carries no `name_location` -- it records
    # the synthetic `PLUGIN_LOCATION` -- so keying the refusal on that
    # would disable rename for a method the workspace writes with a real
    # `def` merely because a plugin also registered the name. The refusal
    # is about a *macro* declaration, which is what `origin: :generated`
    # says.
    it "still renames a `def` a plugin also registered" do
      workspace_index.replace_file(
        Ovallsp::Index::FileSummary.new(
          uri: "file:///plugin.rb", content_hash: "p", document_version: 1,
          declarations: [
            Ovallsp::Index::Declaration.new(
              symbol_id: sym(kind: :instance_method, owner: "::Widget", name: "describe"),
              location: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
              visibility: :public, parameters: [], origin: :plugin
            )
          ],
          diagnostics: [], ancestor_facts: [], alias_facts: [], reference_candidates: [],
          generated_method_facts: []
        )
      )

      expect(planner.prepare(sym(kind: :instance_method, owner: "::Widget", name: "describe"))).not_to be_nil
    end

    it "still renames a method the same class declares with `def`" do
      plan = planner.plan(sym(kind: :instance_method, owner: "::Widget", name: "describe"),
                          new_name: "explain", generation: 1)

      expect(plan.confirmed_edits).not_to be_empty
      expect(plan.warnings).to eq([])
    end
  end
end
