# frozen_string_literal: true

require "tmpdir"

# **What a `self.included` hook does to the class it is handed.**
#
# The parser has read exactly one statement in such a hook since 0.2.11 --
# `base.extend(Const)`, the pre-`ActiveSupport::Concern` spelling -- and
# read everything else as nothing at all. A class that includes such a
# module therefore looked fully enumerated when it was not, and every
# method the hook gave it was reported missing. Ground truth:
#
#   $ ruby -e '
#   module Helpers
#     def from_helpers; end
#   end
#   module H2; def self.included(base) = base.include(Helpers); end
#   class W2; include H2; end
#   module H3; def self.included(base) = base.extend(Helpers); end
#   class W3; include H3; end
#   module H4
#     def self.included(base) = base.class_eval { def from_ce; end }
#   end
#   class W4; include H4; end
#   module H5; def self.extended(base) = base.include(Helpers); end
#   class W5; extend H5; end
#   p [W2.new.respond_to?(:from_helpers), W3.respond_to?(:from_helpers),
#      W4.new.respond_to?(:from_ce), W5.respond_to?(:from_helpers)]
#   '
#   # => [true, true, true, false]
#   # ruby 3.4.10
#
# Three of the four were reported. The fourth -- `W5` -- is Ruby saying
# `false`, and the report on it is **correct**: `extended`'s hook calls
# `base.include`, which puts the module on the instance chain, so the
# class-level call really does raise. It is kept below as the example that
# must not be silenced by either half of the fix.
#
# Two halves, because the three shapes are two different mistakes:
#
# - `base.include(Helpers)` and `base.class_eval { ... }` are statements
#   this parser cannot model, so the module's instance surface opens and
#   the including class is declined about. That is the same trade every
#   other unreadable class-body call makes.
# - `base.extend(Helpers)` *is* modelled -- and the recorded target was
#   then thrown away, `"#{module}::ClassMethods"` synthesised in its
#   place. Right only when the extended module happens to be spelled
#   `ClassMethods`. Reading the name the hook actually wrote costs no
#   silence at all, which is why it is not folded into the first half.
RSpec.describe "a self.included hook's effect on the including class" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  around do |example|
    Dir.mktmpdir do |root|
      @workspace_root = root
      example.run
    end
  end

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) do
    Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: @workspace_root) }
  end

  def context
    Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: stack.method_resolver,
      local_inferencer: stack.local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
  end

  def index(text, uri:)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  def unknown_methods(text)
    engine.analyze(document: index(text, uri: "file:///use.rb"), semantic_context: context, mode: :standard)
          .select { |finding| finding.code == "unknown-method" }
          .map { |finding| finding.message[/named `(.+)`/, 1] }
  end

  let(:helpers) { "module Helpers\n  def from_helpers; end\nend\n" }

  before { index(helpers, uri: "file:///helpers.rb") }

  describe "a hook this parser cannot model" do
    it "declines about a class whose hook includes another module" do
      index("module H2\n  def self.included(base) = base.include(Helpers)\nend\n", uri: "file:///h2.rb")

      expect(unknown_methods("class W2\n  include H2\n  def go = from_helpers\nend\n")).to be_empty
    end

    it "declines about a class whose hook class_evals it" do
      index("module H4\n  def self.included(base)\n    base.class_eval { def from_ce; end }\n  end\nend\n",
            uri: "file:///h4.rb")

      expect(unknown_methods("class W4\n  include H4\n  def go = from_ce\nend\n")).to be_empty
    end

    # **A call *on* the class, and nothing else.** The first version of
    # this rule counted every mention of the parameter, and a cold review
    # measured what that cost: of 51 hooks in eleven installed gems, 42
    # opened, and 55 of the 994 types in a six-gem corpus lost checking
    # entirely -- `Rails::Generators::Base`, `ActiveSupport::TestCase`,
    # `Thor`, every Devise generator. A dozen of those hooks add nothing
    # at all to the class:
    #
    #     raise ArgumentError unless base <= Hashie::Mash   # hashie
    #     (@re_include_to_bases ||= []) << base             # concurrent
    #     super(base); base.extend ClassMethods             # thor x3
    #
    # Ruby, 3.4.10, agrees that none of those adds a member: for a module
    # whose hook is only `raise ... unless base <= Object`, or only
    # `super(base)`, `W.new.respond_to?(:anything)` is `false`.
    #
    # So the rule is the effect, not the mention: a call whose *receiver*
    # is the parameter changes the class, and this parser can read exactly
    # one such call. Everything else -- a comparison, an interpolation, a
    # `super`, the class handed to another method -- is left alone. That
    # gives up `Registry.install(base)`, which really could add members
    # through code this parser cannot follow; it is the same judgement
    # made everywhere else here, and the measured alternative was worse.
    it "does not open the surface for a hook that only reads the class" do
      index("module Registry\n  def self.install(k); end\nend\n", uri: "file:///registry.rb")
      index("module H6\n  def self.included(base) = Registry.install(base)\nend\n", uri: "file:///h6.rb")

      expect(unknown_methods("class W6\n  include H6\n  def go = definitely_absent\nend\n"))
        .to include("definitely_absent")
    end

    it "does not open the surface for a hook that only compares the class" do
      index("module H11\n  def self.included(base)\n    raise ArgumentError unless base <= Object\n  end\nend\n",
            uri: "file:///h11.rb")

      expect(unknown_methods("class W11\n  include H11\n  def go = definitely_absent\nend\n"))
        .to include("definitely_absent")
    end

    # `super(base)` and a bare `super` are the same call in Ruby, and the
    # mention rule told them apart -- it saw a `LocalVariableReadNode` in
    # one and a `ForwardingSuperNode` in the other. Neither is a call on
    # the class, so neither opens now.
    it "treats super(base) and a bare super alike" do
      index("module H12\n  def self.included(base)\n    super(base)\n  end\nend\n", uri: "file:///h12.rb")
      index("module H13\n  def self.included(base)\n    super\n  end\nend\n", uri: "file:///h13.rb")

      expect(unknown_methods("class W12\n  include H12\n  def go = definitely_absent\nend\n"))
        .to include("definitely_absent")
      expect(unknown_methods("class W13\n  include H13\n  def go = definitely_absent\nend\n"))
        .to include("definitely_absent")
    end

    # **An `included` hook does not run on `extend`.** Ruby:
    # `Z.respond_to?(:from_helpers)` and `Z.new.respond_to?(:from_helpers)`
    # are both `false` for `class Z; extend H2`, where `H2`'s hook is
    # `base.include(Helpers)`. Opening the module's surface flatly meant
    # every class-level call on `Z` was declined about, and the real
    # instance is `concurrent-ruby/promises.rb:47 extend ReInclude`.
    #
    # So the surface is recorded under its own key and consulted only for
    # the relations whose hook it is.
    it "does not decline about a class that extends the module" do
      index("module Helpers\n  def from_helpers; end\nend\n", uri: "file:///helpers2.rb")
      index("module H2\n  def self.included(base) = base.include(Helpers)\nend\n", uri: "file:///h2.rb")

      expect(unknown_methods("class Z\n  extend H2\n  def self.go = definitely_absent\nend\n"))
        .to include("definitely_absent")
    end

    it "declines about a class that prepends it" do
      index("module H2\n  def self.included(base) = base.include(Helpers)\nend\n", uri: "file:///h2.rb")

      expect(unknown_methods("class P\n  prepend H2\n  def go = from_helpers\nend\n")).to be_empty
    end

    # **The control, and the reason the rule is not simply "a module with
    # a hook".** A hook whose every statement *is* modelled leaves the
    # class enumerated, so an ordinary typo in it is still reported.
    # Without this, opening the surface for every hook would pass all
    # three examples above.
    it "still reports a typo in a class whose hook is fully modelled" do
      index("module H1\n  def self.included(base) = base.extend(ClassMethods)\n" \
            "  module ClassMethods\n    def cm1; end\n  end\nend\n", uri: "file:///h1.rb")

      expect(unknown_methods("class W1\n  include H1\n  def go = definitely_absent\nend\n"))
        .to include("definitely_absent")
    end

    # The surface opens on the *module*, which is where the including
    # class's ancestor chain reaches it -- the class is in another file
    # this visitor never sees. Under its own key, not the instance one:
    # the two are different claims and only the ordinary one is true of a
    # class that extends the module.
    it "opens the module's own hook surface and not its instance surface" do
      index("module H2\n  def self.included(base) = base.include(Helpers)\nend\n", uri: "file:///h2.rb")

      expect(workspace_index.open_surface?("H2", kind: :included_hook)).to be(true)
      expect(workspace_index.open_surface?("H2")).to be(false)
      expect(workspace_index.open_surface?("Helpers", kind: :included_hook)).to be(false)
    end
  end

  describe "a hook whose extend target this parser did read" do
    # `base.extend(Helpers)` names `Helpers`, and the recorded name was
    # discarded in favour of `H3::ClassMethods`, which does not exist --
    # so the concern contributed nothing and every class method it gave
    # the class was reported.
    it "puts the extended module's methods on the including class" do
      index("module H3\n  def self.included(base) = base.extend(Helpers)\nend\n", uri: "file:///h3.rb")

      expect(unknown_methods("class W3\n  include H3\n  def self.go = from_helpers\nend\n")).to be_empty
    end

    # The control: reading the hook's target must not silence the class.
    it "still reports a typo beside it" do
      index("module H3\n  def self.included(base) = base.extend(Helpers)\nend\n", uri: "file:///h3.rb")

      expect(unknown_methods("class W3\n  include H3\n  def go = definitely_absent\nend\n"))
        .to include("definitely_absent")
    end

    # The `ClassMethods` route is a union with the hook's, not replaced by
    # it: a module may carry both markers.
    it "keeps the nested ClassMethods route" do
      index("module H1\n  def self.included(base) = base.extend(ClassMethods)\n" \
            "  module ClassMethods\n    def cm1; end\n  end\nend\n", uri: "file:///h1.rb")

      expect(unknown_methods("class W1\n  include H1\n  def self.go = cm1\nend\n")).to be_empty
    end

    # **Resolved with the hook's own nesting**, not by a workspace-wide
    # pick among every module that nests a module of that name. Two
    # concerns each nesting a `Mixin` is the ordinary case, and picking
    # either for both is `024.15`'s ambiguity.
    #
    # The nested module is deliberately *not* called `ClassMethods` here:
    # the fallback route synthesises that name from the concern itself, so
    # a hook extending a `ClassMethods` is resolved correctly by the
    # fallback whatever the hook's own resolution does. Naming it `Mixin`
    # leaves the hook's route as the only one, which is what this example
    # is about.
    it "resolves the hook's target within the module that wrote it" do
      index("module A1\n  def self.included(base) = base.extend(Mixin)\n" \
            "  module Mixin\n    def a_cm; end\n  end\nend\n", uri: "file:///a1.rb")
      index("module B1\n  def self.included(base) = base.extend(Mixin)\n" \
            "  module Mixin\n    def b_cm; end\n  end\nend\n", uri: "file:///b1.rb")

      expect(unknown_methods("class WA\n  include A1\n  def self.go = a_cm\nend\n")).to be_empty
      expect(unknown_methods("class WB\n  include B1\n  def self.go = b_cm\nend\n")).to be_empty
    end

    # A hook naming a module this workspace does not hold is a gem's, and
    # whatever it declares is on the class.
    it "declines when the hook extends a module the workspace does not hold" do
      index("module H7\n  def self.included(base) = base.extend(SomeGem::Mixin)\nend\n", uri: "file:///h7.rb")

      expect(unknown_methods("class W7\n  include H7\n  def self.go = whatever_the_gem_added\nend\n")).to be_empty
    end

    # **Pinned on the chain, because that is where the difference is.**
    # Read as identified, `SomeGem::Mixin` is still a name no signature
    # set declares, so the check declines by the other route and the
    # example above passes either way -- the same asymmetry
    # `class_body_macro_spec` records for the Class/Module tail. What
    # changes is the chain: identified, the name arrives carrying the
    # whole `Object, Kernel, BasicObject` tail, which claims an ancestry
    # that was never built for every later reader of `#ancestors`.
    it "records the unresolvable target as one entry with no name and no tail" do
      index("module H7\n  def self.included(base) = base.extend(SomeGem::Mixin)\nend\n", uri: "file:///h7.rb")
      index("class W7\n  include H7\nend\n", uri: "file:///w7.rb")

      expect(hierarchy_index.ancestors("W7", singleton: true).map(&:name_or_nil)).to eq(["::W7", nil])
    end
  end

  # **Ruby says `false` here**, so the report is right and neither half of
  # the fix may remove it. `extended`'s hook calls `base.include`, which
  # puts `Helpers` on the instance chain -- a class-level call raises.
  it "still reports a class-level call an extended hook did not provide" do
    index("module H5\n  def self.extended(base) = base.include(Helpers)\nend\n", uri: "file:///h5.rb")

    expect(unknown_methods("class W5\n  extend H5\n  def self.go = from_helpers\nend\n"))
      .to include("from_helpers")
  end
end
