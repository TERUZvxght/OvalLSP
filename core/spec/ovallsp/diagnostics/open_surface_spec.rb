# frozen_string_literal: true

# 31 of the 34 remaining false `unknown-method` findings over real gem
# source are metaprogrammed method surfaces: `attr_atomic`,
# `attr_volatile`, `safe_initialization!`, `module_eval`. Static analysis
# cannot see what they define, and this check's stated policy -- 015,
# 誤検出率を最優先 -- says the answer there is silence, not a report.
#
# So a class whose body contains a class-level call the index does not
# recognise has an **open** method surface: absence cannot be
# established, and `closed_nominal?` must decline.
#
# **Measured before adopting**, because the external review named this as
# the change most likely to be the wrong shape -- it is wrong if the
# parser cannot tell a method-defining call from a harmless one and a
# large fraction of ordinary classes fall silent. Over 213 files and 257
# classes: a blanket rule opens 33 (12.8%), but 21 of those are
# `private_constant`, which defines nothing. With the calls known not to
# define methods excluded, **24 classes (9.3%)** open, and every name
# among them can define one: `safe_initialization!` 16, `module_eval` 9,
# `attr_atomic` 6, `attr`, `attr_volatile`, `def_delegators`,
# `java_import`, `send`, `padding`.
RSpec.describe "Ovallsp::Diagnostics::Engine and an unrecognised class-body macro" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) do
    Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
  end
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:local_inferencer) do
    Ovallsp::LocalInferencer.new(
      model_registry: model_registry, method_resolver: method_resolver,
      method_analyzer: Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver,
        summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
    )
  end
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }

  def index(text, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  def index_second(text) = index(text, uri: "file:///b.rb")

  def unknown_methods(document)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
    engine.analyze(document: document, semantic_context: context, mode: :standard)
          .select { |finding| finding.code == "unknown-method" }
          .map { |finding| finding.message[/named `(.+)`/, 1] }
  end

  it "says nothing about a class whose body runs a macro it cannot read" do
    document = index(<<~RUBY_SRC)
      class Counter
        attr_atomic :value

        def show
          value
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).not_to include("value")
  end

  # The other half of the same decision, and the reason the two surfaces
  # are tracked separately: `attr_atomic :value` defines `#value`, so it
  # opens the instance surface -- and it does *not* define
  # `.attr_atomic`, so the call itself stays reportable. Opening both
  # would make every unreadable macro silence its own report, which is
  # behaviour 024.23 established deliberately.
  it "still reports the unreadable macro call itself" do
    document = index(<<~RUBY_SRC)
      class Counter
        attr_atomic :value
      end
    RUBY_SRC

    expect(unknown_methods(document)).to eq(["attr_atomic"])
  end

  # The control, and the reason this is not "stop reporting": an ordinary
  # class with no unreadable macro still answers.
  it "still reports on a class whose surface it can read completely" do
    document = index(<<~RUBY_SRC)
      class Plain
        attr_reader :value

        def show
          definitely_not_defined_zzz
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to include("definitely_not_defined_zzz")
  end

  # A call that provably defines nothing must not open the surface, or the
  # rule costs far more than it buys -- 21 of the 33 classes a blanket
  # rule would silence use `private_constant`.
  it "is not opened by a class-level call that defines no method" do
    document = index(<<~RUBY_SRC)
      class Scoped
        SECRET = 1
        private_constant :SECRET

        def show
          definitely_not_defined_zzz
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to include("definitely_not_defined_zzz")
  end

  # `singleton_class.send :alias_method, :[], :new` -- concurrent-ruby's
  # `LockFreeStack::Node`, and 6 of the 16 findings the gem corpus still
  # produced after the receiverless rule above. The call has a receiver,
  # so the receiverless rule cannot see it, and what it defines is a
  # *class-level* method: `Node[a, b]`.
  #
  # `singleton_class` and `self` only. A class body naming some other
  # constant and calling into it is not this shape, and widening to every
  # receiver would open a surface for `LOGGER.warn`.
  it "is opened at class level by a call through singleton_class" do
    document = index(<<~RUBY_SRC)
      class Node
        def initialize(value); end
        singleton_class.send :alias_method, :[], :new
      end

      class NodeUser
        def build = Node[1]
      end
    RUBY_SRC

    expect(unknown_methods(document)).to be_empty
  end

  # The control for the example above, and the reason it is not asserting
  # nothing: without the `singleton_class` line the same call *is*
  # reported, so the example distinguishes the two behaviours rather than
  # passing on a fixture where neither branch says anything.
  it "still reports that class-level call when nothing opens the surface" do
    document = index(<<~RUBY_SRC)
      class Node
        def initialize(value); end
      end

      class NodeUser
        def build = Node[1]
      end
    RUBY_SRC

    expect(unknown_methods(document)).to eq(["[]"])
  end

  it "is opened at instance level by a call through self" do
    document = index(<<~RUBY_SRC)
      class Wired
        self.class_eval { }

        def show
          woven_in
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).not_to include("woven_in")
  end

  # The control: a class body calling into some *other* object is not
  # metaprogramming its own surface, and must not silence the check.
  it "is not opened by a class body calling into another object" do
    document = index(<<~RUBY_SRC)
      class Plainish
        LOGGER = Object.new
        LOGGER.freeze

        def show
          definitely_not_defined_zzz
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to include("definitely_not_defined_zzz")
  end

  # An open surface is a property of what is indexed *now*. Deleting the
  # macro must close it again -- otherwise the check falls silent about
  # that class for the rest of the session, and the user who removed the
  # macro to get their diagnostics back does not get them back.
  #
  # Found by the hunk-by-hunk sweep, not by review: the decrement in
  # `WorkspaceIndex#remove_file_locked` could be reverted with the whole
  # suite still green, which CLAUDE.md counts as a defect in its own
  # right. `#replace_file` removes and re-adds, so re-indexing an edited
  # file runs the same path.
  it "closes the surface again when the macro is edited away" do
    index(<<~RUBY_SRC)
      class Counter
        attr_atomic :value

        def show
          value
        end
      end
    RUBY_SRC

    document = index(<<~RUBY_SRC)
      class Counter
        def show
          value
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to eq(["value"])
  end
end

