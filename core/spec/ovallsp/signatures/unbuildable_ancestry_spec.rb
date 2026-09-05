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

  # The only difference: an interface the signature *names* and nothing
  # *declares*, which is what makes the chain unbuildable.
  #
  # **This was `_OvallspNothingDeclaresThis` until `024.321`.** That name was chosen because
  # `stdlib/json/0/json.rbs` declares it and the loader never added the
  # library -- so it was absent in practice while being a real name. When
  # 0.4.0 loaded all 61 stdlib libraries the name became declared, every
  # fixture here built, and nine examples in this file passed while
  # asserting nothing. A fixture that depends on a library *not* being
  # loaded is a fixture with a second subject; this one names something
  # nothing ships, so it cannot be neutralised by loading more.
  UNBUILDABLE_UNRESOLVABLE_RBS = UNBUILDABLE_RESOLVABLE_RBS.sub("  class Key\n", "  class Key\n    include _OvallspNothingDeclaresThis\n")

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
      # `PP::ObjectMixin` sits between `Object` and `Kernel` because
      # `024.321` loads the `pp` library, which reopens `Object` to
      # include it. Ruby agrees once `pp` is required -- `ruby -e 'p
      # Object.ancestors'` is `[Object, Kernel, BasicObject]` and
      # `ruby -e 'require "pp"; p Object.ancestors'` inserts it -- and
      # Rails requires `pp`, so for the application this targets the
      # longer chain is the true one. It is the only core chain the
      # stdlib load moves: measured across Object, String, Integer,
      # Array, Hash, Symbol, Float and Range, this module is the whole
      # difference.
      expect(environment.ancestors("::App::Key")).to eq(%w[App::Key Object PP::ObjectMixin Kernel BasicObject])
    end
  end

  it "still knows the class declares its own method when every include resolves" do
    environment_for(UNBUILDABLE_RESOLVABLE_RBS) do |environment|
      expect(environment.member_names("::App::Key")).to include("digest")
    end
  end

  # The three that fail before the fix.
  # Named separately per failing build, not merely "something failed".
  # Asserting only that the channel is non-empty could not tell the two
  # apart, and the hunk sweep found the `#build_definition` recording
  # unpinned for exactly that reason: the ancestors recording alone
  # already made the list non-empty, so reverting the other one left the
  # suite green.
  it "names the ancestor chain it could not build" do
    environment_for(UNBUILDABLE_UNRESOLVABLE_RBS) do |environment|
      environment.ancestors("::App::Key")

      expect(environment.diagnostics.map { |d| d[:message] })
        .to include(a_string_matching(/ancestors of ::App::Key/))
    end
  end

  it "names the definition it could not build, which is a different failure at a different call" do
    environment_for(UNBUILDABLE_UNRESOLVABLE_RBS) do |environment|
      environment.member_names("::App::Key")

      expect(environment.diagnostics.map { |d| d[:message] })
        .to include(a_string_matching(/definition of ::App::Key/))
    end
  end

  # One bad `include` fails once per *route* that reaches it, and an
  # unbounded list of one sentence is what makes a person stop reading
  # the channel carrying the line they need.
  #
  # The calls below are chosen so the guard can actually fail. Repeating
  # one call cannot: `#ancestors` and `#member_names` memoize, so five
  # calls compute once and the duplicate never arises. An earlier version
  # of this example did exactly that, passed, and a mutation run found
  # the guard unpinned -- an assertion that could not fail, written while
  # trying to pin one.
  #
  # These three reach `#build_definition` by three different cache keys
  # -- instance members, singleton members, type parameters -- and every
  # one of them produces the same sentence.
  it "records a failure once even when three different lookups hit it" do
    environment_for(UNBUILDABLE_UNRESOLVABLE_RBS) do |environment|
      environment.member_names("::App::Key", singleton: false)
      environment.member_names("::App::Key", singleton: true)
      environment.type_parameters("::App::Key")

      definition_failures = environment.diagnostics
                                       .map { |d| d[:message] }
                                       .grep(/definition of ::App::Key/)

      expect(definition_failures.length).to eq(1)
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

  # `024.246`/`024.247`. Four callers derived "the signature environment
  # declares this name" from `!ancestors(...).empty?`, and each had to
  # remember two things the chain does not tell them: to qualify the name
  # first, and that one of the empty chains is the sentinel above. Two of
  # them forgot the second, so a class the project's own `sig/` declares
  # read as a name signatures have never heard of.
  #
  # `#declares?` decides both here, and it answers three things rather
  # than two because the questions its callers ask have opposite safe
  # directions -- "is this constant known" must fail towards *known*,
  # "is this receiver's surface complete" must fail towards *incomplete*
  # -- so no single boolean is safe for both.
  describe "#declares?" do
    it "answers true for a declared name whose chain was built" do
      environment_for(UNBUILDABLE_RESOLVABLE_RBS) do |environment|
        expect(environment.declares?("App::Key")).to be(true)
      end
    end

    it "answers nil, not false, for a declared name whose chain could not be built" do
      environment_for(UNBUILDABLE_UNRESOLVABLE_RBS) do |environment|
        expect(environment.declares?("App::Key")).to be_nil
      end
    end

    it "answers false for a name the signature set has never heard of" do
      environment_for(UNBUILDABLE_UNRESOLVABLE_RBS) do |environment|
        expect(environment.declares?("NoSuchTypeAnywhere")).to be(false)
      end
    end

    # The qualification the four callers each had to remember. A bare
    # name and a rooted one are the same name, and `#ancestors` answers
    # only for the rooted spelling.
    it "answers the same for a bare name and a rooted one" do
      environment_for(UNBUILDABLE_RESOLVABLE_RBS) do |environment|
        expect(environment.declares?("::App::Key")).to be(true)
      end
    end
  end

  # The user-visible half. The workspace declares `App::Key` in Ruby, so
  # `MethodResolver#accounted_for?` returns true on `entry.kind` alone and
  # the chain reads as complete -- while the only place `digest` is
  # declared is the RBS whose build just failed.
  describe "the report it produced" do
    # `mode:` because the two entries below need different ones and each
    # needs the one it names: `unresolved-constant` runs only at
    # `:standard` or above, while `:safe` is what the shipped extension
    # gets -- nothing under `vscode/` sets
    # `initializationOptions.diagnosticsMode`.
    def findings_for(rbs, source: UNBUILDABLE_RUBY_SOURCE, mode: :standard, ancestry_registry: nil)
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
          ancestry_registry: ancestry_registry,
          signatures: signatures, generation: 1
        )
        Ovallsp::Diagnostics::Engine.new
                .analyze(document: document, semantic_context: context, mode: mode)
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

    # `024.246`. The same cause at a reader `024.223` does not enumerate:
    # it names `#compute_ancestors`' readers and
    # `MethodResolver#accounted_for?`, and this is
    # `Index::TypeNameResolution.substitution?`.
    #
    # That rule refuses to report about a *bare* inferred type the
    # workspace answered with a differently-namespaced class of its own —
    # here the RBS `Widget` against the workspace's `Zoo::Widget`. It
    # decided "signatures declare this name" from `!ancestors(...).empty?`,
    # so the unbuildable chain switched the refusal off and the engine
    # reported `label` against the wrong class entirely.
    #
    # The receiver has to *arrive* bare, which is why the type comes back
    # from a signature rather than being written: a written `Zoo::Widget`
    # carries its namespace and `WorkspaceIndex#guessed_type_name?` blanks
    # it one line earlier.
    describe "a bare inferred type the workspace answers with a class of its own" do
      SUBSTITUTION_RESOLVABLE_RBS = <<~RBS
        class Widget
          def label: () -> String
        end
        class Factory
          def make: () -> Widget
        end
      RBS

      SUBSTITUTION_UNRESOLVABLE_RBS =
        SUBSTITUTION_RESOLVABLE_RBS.sub("class Widget\n") { "class Widget\n  include _OvallspNothingDeclaresThis\n" }

      SUBSTITUTION_SOURCE = <<~SRC
        module Zoo
          class Widget
            def zoo_only
              :here
            end
          end

          class Other
            def planted_bad
              definitely_absent
            end
          end
        end

        w = Factory.new.make
        w.label
      SRC

      it "reports only what nothing declares, when the chain builds" do
        expect(findings_for(SUBSTITUTION_RESOLVABLE_RBS, source: SUBSTITUTION_SOURCE, mode: :safe))
          .to contain_exactly(a_string_including("definitely_absent"))
      end

      # The control is inside the expectation: `definitely_absent` has to
      # stay, so an engine that answered by declining wholesale fails
      # here rather than passing.
      it "keeps refusing to substitute when the chain cannot be built" do
        expect(findings_for(SUBSTITUTION_UNRESOLVABLE_RBS, source: SUBSTITUTION_SOURCE, mode: :safe))
          .to contain_exactly(a_string_including("definitely_absent"))
      end
    end

    # `024.247`. `Engine#rbs_known_constant?` derived its answer from the
    # same emptiness, so "declared, chain unbuildable" read as "RBS does
    # not know this name" and the engine reported `cannot resolve
    # constant` naming a class the project's own `sig/` declares. The
    # method's own comment already says it must fail towards *known*
    # (`024.122`); the sentinel is what it could not see.
    #
    # The Ruby *references* the name rather than declaring it: a name the
    # workspace index settles never reaches the signature environment.
    describe "a constant declared only in the signature file" do
      CONSTANT_ONLY_SOURCE = <<~SRC
        module App
          def self.use
            App::Key
          end

          def self.planted_bad
            DefinitelyAbsentConstant
          end
        end
      SRC

      it "resolves the constant when the chain builds" do
        expect(findings_for(UNBUILDABLE_RESOLVABLE_RBS, source: CONSTANT_ONLY_SOURCE))
          .to contain_exactly(a_string_including("DefinitelyAbsentConstant"))
      end

      it "still resolves it when the chain cannot be built" do
        expect(findings_for(UNBUILDABLE_UNRESOLVABLE_RBS, source: CONSTANT_ONLY_SOURCE))
          .to contain_exactly(a_string_including("DefinitelyAbsentConstant"))
      end
    end

    # The reader that must go the OTHER way, and the one place the shared
    # predicate is not a free substitution.
    #
    # `Engine#locally_accounted_for?` decides whether an ancestor the
    # running application reported is one static analysis already
    # accounts for. A `yes` concludes the receiver is not reopened
    # elsewhere and lets the check report every name it cannot find — so
    # the question is not whether signatures *declare* the ancestor but
    # whether anything can say what it *contributes*. A chain that could
    # not be built declares the name and enumerates nothing.
    #
    # `049` proposed converting this reader together with the other
    # three, on the reasoning that they all ask one question. Built and
    # measured, it reported a method missing on a receiver whose
    # Agent-reported ancestor is declared in the project's own sig with
    # that very method on it. The two arms below differ by one line of
    # RBS and give different answers, so the direction is pinned rather
    # than merely present.
    describe "an ancestor only the running application reported" do
      FOREIGN_ANCESTOR_RESOLVABLE_RBS = <<~RBS
        module Vendor
          class Thing
            def shout: () -> String
          end
        end
      RBS

      FOREIGN_ANCESTOR_UNRESOLVABLE_RBS =
        FOREIGN_ANCESTOR_RESOLVABLE_RBS.sub("  class Thing\n") { "  class Thing\n    include _OvallspNothingDeclaresThis\n" }

      # `Receiver`'s own static chain is complete and reaches
      # `BasicObject`, so nothing about *it* is in doubt. Only the
      # foreign ancestor's chain is broken, which is the shape this
      # reader exists for.
      FOREIGN_ANCESTOR_SOURCE = <<~SRC
        class Receiver
          def use
            shout
          end
        end
      SRC

      def findings_with_agent(rbs)
        registry = Ovallsp::Runtime::AncestryRegistry.new
        registry.install(
          object_ancestors: %w[Object Kernel BasicObject],
          classes: { "Receiver" => { ancestors: %w[Receiver Vendor::Thing Object Kernel BasicObject] } }
        )
        findings_for(rbs, source: FOREIGN_ANCESTOR_SOURCE, mode: :safe, ancestry_registry: registry)
      end

      # The control, and it is the existing rule: an ancestor RBS knows
      # is not evidence that the surface was reopened, so the check keeps
      # firing.
      it "reports when the foreign ancestor's chain builds" do
        expect(findings_with_agent(FOREIGN_ANCESTOR_RESOLVABLE_RBS))
          .to contain_exactly(a_string_including("shout"))
      end

      it "declines when the foreign ancestor's chain could not be built" do
        expect(findings_with_agent(FOREIGN_ANCESTOR_UNRESOLVABLE_RBS)).to be_empty
      end
    end
  end
end
