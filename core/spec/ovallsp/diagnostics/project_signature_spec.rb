# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# A method a project declares in its own `sig/` and not in Ruby is not an
# unknown method (0.1.11).
#
# `HierarchyIndex` reports a class's *own* ancestry entry already
# qualified (`::Widget`) while its inherited ones are bare (`Object`), so
# prefixing every entry asked for `::::Widget` and matched nothing. The
# consequence is the worst kind this check can produce: a report on code
# that runs, for the perfectly ordinary practice of describing a class in
# RBS without also writing the method body's signature in Ruby.
RSpec.describe "Ovallsp::Diagnostics::Engine against a project's own sig/ (0.1.11)" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "widget.rbs"), <<~RBS)
        class Widget
          def declared_only: () -> void
        end
      RBS
      @workspace_root = root
      example.run
    end
  end

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:method_resolver) { stack.method_resolver }
  let(:local_inferencer) { stack.local_inferencer }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) do
    Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: @workspace_root) }
  end

  def context
    Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
  end

  def index(text, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  def unknown_method_findings(body)
    index("class Widget\nend\n", uri: "file:///widget.rb")
    engine.analyze(document: index(body), semantic_context: context, mode: :standard)
          .select { |f| f.code == "unknown-method" }
  end

  # The same un-normalised prefix, two methods away in the same file. A
  # root-scoped constant reference is ordinary Ruby -- `::Rails`,
  # `::JSON`, `::ActiveRecord::Base` -- and every one of them was reported
  # as unresolvable while the identical name without `::` resolved.
  it "does not report a root-scoped reference to a constant RBS knows" do
    findings = engine.analyze(document: index("::Comparable\n"), semantic_context: context, mode: :standard)
                     .select { |f| f.code == "unresolved-constant" }

    expect(findings).to be_empty
  end

  it "still reports a root-scoped reference to a constant nothing declares" do
    findings = engine.analyze(document: index("::DefinitelyNotAConstant\n"), semantic_context: context, mode: :standard)
                     .select { |f| f.code == "unresolved-constant" }

    expect(findings.size).to eq(1)
  end

  # The last place the rule was written by hand rather than delegated
  # (0.1.12). `chain_reaches_root?` asks `entry.name == "BasicObject"`,
  # and a class written `< ::BasicObject` produces an entry named
  # `::BasicObject` -- so the chain is judged not to reach the root, the
  # receiver is not "closed", and the unknown-method check switches off
  # for that class without saying so. `ROOT_SUPERCLASS_NAMES` in the same
  # subsystem already lists both forms, which is what makes this an
  # oversight rather than a decision.
  it "still reports an unknown method on a class written `< ::BasicObject`" do
    index("class Rooted < ::BasicObject\nend\n", uri: "file:///rooted_base.rb")
    findings = engine.analyze(document: index("Rooted.new.definitely_not_here\n"),
                              semantic_context: context, mode: :standard)
                     .select { |f| f.code == "unknown-method" }

    expect(findings.size).to eq(1)
  end

  # The bare form has always worked; both must, and the pair is what
  # shows the two spellings are the same class.
  it "still reports an unknown method on a class written `< BasicObject`" do
    index("class Bare < BasicObject\nend\n", uri: "file:///bare_base.rb")
    findings = engine.analyze(document: index("Bare.new.definitely_not_here\n"),
                              semantic_context: context, mode: :standard)
                     .select { |f| f.code == "unknown-method" }

    expect(findings.size).to eq(1)
  end

  # The same prefix again, in the ancestry walk. An entry that is
  # `::`-prefixed *and* carries no kind -- which is what `include ::Foo`
  # produces -- slipped past the kind short-circuit and asked for
  # `::::Comparable`, so writing `::` in an include silently switched the
  # unknown-method check off for that class.
  it "still reports an unknown method on a class that includes a root-scoped module" do
    index("class Rooted\n  include ::Comparable\nend\n", uri: "file:///rooted.rb")
    findings = engine.analyze(document: index("Rooted.new.definitely_not_here\n"),
                              semantic_context: context, mode: :standard)
                     .select { |f| f.code == "unknown-method" }

    expect(findings.size).to eq(1)
  end

  it "does not report a method the project's own sig/ declares on the class itself" do
    expect(unknown_method_findings("Widget.new.declared_only\n")).to be_empty
  end

  # `class Foo < <expression>` gives `HierarchyIndex` an entry with no
  # name at all. The old `"::#{entry.name}"` tolerated that (`"::"`);
  # `delete_prefix` on nil does not, and the model path reaches
  # `rbs_resolves?` without passing the nil guard that shields the other
  # one -- so the normalization has to keep tolerating it or `analyze`
  # raises out of a request.
  it "survives an ancestor whose superclass is an expression rather than a name" do
    model_registry.register_from_agent_response(
      "Widget", { tableName: "widgets", partial: false, columns: [], associations: [] }
    )
    index("class Widget < Struct.new(:a)\nend\n", uri: "file:///widget.rb")

    expect do
      engine.analyze(document: index("Widget.new.definitely_not_here\n"),
                     semantic_context: context, mode: :standard)
    end.not_to raise_error
  end

  # The fix must not silence the check: a name nothing declares, in Ruby
  # or in RBS, is still exactly what this reports.
  it "still reports a method nothing declares anywhere" do
    findings = unknown_method_findings("Widget.new.definitely_not_here\n")

    expect(findings.size).to eq(1)
    expect(findings.first.message).to include("definitely_not_here")
  end
end
