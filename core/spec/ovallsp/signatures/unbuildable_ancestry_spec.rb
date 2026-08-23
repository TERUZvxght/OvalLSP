# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# `024.223`. One unresolvable `include` in a project's own RBS turned
# every method of that class into a false "has no method named" report.
#
# `RBS::EnvironmentLoader` is built from the project `sig/` and the
# Bundler gem signature directories only, so an interface declared in an
# stdlib signature nobody added cannot be resolved.
# `AncestorBuilder#instance_ancestors` then raises
# `RBS::NoMixinFoundError`, and three separate rescues in `Environment`
# swallowed it into the same value a type RBS has never heard of
# produces. The ancestor chain includes the class *itself*, so an empty
# chain does not merely lose what the class inherits -- it loses what the
# class declares.
#
# The two workspaces below are identical except for one line of RBS, and
# each example asserts a *different* answer between them, so a fixture
# that could not tell the two apart cannot pass by accident.
RSpec.describe "a project signature whose ancestry cannot be built" do
  UNBUILDABLE_RESOLVABLE_RBS = <<~RBS
    module App
      class Key
        def digest: () -> String
      end
    end
  RBS

  # The only difference. `_ToJson` is declared in `stdlib/json/0/json.rbs`,
  # which the loader never adds.
  UNBUILDABLE_UNRESOLVABLE_RBS = UNBUILDABLE_RESOLVABLE_RBS.sub("  class Key\n", "  class Key\n    include _ToJson\n")

  def environment_for(rbs)
    Dir.mktmpdir("unbuildable-ancestry-") do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "app.rbs"), rbs)
      environment = Ovallsp::Signatures::Environment.new
      environment.load(workspace_root: root)
      yield environment
    end
  end

  it "builds the chain when every include resolves" do
    environment_for(UNBUILDABLE_RESOLVABLE_RBS) do |environment|
      expect(environment.ancestors("::App::Key")).to eq(%w[App::Key Object Kernel BasicObject])
    end
  end

  it "still knows the class declares its own method when every include resolves" do
    environment_for(UNBUILDABLE_RESOLVABLE_RBS) do |environment|
      expect(environment.member_names("::App::Key")).to include("digest")
    end
  end

  # The three that fail before the fix.
  it "reports the failure through the diagnostics channel built to explain a gap" do
    environment_for(UNBUILDABLE_UNRESOLVABLE_RBS) do |environment|
      environment.ancestors("::App::Key")

      expect(environment.diagnostics).not_to be_empty
    end
  end

  it "tells a chain it could not build apart from a type it has never heard of" do
    environment_for(UNBUILDABLE_UNRESOLVABLE_RBS) do |environment|
      expect(described_class_unavailable?(environment.ancestors("::App::Key"))).to be(true)
      expect(described_class_unavailable?(environment.ancestors("::NoSuchTypeAnywhere"))).to be(false)
    end
  end

  it "does not answer that the class has no members when it could not look" do
    environment_for(UNBUILDABLE_UNRESOLVABLE_RBS) do |environment|
      expect(described_class_unavailable?(environment.member_names("::App::Key"))).to be(true)
    end
  end

  def described_class_unavailable?(value)
    Ovallsp::Signatures::Environment.unavailable?(value)
  end

  # The user-visible half. The workspace declares `App::Key` in Ruby, so
  # `MethodResolver#accounted_for?` returns true on `entry.kind` alone and
  # the chain reads as complete -- while the only place `digest` is
  # declared is the RBS whose build just failed.
  describe "the report it produced" do
    def findings_for(rbs, source: UNBUILDABLE_RUBY_SOURCE)
      Dir.mktmpdir("unbuildable-ancestry-engine-") do |root|
        FileUtils.mkdir_p(File.join(root, "sig"))
        File.write(File.join(root, "sig", "app.rbs"), rbs)

        signatures = Ovallsp::Signatures::Environment.new
        signatures.load(workspace_root: root)
        workspace_index = Ovallsp::WorkspaceIndex.new
        stack = build_analysis_stack(workspace_index: workspace_index, signatures: signatures)

        document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1,
                                             language_id: "ruby")
        summary = Ovallsp::ParserService.new.summarize(document)
        workspace_index.replace_file(summary)
        stack.hierarchy_index.replace_file(summary)

        context = Ovallsp::Diagnostics::SemanticContext.new(
          workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
          method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
          model_registry: Ovallsp::Models::ModelRegistry.new,
          route_registry: Ovallsp::Routes::RouteRegistry.new,
          signatures: signatures, generation: 1
        )
        Ovallsp::Diagnostics::Engine.new
                .analyze(document: document, semantic_context: context, mode: :standard)
                .map(&:message)
      end
    end

    UNBUILDABLE_RUBY_SOURCE = <<~SRC
      module App
        class Key
          def use
            digest
          end

          def planted_bad
            definitely_absent
          end
        end
      end
    SRC

    it "reports the method nothing declares, when the chain builds" do
      expect(findings_for(UNBUILDABLE_RESOLVABLE_RBS)).to contain_exactly(a_string_including("definitely_absent"))
    end

    it "does not report the method the signature declares, when the chain cannot be built" do
      expect(findings_for(UNBUILDABLE_UNRESOLVABLE_RBS)).not_to include(a_string_including("digest"))
    end

    # **The affected class goes quiet entirely, and that is the fix, not a
    # side effect of it.** Once the surface cannot be enumerated the engine
    # cannot tell `digest`, which the sig declares, from
    # `definitely_absent`, which nothing does -- so it declines about both.
    # An earlier draft of this file asserted the opposite, on the reasoning
    # that a fix should not lose a true report; that reasoning wants the
    # engine to answer from a question it could not ask, which is what
    # section 0 puts below saying nothing.
    it "declines about the whole receiver, including a method nothing declares" do
      expect(findings_for(UNBUILDABLE_UNRESOLVABLE_RBS)).to be_empty
    end

    # What must NOT happen is the decline spreading. `Other` has no
    # signature trouble, and one bad `include` elsewhere in the file must
    # not silence it -- otherwise the example above would pass on an
    # engine that stopped reporting anything at all once any signature
    # failed to load.
    it "keeps reporting on a class whose own chain is fine" do
      source = <<~SRC
        module App
          class Key
            def use
              digest
            end
          end

          class Other
            def oops
              definitely_absent
            end
          end
        end
      SRC

      expect(findings_for(UNBUILDABLE_UNRESOLVABLE_RBS, source: source))
        .to contain_exactly(a_string_including("definitely_absent"))
    end
  end
end
