# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# `024.224`. A namespaced type was reported incompatible with itself.
#
# Driven over rbs 4.0.3 with its own `sig/` as the signature root, every
# `argument-type` report the engine produced was this shape:
#
#     `constant` expects RBS::TypeName here, but TypeName is given
#     `new` expects RBS::Location here, but Location is given
#
# Taken from the interpreter rather than reasoned about:
#
#   $ ruby -e 'require "rbs"; module RBS
#     p [TypeName.equal?(RBS::TypeName), Location.equal?(RBS::Location)]
#   end'
#   # => [true, true]
#   # ruby 3.4.10
#
# The expected side arrives from RBS namespace-qualified; the actual side
# is inferred from Ruby written *inside* that namespace, so it arrives
# bare. `#ancestor_names` built the reachable set with the `::`-prefixed
# and last-segment spellings and never the bare qualified one that
# `simple_name` produces for the expected side.
#
# The failure direction is the safe one: widening `reachable` can only
# make `#compatible_nominal?` answer true more often, so it can silence a
# report and never create one.
RSpec.describe "an argument whose type is namespaced" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  # `Key` is declared in `sig/` and **not** in any Ruby the workspace
  # indexes. That is the shape that reproduces, and finding it took a
  # probe: with `class Key` also written in Ruby the hierarchy index
  # resolves the receiver to `::App::Key` and the two spellings meet, so
  # the defect hides. Four synthetic fixtures in an earlier pass missed
  # this and concluded the `rbs` gem was the only reproduction
  # (`024.228`).
  around do |example|
    Dir.mktmpdir("namespaced-argtype-") do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "app.rbs"), <<~RBS)
        module App
          class Key
          end

          class Registry
            def fetch: (Key key) -> Key
            def label: (String text) -> String
          end
        end
      RBS
      @workspace_root = root
      example.run
    end
  end

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) do
    Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: @workspace_root) }
  end
  let(:stack) do
    build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures)
  end

  def findings(body)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: body, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)

    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
      method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
      model_registry: model_registry, route_registry: Ovallsp::Routes::RouteRegistry.new,
      signatures: signatures, generation: 1
    )
    engine.analyze(document: document, semantic_context: context, mode: :standard)
          .select { |f| f.code == "argument-type" }.map(&:message)
  end

  # The source writes `Key` bare, from inside `module App`, where Ruby
  # resolves it to `App::Key` — the very class the signature declares.
  NAMESPACED_SOURCE = <<~SRC
    module App
      class Registry
        def use
          fetch(Key.new)
        end
      end
    end
  SRC

  # **Pending, deliberately.** This is the defect, reproduced; the fix is
  # not in 0.2.16 because the cheap one silences a true report. Measured:
  # widening the comparison to last segments (`reachable.include?(
  # simple_name_of(target))`) makes this example pass and simultaneously
  # takes `Farm::Animal` passed where `Zoo::Animal` is declared from
  #
  #     "`feed` expects Zoo::Animal here, but Animal is given"
  #
  # to nothing at all. A real mismatch, silenced. The entry's own note
  # calls that the "symptom's fix, two lines, measured 3 -> 0" — it is
  # two lines, and it buys the 3 by losing reports it should keep.
  #
  # Note what the baseline message itself shows: the actual side is
  # already only `Animal`. The receiver is under-qualified before the
  # comparison ever runs, which is why matching on spelling cannot be
  # made both correct and cheap. See `024.224` for the measurement and
  # the direction that remains.
  it "does not report a namespaced type against itself" do
    pending("Key is declared only in sig/, with no Ruby class of that name to qualify it — 024.224")
    expect(findings(NAMESPACED_SOURCE)).to be_empty
  end

  # The controls. Without these the example above would pass on an engine
  # that had simply stopped checking argument types.
  it "still reports a genuine mismatch inside the same namespace" do
    source = <<~SRC
      module App
        class Registry
          def use
            label(Key.new)
          end
        end
      end
    SRC

    expect(findings(source)).to contain_exactly(a_string_including("expects String here"))
  end

  it "still reports a genuine mismatch with a literal" do
    source = <<~SRC
      module App
        class Registry
          def use
            label(42)
          end
        end
      end
    SRC

    expect(findings(source)).to contain_exactly(a_string_including("expects String here, but Integer is given"))
  end

  it "still says nothing where the argument matches" do
    source = <<~SRC
      module App
        class Registry
          def use
            label("ok")
          end
        end
      end
    SRC

    expect(findings(source)).to be_empty
  end
end
