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
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:method_resolver) { stack.method_resolver }
  let(:local_inferencer) { stack.local_inferencer }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
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
  # **0.2.11 reversed this and rolled the reversal back inside the same
  # release.** The reversal marked the owner's *class* surface open as
  # well, which is right for the class in front of you and catastrophic
  # for `class Module`, `class Object` or `class Kernel` -- they are in
  # every class's singleton chain, so one bare `alias_method` in a
  # `core_ext` file switched off `Foo.bar` checking for the whole
  # workspace. A `drive` round measured it over 1,659 files of 16 gems:
  # constant-receiver `unknown-method` findings **117 -> 0**, and among
  # the 148 removals a real latent `NoMethodError`
  # (`ActiveRecord::Promise.wrap`). The measurement that justified the
  # reversal had the same contamination -- its corpus contained
  # activesupport's `core_ext/module/attr_internal.rb`, a bare
  # `alias_method` in `class Module` -- and the sampling missed it.
  #
  # So the macro call itself is reported again, and `024.110` is open
  # with what a real fix has to distinguish: "I could not read *this
  # class's* body" from "I could not read `Module`'s".
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

  # The rule as first shipped was far broader than its own recorded
  # measurement, and the measurement was taken against a different rule
  # than the one that shipped. Re-measured over the same 213 files with
  # the shipped code: **52 of 329 class and module names open**, not the
  # 24 of 257 recorded, and the triggering names include `warn`,
  # `respond_to?`, `lambda`, `<` and `private_method_defined?` -- none of
  # which can define anything.
  #
  # Two things were wrong. The claim, corrected in 035 and in the table
  # above; and the rule, which counted receiverless calls written *inside
  # a block*. A block's meaning belongs to the call that owns it:
  # `included do ... end` is unreadable and opens the surface, but
  # `assert_equal` written inside somebody's `test` block says nothing
  # about the enclosing class's members. Counting both silenced a class
  # for the whole session over a lambda in a constant.
  it "is not opened by a receiverless call inside a lambda" do
    document = index(<<~RUBY_SRC)
      class Service
        DEFAULT = -> { helper_thing }

        def run
          definitely_not_defined_zzz
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to include("definitely_not_defined_zzz")
  end

  it "is not opened by a receiverless call inside somebody else's block" do
    document = index(<<~RUBY_SRC)
      class Suite
        [1, 2].each { |n| some_helper(n) }

        def run
          definitely_not_defined_zzz
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to include("definitely_not_defined_zzz")
  end

  # The control, and the shape the block rule must not break: the call
  # that *owns* an unreadable block still opens the surface, because
  # `included do ... end` and `class_eval { ... }` really do define
  # methods on the owner.
  it "is still opened by an unreadable call that takes a block" do
    document = index(<<~RUBY_SRC)
      class Concernish
        included do
          def woven_in; end
        end

        def run
          woven_in
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).not_to include("woven_in")
  end

  it "is not opened by a class-body call that cannot define anything" do
    document = index(<<~RUBY_SRC)
      class Noisy
        warn "deprecated"

        def run
          definitely_not_defined_zzz
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to include("definitely_not_defined_zzz")
  end

  # A setter and an operator are named in a way no method-defining macro
  # is. Ruby will not let you write `def default_query_parser=(v)` and
  # have it define something else, and `Foo < Bar` in a class body is a
  # comparison. Expressed as a shape rather than added to the list, since
  # the list can only ever name the calls somebody has already seen.
  it "is not opened by a setter or an operator in the class body" do
    document = index(<<~RUBY_SRC)
      class Configured
        self.default_query_parser = 1
        singleton_class < Comparable

        def run
          definitely_not_defined_zzz
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to include("definitely_not_defined_zzz")
  end

  # An `include` of a module the workspace cannot identify leaves the
  # *instance* chain correctly open -- the entry is there with no kind, so
  # `#ancestor_known?` refuses it. The singleton chain carried no trace of
  # it at all and therefore looked complete, and a `included`/`extended`
  # hook is exactly how a Ruby module adds class methods.
  #
  # Measured by a reviewer driving the real server: `include Singleton` +
  # `.instance`, `include Sidekiq::Worker` + `sidekiq_options`,
  # `include ActiveModel::Model` + `validates`, and 8 more of the same
  # shape across `mail-2.9.1` -- all wrong reports on working code, all in
  # the configuration a first-time user meets, since a plain Ruby project
  # never gets a Runtime Agent and a Rails project in Restricted Mode does
  # not either.
  it "says nothing at class level about a class that includes a module it cannot identify" do
    document = index(<<~RUBY_SRC)
      class ImportWorker
        include Sidekiq::Worker

        sidekiq_options queue: "low"
      end
    RUBY_SRC

    expect(unknown_methods(document)).to be_empty
  end

  # The control: without the unidentifiable include, the same class-level
  # call is still reported -- 024.23's behaviour, which this must not undo.
  it "still reports that class-level call when every ancestor is identified" do
    document = index(<<~RUBY_SRC)
      module Known
        def helper; end
      end

      class ImportWorker
        include Known

        sidekiq_options queue: "low"
      end
    RUBY_SRC
    expect(unknown_methods(document)).to eq(["sidekiq_options"])
  end

  # The message names the *branch* when a Union has one reportable
  # member, and the whole receiver otherwise. Both arms are reachable and
  # they differ, so a reader seeing `Widget | nil` in a report is being
  # told something different from `Widget` -- and `evidence[:receiver]`
  # carries the same string to anyone consuming findings.
  it "names the single reportable branch rather than the whole union" do
    document = index(<<~RUBY_SRC)
      class Widget
        def build = nil
      end

      class Caller
        def go(flag)
          maybe = flag ? Widget.new : nil
          maybe.definitely_not_defined_zzz
        end
      end
    RUBY_SRC

    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
    finding = engine.analyze(document: document, semantic_context: context, mode: :standard)
                    .find { |f| f.code == "unknown-method" }

    expect(finding&.evidence&.fetch(:receiver)).to eq("Widget")
  end

  # Inside `class << self`, an unreadable call defines *singleton*
  # methods, so it must open that surface and not the instance one.
  # Reverting the branch that decides this left the whole suite green.
  it "opens the class-level surface for an unreadable call inside class << self" do
    document = index(<<~RUBY_SRC)
      class Woven
        class << self
          weave_in_class_methods :a
        end
      end

      class Caller
        def go = Woven.woven
      end
    RUBY_SRC

    expect(unknown_methods(document)).to be_empty
  end

  it "leaves the instance surface closed in that case" do
    document = index(<<~RUBY_SRC)
      class Woven
        class << self
          weave_in_class_methods :a
        end

        def run
          definitely_not_defined_zzz
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to include("definitely_not_defined_zzz")
  end

  # A module reached through `extend M` contributes its **instance**
  # surface to the class-level chain, so asking `M` about its *singleton*
  # surface answers about the wrong side and the report goes out anyway.
  # The `include` spelling of the same thing was already silent.
  it "reads an extended module's instance surface when asked at class level" do
    document = index(<<~RUBY_SRC)
      module Helper
        attr_atomic :thing
      end

      class Host
        extend Helper
      end

      class Caller
        def go = Host.thing
      end
    RUBY_SRC

    # Narrowed in 0.2.10 from `be_empty` to the call this example is
    # about. The macro call itself -- `attr_atomic :thing` -- is reported,
    # and always was on a *class*; it went unreported here only because
    # nothing checked a module's class-level calls at all, which
    # `024.106` fixed. That asymmetry (the engine silences what a macro
    # might define and reports the macro) is `024.110`, not this example's
    # subject -- 0.2.11 reversed it and rolled the reversal back.
    expect(unknown_methods(document)).not_to include("thing")
  end

  # The control: a module that opens nothing leaves the class-level check
  # answering.
  it "still reports a class-level call through a module that opens nothing" do
    document = index(<<~RUBY_SRC)
      module Helper
        def readable; end
      end

      class Host
        extend Helper
      end

      class Caller
        def go = Host.definitely_not_defined_zzz
      end
    RUBY_SRC

    expect(unknown_methods(document)).to eq(["definitely_not_defined_zzz"])
  end

  # A recognised DSL called with a splat records no declarations at all --
  # `record_attribute_methods` needs literal arguments -- yet the surface
  # stayed closed because the *name* was on the recognised list. The rule
  # has to key on whether anything was actually recorded.
  it "opens the surface when a recognised DSL is called in a way it cannot read" do
    document = index(<<~RUBY_SRC)
      class Bag
        NAMES = [:a, :b]
        attr_reader(*NAMES)

        def show = a
      end
    RUBY_SRC

    expect(unknown_methods(document)).to be_empty
  end
end

