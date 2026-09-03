# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# `024.224`. A namespaced type was reported incompatible with itself, and
# the cause is not the spelling the entry spent two attempts on.
#
# `Signatures::Environment#ancestors` answers `UNAVAILABLE` -- a frozen
# `[]` -- when RBS *declares* a type but its ancestry cannot be built
# (`024.223`). `Engine#ancestor_names` adds whatever that call returns to
# the reachable set, so an unavailable chain contributes nothing and is
# indistinguishable there from a type with no ancestors at all. The
# comparison then reports a mismatch from a question it could not ask,
# which is the one thing `docs/CODE_DISCIPLINE.md`'s swallowed-failure rule says a
# contained failure must never let a caller do.
#
# The reproduction is rbs's own signatures, and it is ordinary:
#
#     failed to build ancestors of ::RBS::TypeName:
#       sig/typename.rbs:52:4...52:19: Could not find mixin: _ToJson
#
# `sig/typename.rbs` includes an interface that is not in the set rbs
# loads for itself. RBS raises, the chain is unavailable, and the
# reachable set comes out as every spelling of the class *except* the
# bare-qualified one the expected side is compared as:
#
#     actual="TypeName" expected="RBS::TypeName"
#     reachable=["TypeName", "::RBS::TypeName", "Object", "Kernel",
#                "BasicObject"]
#
# Six of rbs 4.2.0's six `argument-type` reports are this.
#
# The fix is the guard directly above it, read for the other half of the
# chain: `nil` means decline, and `#compatible_nominal?` already treats it
# that way.
RSpec.describe "an argument whose signature ancestry cannot be built" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  # `_Missing` is never declared, which is what rbs's own `sig/` does to
  # `_ToJson` by accident: RBS loads the file, `class_decls` has the name,
  # and only `instance_ancestors` raises. So `App::Key` is a name the
  # signatures know and cannot describe, while `App::Sound` beside it is
  # ordinary -- the two are what tell the fix from a check that simply
  # stopped comparing.
  UNBUILDABLE_SIG = <<~RBS
    module App
      class Key
        include _Missing
      end

      class Sound
      end

      module Deep
        class Runner
          def fetch: (Key key) -> Key
          def play: (Sound sound) -> void
          def make: () -> Key
        end
      end
    end
  RBS

  # The same signatures with the unbuildable mixin removed. Every example
  # that pairs the two runs both, because "silent" means nothing without
  # a fixture that is loud for the reason under test.
  BUILDABLE_SIG = UNBUILDABLE_SIG.sub(/^\s*include _Missing\n/) { "" }
  raise "UNBUILDABLE_SIG no longer contains the mixin" if BUILDABLE_SIG == UNBUILDABLE_SIG

  # rbs's own shape, shrunk: the class is written bare from inside a
  # module nested deeper than it, so the actual side arrives as `Key`
  # while the expected side arrives as `App::Key`. Reproducing this took
  # a probe -- with the reference written where the enclosing namespace
  # can qualify it, the actual side is already `App::Key` and the two
  # sides meet whatever the chain does.
  FILES = {
    "helpers.rb" => <<~SRC,
      module App
        module Deep
          class Runner
            module Helpers
              def make
                Key.new
              end
            end
          end
        end
      end
    SRC
    "key.rb" => <<~SRC,
      module App
        class Key
        end

        class Sound
        end
      end
    SRC
  }.freeze

  def analyze(sig_text, call)
    Dir.mktmpdir("unbuildable-chain-") do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "app.rbs"), sig_text)

      workspace_index = Ovallsp::WorkspaceIndex.new
      model_registry = Ovallsp::Models::ModelRegistry.new
      signatures = Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: root) }
      stack = build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry,
                                   signatures: signatures)

      documents = FILES.merge("use.rb" => use_source(call)).map do |name, text|
        document = Ovallsp::TextDocument.new(uri: "file:///#{name}", text: text, version: 1, language_id: "ruby")
        summary = Ovallsp::ParserService.new.summarize(document)
        workspace_index.replace_file(summary)
        stack.hierarchy_index.replace_file(summary)
        document
      end

      context = Ovallsp::Diagnostics::SemanticContext.new(
        workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
        method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
        model_registry: model_registry, route_registry: Ovallsp::Routes::RouteRegistry.new,
        signatures: signatures, generation: 1
      )
      yield signatures if block_given?
      documents.flat_map do |document|
        engine.analyze(document: document, semantic_context: context, mode: :standard)
              .select { |f| f.code == "argument-type" }.map(&:message)
      end
    end
  end

  def use_source(call)
    <<~SRC
      module App
        module Deep
          class Runner
            include Helpers

            def use
              #{call}
            end
          end
        end
      end
    SRC
  end

  # The fixture states its own premise. Without this, a change that made
  # `Environment` build the chain after all would leave every example
  # below passing for a reason that has nothing to do with the fix.
  it "is a chain the signature environment cannot build, beside one it can" do
    unavailable = nil
    analyze(UNBUILDABLE_SIG, "fetch(make)") do |signatures|
      unavailable = [
        Ovallsp::Signatures::Environment.unavailable?(signatures.ancestors("::App::Key")),
        Ovallsp::Signatures::Environment.unavailable?(signatures.ancestors("::App::Sound"))
      ]
    end
    expect(unavailable).to eq([true, false])
  end

  it "does not report the class against itself" do
    expect(analyze(UNBUILDABLE_SIG, "fetch(make)")).to be_empty
  end

  # The pair that says why. Identical source, identical call, one mixin
  # apart -- and at HEAD only the buildable side is silent, which is what
  # makes the chain rather than the spelling the cause.
  it "is silent on the same call when the chain builds" do
    expect(analyze(BUILDABLE_SIG, "fetch(make)")).to be_empty
  end

  # The controls. Declining on an unavailable chain must cost only the
  # comparisons that reach one.
  it "still reports a mismatch whose argument's chain does build" do
    expect(analyze(UNBUILDABLE_SIG, "play(Runner.new)"))
      .to contain_exactly(a_string_including("expects App::Sound here"))
  end

  it "still reports a literal against a class whose chain does build" do
    expect(analyze(UNBUILDABLE_SIG, "play(42)"))
      .to contain_exactly(a_string_including("expects App::Sound here, but Integer is given"))
  end

  it "still says nothing where the argument matches" do
    expect(analyze(UNBUILDABLE_SIG, "play(Sound.new)")).to be_empty
  end

  # **The cost, pinned rather than left implicit.** A genuine mismatch
  # whose *actual* class has an unbuildable chain is declined too: the
  # reachable set is a lower bound, and a chain that could not be built
  # may well have had the expected type in it. That is the direction
  # section 0 prefers -- a missed report rather than a wrong one -- and
  # it is the whole price of this fix, so it is written down as an
  # assertion instead of a sentence.
  it "declines a real mismatch when the argument's own chain is unavailable" do
    expect(analyze(UNBUILDABLE_SIG, "play(make)")).to be_empty
  end
end
