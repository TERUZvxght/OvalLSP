# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# `private`, `attr_reader` and their neighbours are `Module`'s instance
# methods, reached from a class body because the body's implicit receiver
# is the class -- whose singleton chain runs Class, Module, Object,
# Kernel, BasicObject.
#
# `HierarchyIndex#ancestors(singleton: true)` modelled none of that tail:
# it walked the superclass chain and stopped. So on a workspace class
# whose ancestry is otherwise fully known -- which is every plain Ruby
# class, the receiver this check exists for -- every one of those calls
# resolved nowhere and was reported.
#
# Measured before the fix, with `scripts/corpus_diagnostics.rb`, against
# 0.1.13: 49 of the 60 `unknown-method` findings over this repository's
# own `core/lib` were this, out of 785 over ActiveSupport 8.1.3. It was
# the largest single source of wrong reports the engine produced, on the
# most ordinary Ruby there is (024.23).
#
# The engine had one name of this list special-cased -- `new`, whose
# comment names Class/Module as the unmodelled chain. Special-casing by
# name is what this replaces: the names are Ruby's, not ours to keep.
RSpec.describe "class-body macros are not unknown methods (024.23)" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  around do |example|
    Dir.mktmpdir do |root|
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

  def unknown_methods(body)
    engine.analyze(document: index(body), semantic_context: context, mode: :standard)
          .select { |finding| finding.code == "unknown-method" }
          .map { |finding| finding.message[/named `(.+)`/, 1] }
  end

  # One example per name rather than one example listing them, so a fix
  # that reaches `private` and not `attr_reader` fails on the one it
  # missed instead of on a list.
  {
    "private" => "  private\n",
    "protected" => "  protected\n",
    "public" => "  public\n",
    "attr_reader" => "  attr_reader :a\n",
    "attr_writer" => "  attr_writer :a\n",
    "attr_accessor" => "  attr_accessor :a\n",
    "private_constant" => "  X = 1\n  private_constant :X\n",
    "alias_method" => "  def a = 1\n  alias_method :b, :a\n",
    "module_function" => "  module_function\n",
    "define_method" => "  define_method(:c) { 1 }\n"
  }.each do |name, line|
    it "does not report `#{name}` in a class body" do
      expect(unknown_methods("class Widget\n#{line}end\n")).to be_empty
    end
  end

  # **A macro the parser read, and then reported.** `delegate` is one of
  # three DSLs `#record_generated_methods` understands: the parser reads
  # `delegate :size, to: :inner` and declares `size` from it. It then
  # emitted the `delegate` call itself as an ordinary method-call
  # candidate, so the check reported the very macro whose meaning the
  # parser had just used:
  #
  #     class W
  #       delegate :size, to: :inner    # W has no method named `delegate`
  #       def inner; []; end
  #     end
  #
  # Either the call is a macro this engine understands, in which case
  # reporting it is wrong, or it is not, in which case declaring `size`
  # from it was. What holds the answer is a *call-local* value, computed
  # where the declarations are counted and passed to the two readers that
  # want it -- see the two examples below, each of which is a defect the
  # ivar form had and no example caught.
  #
  # The control is the same class with a name nothing recorded: a macro
  # the parser cannot read must still leave the surface open rather than
  # silently exempting its own call.
  it "does not report a generated-method macro whose declarations it read" do
    expect(unknown_methods("class W\n  delegate :size, to: :inner\n  def inner; []; end\nend\n")).to be_empty
    expect(unknown_methods("class W\n  enum :status, %i[on off]\nend\n")).to be_empty
    expect(unknown_methods("class W\n  scope :recent, -> { 1 }\nend\n")).to be_empty
  end

  # **The control**, and it has to be a typo the check actually reaches:
  # an unrecognised *class-body* call is deliberately silent, because it
  # opens the surface. That asymmetry is the mechanism here -- reading
  # the macro is what closes the surface and exposes the macro's own call
  # to the check -- so the control is a typo inside a method body, where
  # the surface is closed for the ordinary reason.
  it "still reports an ordinary typo beside a macro it read" do
    expect(unknown_methods("class W\n  delegate :size, to: :inner\n  def inner; []; end\n  def go; definitely_absent; end\nend\n"))
      .to include(a_string_including("definitely_absent"))
  end

  # **A call the file guards with `respond_to?` is a call the author
  # already knows may not be there.** It is the idiom written to be safe
  # about exactly what this check reports, and reporting it tells the
  # author something they have said in the code that they know:
  #
  #     def go
  #       return unless respond_to?(:maybe_there)
  #       maybe_there
  #     end
  #
  # The same shape as the `defined?(@x)` exemption the unassigned-ivar
  # check already carries, and read the same way: by *name*, because a
  # file defensive about a name is defensive about it, and the typo this
  # check exists for appears in no `respond_to?`.
  it "does not report a call the file guards with respond_to?" do
    expect(unknown_methods("class W\n  def go\n    return unless respond_to?(:maybe_there)\n    maybe_there\n  end\nend\n"))
      .to be_empty
    expect(unknown_methods("class W\n  def go\n    maybe_there if respond_to?(\"maybe_there\")\n  end\nend\n"))
      .to be_empty
  end

  # **The guard is the *true* branch, not the body it was written in.**
  # `024.335` scoped a guard to its enclosing `def`/`class`/file, and said
  # so: a guard in the false arm exempted the true arm as well. The
  # 2026-09-05 review's condition for R07 asked for the true branch alone,
  # and a follow-up review's verdict was that documenting the gap does not
  # satisfy the condition. It does not. Ruby, 3.4.10:
  #
  #   $ ruby -e '
  #   class W
  #     def guarded_true;  if respond_to?(:maybe) then maybe else 0 end; end
  #     def guarded_false; if respond_to?(:maybe) then 0 else maybe end; end
  #     def early;         return 1 unless respond_to?(:maybe); maybe; end
  #     def andform;       respond_to?(:maybe) && maybe; end
  #   end
  #   %i[guarded_true guarded_false early andform].each do |m|
  #     begin
  #       W.new.send(m); puts "#{m}: ran"
  #     rescue NameError => e
  #       puts "#{m}: NameError"
  #     end
  #   end'
  #   # => guarded_true: ran
  #   #    guarded_false: NameError
  #   #    early: ran
  #   #    andform: ran
  #   # ruby 3.4.10
  #
  # So three of the four shapes are guarded and one raises, and the
  # implementation must tell them apart.
  describe "which side of the condition the guard covers" do
    it "exempts the true branch of an if" do
      expect(unknown_methods("class W\n  def go\n    if respond_to?(:maybe)\n      maybe\n    end\n  end\nend\n"))
        .to be_empty
    end

    it "reports the same call in the else branch" do
      source = "class W\n  def go\n    if respond_to?(:maybe)\n      1\n    else\n      maybe\n    end\n  end\nend\n"

      expect(unknown_methods(source)).to include("maybe")
    end

    # `unless` is the mirror: its `else` is the guarded side.
    it "reports the statements of an unless and exempts its else" do
      guarded = "class W\n  def go\n    unless respond_to?(:maybe)\n      1\n    else\n      maybe\n    end\n  end\nend\n"
      reported = "class W\n  def go\n    unless respond_to?(:maybe)\n      maybe\n    end\n  end\nend\n"

      expect(unknown_methods(guarded)).to be_empty
      expect(unknown_methods(reported)).to include("maybe")
    end

    # **The commonest spelling in Ruby, and the one a branch rule loses if
    # it only reads the arms.** `return unless` leaves the guard true for
    # everything after it, so the scope is the rest of the enclosing body.
    %w[return raise\ "x" next break].each do |jump|
      it "exempts the rest of the body after `#{jump} unless`" do
        source = "class W\n  def go\n    #{jump} unless respond_to?(:maybe)\n    maybe\n  end\nend\n"

        expect(unknown_methods(source)).to be_empty
      end
    end

    # Its control: an `unless` whose body does *not* leave guards nothing
    # after it, and Ruby agrees -- execution falls through.
    it "still reports after an unless whose body does not leave" do
      source = "class W\n  def go\n    1 unless respond_to?(:maybe)\n    maybe\n  end\nend\n"

      expect(unknown_methods(source)).to include("maybe")
    end

    it "exempts the right of an and, and the body of an or-return" do
      expect(unknown_methods("class W\n  def go\n    respond_to?(:maybe) && maybe\n  end\nend\n")).to be_empty
      expect(unknown_methods("class W\n  def go\n    respond_to?(:maybe) or return\n    maybe\n  end\nend\n")).to be_empty
    end

    it "reports the right of an or, which runs when the guard is false" do
      expect(unknown_methods("class W\n  def go\n    respond_to?(:maybe) || maybe\n  end\nend\n")).to include("maybe")
    end

    # A `respond_to?` that is not a condition at all guards nothing.
    it "reports a call beside a bare respond_to? that decides nothing" do
      expect(unknown_methods("class W\n  def go\n    respond_to?(:maybe)\n    maybe\n  end\nend\n")).to include("maybe")
    end
  end

  # **The controls.** A guard on one name says nothing about another, and
  # a guard with a receiver is about *that* object rather than self.
  it "still reports a different name beside a respond_to? guard" do
    expect(unknown_methods("class W\n  def go\n    return unless respond_to?(:maybe_there)\n    definitely_absent\n  end\nend\n"))
      .to include(a_string_including("definitely_absent"))
  end

  it "still reports when the guard is about another object" do
    expect(unknown_methods("class W\n  def go(other)\n    return unless other.respond_to?(:maybe_there)\n    maybe_there\n  end\nend\n"))
      .to include(a_string_including("maybe_there"))
  end

  # **`self.respond_to?` is the same guard.** The parser's own
  # `#open_surface_kind` reads `nil` and `Prism::SelfNode` alike, and this
  # collector did not -- so the explicit spelling, which is ordinary in
  # application code, was still reported. Ruby runs both. Found by two
  # independent cold reviews and by the 2026-09-05 critical review (R07).
  it "reads an explicit self on the guard" do
    expect(unknown_methods("class W\n  def go\n    return unless self.respond_to?(:maybe_there)\n    maybe_there\n  end\nend\n"))
      .to be_empty
  end

  # **The exemption is about `self`, so it applies to calls on `self`.**
  # By name and nothing else, a guard silenced `Other.new.maybe_there`
  # in the same file -- a different object, about which the guard says
  # nothing. This is the half of the `defined?(@x)` analogy that does not
  # carry: an ivar has no receiver and a method call does.
  it "still reports the guarded name on another object" do
    index("class Other\nend\n", uri: "file:///other.rb")
    source = "class W\n  def go\n    return unless respond_to?(:maybe_there)\n    Other.new.maybe_there\n  end\nend\n"

    expect(unknown_methods(source)).to include(a_string_including("maybe_there"))
  end

  # **A guard scopes to the body it was written in.** File-wide by name,
  # a guard in one method silenced the same name called *unguarded* in
  # another -- which is the forgotten-guard mistake, not the typo this
  # check is framed around, and it is the one a reader would most want
  # reported.
  it "does not carry the guard into another method" do
    source = "class W\n  def guarded\n    maybe_there if respond_to?(:maybe_there)\n  end\n" \
             "  def unguarded\n    maybe_there\n  end\nend\n"

    expect(unknown_methods(source)).to include(a_string_including("maybe_there"))
  end

  it "does not carry the guard into another class in the same file" do
    source = "class A\n  def go\n    maybe_there if respond_to?(:maybe_there)\n  end\nend\n" \
             "class B\n  def go\n    maybe_there\n  end\nend\n"

    expect(unknown_methods(source)).to include(a_string_including("maybe_there"))
  end

  # The control for the three above: the guard still works where it is
  # written, in each of the idiom's three spellings. Without this, a fix
  # that scoped the guard to nothing would pass all of them.
  it "still exempts the call in the body the guard is written in" do
    guard_then_call = "class W\n  def go\n    return unless respond_to?(:maybe_there)\n    maybe_there\n  end\nend\n"
    trailing_if = "class W\n  def go\n    maybe_there if respond_to?(:maybe_there)\n  end\nend\n"
    block_form = "class W\n  def go\n    if respond_to?(:maybe_there)\n      maybe_there\n    end\n  end\nend\n"

    expect(unknown_methods(guard_then_call)).to be_empty
    expect(unknown_methods(trailing_if)).to be_empty
    expect(unknown_methods(block_form)).to be_empty
  end

  # **A macro is a class-body call, and the recorders never asked.**
  # `#record_generated_methods` runs wherever `current_owner` is set, so a
  # `delegate` written *inside a method body* declared a method from it --
  # and, once `024.327` marked what the parser read, silenced the call
  # too. Both are wrong, and Ruby says so:
  #
  #   $ ruby -e '
  #   gem "activesupport"; require "active_support/all"
  #   class Q
  #     def inner = []
  #     def setup; delegate :size, to: :inner; end
  #   end
  #   begin; Q.new.setup; rescue NoMethodError => e; puts e.message; end
  #   p Q.new.respond_to?(:size)
  #   '
  #   # => undefined method 'delegate' for an instance of Q
  #   #    false
  #   # ruby 3.4.10, activesupport 8.1.3.1
  #
  # `delegate` is `Module`'s, so an instance has none, and nothing named
  # `size` is ever defined. Found independently by two cold reviews.
  #
  # `in_method_body?` rather than `#defines_surface?`: a block is the
  # other thing that method refuses, and `included do ... end` runs in
  # class context, where the macro really does define what it says.
  it "declares nothing from a macro written inside a method body" do
    source = "class Q\n  def inner; []; end\n  def setup\n    delegate :size, to: :inner\n  end\nend\n"

    expect(unknown_methods(source)).to include("delegate")
  end

  # **The block has to be one that does not open the surface**, or the
  # example cannot fail. The first version used `included do ... end`,
  # which is itself an unreadable class-body call: `size` was silent
  # whether or not the block's `delegate` was read, and the example passed
  # on the parent commit too. Found by cold review -- an assertion that
  # cannot fail, arriving through the fixture.
  #
  # `%i[...].each { }` has a receiver, so it opens nothing, and `self` in
  # the block is still the class -- which is the claim being made.
  it "still reads a macro written inside a class-context block" do
    source = "class Q\n  def inner; []; end\n  %i[a].each do |_|\n    delegate :size, to: :inner\n  end\n  def go = size\nend\n"

    expect(unknown_methods(source)).to be_empty
  end

  # Its control: the same class without the block reports `size`, so the
  # example above is the macro being read and not the class being silent.
  it "reports the same call when no macro declared it" do
    expect(unknown_methods("class Q\n  def inner; []; end\n  def go = size\nend\n")).to include("size")
  end

  # **The candidate survives; only the report stops.** The first fix
  # withheld the method-call candidate for any call that recorded a
  # declaration, and `#record_attribute_methods` records them too -- so
  # `attr_reader` lost the candidate that hover, go to definition,
  # references and documentHighlight all read, and so did a `scope` or
  # `delegate` in a workspace that defines one of its own. None of that
  # was the defect. Marked by range instead, which stops the report and
  # touches nothing else.
  #
  # Asserted on the summary rather than through a feature, because that is
  # where the loss was: every one of the four reads this list.
  it "keeps the method-call candidate for a macro it read" do
    document = Ovallsp::TextDocument.new(
      uri: "file:///c.rb", version: 1, language_id: "ruby",
      text: "class W\n  attr_reader :one\n  delegate :size, to: :inner\n  def inner; []; end\nend\n"
    )
    summary = Ovallsp::ParserService.new.summarize(document)
    names = summary.reference_candidates.select { |c| c.kind == :method_call }.map(&:name)

    expect(names).to include("attr_reader", "delegate")
    expect(summary.macro_call_ranges.length).to eq(2)
  end

  # **The sticky-ivar defect, in the reader `024.327` itself added.** The
  # flag was an ivar recomputed only in the receiverless branch, so a
  # later call *with* a receiver read a stale `true` and had its candidate
  # withheld. `W.new.definitely_absent` lost its report entirely, on a
  # class the macro above had nothing to do with.
  #
  # **In one file**, because that is the whole of the defect: the visitor
  # is per-document, so a fresh one starting with the flag unset hides it
  # entirely. The first version of this example indexed the macro and then
  # analysed the call as a separate document and passed under the sticky
  # form, which is `024.109`'s shape and is why this file has mutations.
  it "still reports a call with a receiver written after a macro" do
    expect(unknown_methods("class W\n  delegate :size, to: :inner\n  def inner; []; end\nend\nW.new.definitely_absent\n"))
      .to include("definitely_absent")
  end

  # **The same staleness, one reader over**, and this one predates
  # `024.327`. `#record_open_surface` exempts a call on `RECORDING_CALLS`
  # when a declaration was recorded, and read the same ivar:
  #
  #     class Sticky
  #       attr_reader :first                  # sets the flag
  #       self.delegate(*NAMES, to: :inner)   # receiver, so no reset
  #     end
  #
  # The splat is exactly what this parser cannot read, so `delegate`
  # declared nothing and the surface had to open. The stale flag said a
  # declaration had been recorded and it stayed closed, so every method
  # the macro defines was reported missing. Found by cold review.
  #
  # The control is the same file without the `attr_reader`: nothing sets
  # the flag, the surface opens, and `x` is silent on both trees -- so the
  # example that matters is this one, which is silent only with the fix.
  it "opens the surface for an unreadable macro written after a readable one" do
    source = "class Sticky\n  NAMES = %i[x y].freeze\n  attr_reader :first\n  def inner; []; end\n" \
             "  self.delegate(*NAMES, to: :inner)\n  def go; x; end\nend\n"

    expect(unknown_methods(source)).to be_empty
  end

  # Its control: with the surface genuinely closed, the same call *is*
  # reported. Without this, a change that opened every class's surface
  # would pass the example above.
  it "still reports the same call when no macro opened the surface" do
    expect(unknown_methods("class Sticky\n  attr_reader :first\n  def go; x; end\nend\n"))
      .to include("x")
  end

  it "does not report `include` or `extend` in a class body" do
    index("module Helper\nend\n", uri: "file:///helper.rb")

    expect(unknown_methods("class Widget\n  include Helper\n  extend Helper\nend\n")).to be_empty
  end

  it "does not report `private` inside a `class << self` body" do
    expect(unknown_methods("class Widget\n  class << self\n    private\n  end\nend\n")).to be_empty
  end

  it "does not report Module's methods called on a constant receiver" do
    expect(unknown_methods("class Widget\nend\nWidget.instance_methods\nWidget.name\n")).to be_empty
  end

  # `Class#new` is an instance method of `Class`, so it resolves through
  # the tail like any other. The engine carried a special case for this
  # one name, whose comment said Class/Module were not modelled; they are
  # now, and the name is Ruby's rather than a list this project keeps.
  # Closedness has to be judged on the chain the lookup will actually
  # search. Before 0.1.14 a singleton chain stopped at the class, so the
  # check asked the *instance* chain instead -- and 0.1.14 gave the
  # singleton chain a real tail without revisiting that. The two then
  # disagreed: `ActionController::TestRequest`'s instance chain reaches
  # BasicObject, so the receiver read as closed, while its singleton chain
  # is truncated by an unresolvable ancestor, so `new` was looked up in a
  # chain that does not contain `Class` and was reported.
  # The tail says what the *receiver* is, not what the last ancestor
  # happens to be. 0.1.14 keyed it on the name the walk terminated at, so
  # a class whose superclass chain ends at a module got the module tail --
  # no `Class` -- and `new` was reported on it. Real instance, real gem:
  # `ActionController::TestRequest`, whose chain ends at a module named
  # `Request`.
  it "ends a class's chain in Class even when its ancestors end at a module" do
    index("module Mixinish\nend\nclass Base < Mixinish\nend\nclass Derived < Base\nend\n")

    expect(hierarchy_index.ancestors("Derived", singleton: true).map(&:name_or_nil).last(5))
      .to eq(["Class", "Module", "Object", "Kernel", "BasicObject"])
  end

  it "does not report `new` on a class whose ancestors end at a module" do
    index("module Mixinish\nend\nclass Base < Mixinish\nend\n", uri: "file:///base.rb")

    expect(unknown_methods("class Derived < Base\n  def self.create\n    new\n  end\nend\n")).to be_empty
  end

  def argument_counts(body)
    engine.analyze(document: index(body), semantic_context: context, mode: :standard)
          .select { |finding| finding.code == "argument-count" }
          .map { |finding| finding.message[/`(.+?)`/, 1] }
  end

  # The tail exists so that class-level calls *resolve*, which stops false
  # "unknown method" reports. Letting it also *produce* arity reports is
  # the aggressive direction, and it is where the model is weakest: a
  # `module_function`, a `define_method` or a `method_missing` can shadow
  # a Kernel/Module method without this engine knowing.
  #
  # Real instance: Ruby's own `json/generic_object.rb` calls
  # `::JSON.load(source, proc, opts)`. `JSON` declares that method with
  # `module_function`, which this engine does not model, so the call
  # resolved to a reopened `Kernel#load` through the tail and a correct
  # three-argument call was reported.
  it "does not judge arity against a declaration reached through the tail" do
    index("module Kernel\n  def load(path, wrap = false); end\nend\n", uri: "file:///kernel_ext.rb")
    index("module JSONish\nend\n", uri: "file:///jsonish.rb")

    expect(argument_counts("JSONish.load(1, 2, 3)\n")).to be_empty
  end

  # The check still does its job where the workspace states the method.
  it "still reports arity against a declaration the workspace wrote" do
    index("class Widget\n  def self.build(a, b); end\nend\n", uri: "file:///widget.rb")

    expect(argument_counts("Widget.build(1, 2, 3)\n")).to eq(["build"])
  end

  # A brace-less trailing hash is bound to a *positional* parameter when
  # the method declares no keywords: `add("a", "K" => 1)` passes two
  # arguments, not one. Counting it as keywords reported 526 calls over
  # brakeman and its vendored gems -- 399 of them in `sexp_processor`'s
  # `pt_testcase.rb` alone.
  # The miscount predates 0.1.14; what 0.1.14 changed is that a
  # receiverless call in a class body resolves now, so it reached this
  # check for the first time.
  it "counts a brace-less trailing hash as the positional it binds to" do
    source = <<~'RUBY'
      class T
        def self.add_tests(name, hash)
          [name, hash]
        end

        add_tests "a", "K" => 1
      end
    RUBY

    expect(argument_counts(source)).to be_empty
  end

  # `def m(...)` forwards everything, so no call to it can be judged.
  # `extract_parameters` read `...` as no parameters at all, which made
  # every positional call to such a method a report -- pre-existing -- and
  # the trailing-hash fix above widened it to keyword-only calls. 109 such
  # declarations in Rails 8.1.3; net-imap's `body_section_attr` is one.
  it "judges no call to a method that forwards with `...`" do
    source = <<~'RUBY'
      class Fwd
        def self.wrap(...); end

        def self.go
          wrap(offset: 1)
          wrap(1, 2)
        end
      end
    RUBY

    expect(argument_counts(source)).to be_empty
  end

  it "judges no call to a method that forwards after a positional" do
    source = <<~'RUBY'
      class Fwd
        def self.wrap(first, ...); end

        def self.go
          wrap(1, 2, 3)
        end
      end
    RUBY

    expect(argument_counts(source)).to be_empty
  end

  # `**opts` passes whatever the hash holds -- nothing at all when it is
  # empty. Counting the double splat as one positional reported
  # `ping(**opts)`, `ping(**{})` and `ping(**nil)`, all of which run.
  # Two callees, because which one distinguishes the branches depends on
  # the arity: against a zero-parameter callee, not bailing out counts the
  # hash as one positional and reports "takes 0 arguments, but 1 given";
  # against a one-parameter callee it lands inside the range instead, and
  # the fixture would pass either way. `ping(**{x: 1})` binds the hash to
  # `a` in Ruby, and `ping(**{})` passes nothing at all.
  {
    "no parameters" => "def self.ping; end",
    "one required parameter" => "def self.ping(a); end"
  }.each do |label, declaration|
    it "judges no call that passes a double splat, against a callee with #{label}" do
      source = "class Sp\n  #{declaration}\n\n  def self.go(opts)\n    ping(**opts)\n    ping(**{})\n  end\nend\n"

      expect(argument_counts(source)).to be_empty
    end
  end

  # Not when the method really does take keywords -- there the hash is
  # the keywords, and the positional count stands. One example per kind:
  # a required keyword, an optional one, and `**rest` each mean the hash
  # is keywords, and a fixture with only the first pins only the first.
  {
    "a required keyword" => "def self.build(name, size:); end",
    "an optional keyword" => "def self.build(name, size: 1); end",
    "a keyword rest" => "def self.build(name, **rest); end"
  }.each do |label, declaration|
    it "still counts keywords as keywords when the method declares #{label}" do
      source = "class T\n  #{declaration}\n\n  build \"x\" => 1\nend\n"

      expect(argument_counts(source)).to eq(["build"])
    end
  end

  it "does not report `new` on a constant receiver" do
    expect(unknown_methods("class Widget\nend\nWidget.new\n")).to be_empty
  end

  # The point of the check is to still catch what is genuinely absent.
  # Without this, "report nothing on a singleton receiver" would pass
  # every example above.
  # **`024.110`, and the distinction 0.2.12 built to hold it.** 0.2.11
  # made a bare class-body call open the owner's class surface too, and
  # rolled it back the same release: `#open_surface?` read that through
  # the `Class`/`Module`/`Object` tail of every chain, so one bare
  # `alias_method` in a `core_ext` file silenced `Foo.bar` for the whole
  # workspace -- 117 constant-receiver findings to 0 over 16 gems, with a
  # real latent `NoMethodError` among the losses.
  #
  # The reader ignores a *synthesised* link now, so the claim is about
  # this owner and nobody who merely inherits from `Module`. The macro is
  # not reported, because the engine has already declined to enumerate
  # what it might define -- two answers about one fact, which is what the
  # entry was always about.
  it "says nothing about a singleton call in a body it could not read" do
    expect(unknown_methods("class Widget\n  definitely_not_a_macro :a\nend\n")).to be_empty
  end

  it "still reports an absent class method on a constant receiver" do
    expect(unknown_methods("class Widget\nend\nWidget.no_such_class_method\n")).to eq(["no_such_class_method"])
  end

  # A `define_method` block's body becomes an *instance* method, so `self`
  # inside it is an instance -- even though the block is written inside
  # `def self.x`, where self is the class. Propagating the enclosing def's
  # self into the block reported two things on Ruby 3.4.7's own
  # `rdoc/markdown.rb`, where `def self.extension` defines instance
  # methods whose bodies call the instance `extension?`/`extension`:
  # `extension?` unknown, and `extension` called with 2 arguments against
  # the 1-argument singleton definition. This fixture is that shape.
  it "reads a define_method block's body as an instance, inside `def self.`" do
    source = <<~'RUBY'
      class Widget
        def self.build(name)
          define_method("#{name}?") { flagged? name }
          define_method("#{name}=") { |value| assign name, value }
        end

        def flagged?(name) = true
        def assign(name, value) = nil
      end
    RUBY

    expect(unknown_methods(source)).to be_empty
    expect(argument_counts(source)).to be_empty
  end

  # The same block written at class level, where the enclosing self is
  # already the class, must keep resolving its body as an instance too.
  it "reads a define_method block's body as an instance, in a class body" do
    source = "class Widget\n  define_method(:a) { flagged? }\n  def flagged? = true\nend\n"

    expect(unknown_methods(source)).to be_empty
  end

  # **The example that used to sit here could no longer distinguish
  # anything, and is gone rather than adjusted.** It asserted that
  # `[1, 2].each { definitely_not_a_macro }` in a class body reports the
  # call -- true when a block isolated the cref, and false since 0.2.13
  # made a literal iteration share it (`024.117`), because the call is
  # then the class body's own and `024.110` declines about an owner whose
  # body it could not read.
  #
  # That is `024.110`'s recorded cost arriving in a spec rather than in a
  # corpus, and the honest response is to say so. What the example was
  # *for* -- an ordinary block resolves against the class and not an
  # instance -- is still distinguished by the two `define_method`
  # examples above and the `instance_eval` pair below, whose fixtures do
  # not turn on an unreadable call.

  # A `define_method` block written inside `class << self` defines a
  # *singleton* method, so its body's self is the class object -- still a
  # Module. Pushing instance-self unconditionally reported this, on code
  # Ruby runs (`SDM.built` answers 42).
  it "reads a define_method block inside `class << self` as the class" do
    source = <<~RUBY
      class SDM
        class << self
          define_method(:built) { helper_on_class }
          def helper_on_class = 42
        end
      end
    RUBY

    expect(unknown_methods(source)).to be_empty
  end

  # `instance_eval` sets self to the *receiver*, and a receiverless one in
  # a class body has the class as its receiver -- so `attr_accessor` there
  # is exactly as legal as it is one line up. 0.1.14 listed `instance_eval`
  # and `instance_exec` alongside `define_method` with neither a reason
  # nor a test, and reported this.
  it "reads an instance_eval block in a class body as the class" do
    source = "class InstEvalCase\n  instance_eval do\n    attr_accessor :x\n  end\nend\n"

    expect(unknown_methods(source)).to be_empty
  end

  # `instance_eval` sets self to its *receiver*. Receiverless in a class
  # body or in `def self.`, that receiver is the class -- which is why
  # `instance_eval { attr_accessor :x }` is as legal as the line above it.
  # With an explicit receiver it is an instance, and treating the block as
  # class-level then reports the instance methods it calls.
  it "reads an instance_eval block on an explicit receiver as an instance" do
    source = <<~'RUBY'
      class W
        def helper; end

        def self.setup(other)
          other.instance_eval do
            helper
          end
        end
      end
    RUBY

    expect(unknown_methods(source)).to be_empty
  end

  # `define_method` defines a *singleton* method only when it is written
  # directly in a `class << self` body. Called from inside a `def` -- even
  # a `def` in that body -- self at that moment is the class object, so it
  # defines an ordinary instance method and its block's self is an
  # instance. `@singleton_context_stack` answers the first question and
  # `visit_def_node` never pushes it, so reading it alone reported the
  # block's calls against the singleton side. This shape is in Thor,
  # minitest, `rails/engine.rb` and `action_view/base.rb`.
  it "reads a define_method inside a def inside `class << self` as an instance" do
    source = <<~'RUBY'
      class Report
        class << self
          def define_formats(*names)
            names.each { |name| define_method("to_#{name}") { render(name) } }
          end
        end

        def render(name) = name.to_s

        define_formats :csv, :json
      end
    RUBY

    expect(unknown_methods(source)).to be_empty
  end

  # An explicit receiver is the same: `W.define_method(:m) { ... }` defines
  # an instance method of W whatever body it is written in.
  #
  # Written *directly* in `class << self`, not inside a `def` there: with
  # a `def` around it `!@in_method_body` already answers, and the receiver
  # term is dead for the fixture -- a spec that cannot distinguish the two
  # branches pins neither. Ruby confirms the answer: for this source,
  # `Report.new.later` works and `Report.respond_to?(:later)` is false.
  it "reads a define_method with an explicit receiver as an instance" do
    source = <<~'RUBY'
      class Report
        class << self
          Report.define_method(:later) { render("x") }
        end

        def render(name) = name.to_s
      end
    RUBY

    expect(unknown_methods(source)).to be_empty
  end

  # Receiverless `instance_eval` takes the *enclosing* self, whatever it
  # is -- the class in a class body, the instance inside an instance
  # method. Answering "the class" for both reported every instance method
  # such a block calls. `P.new.use` returns "instance-side" in Ruby.
  it "reads a receiverless instance_eval inside a method as an instance" do
    source = <<~'RUBY'
      class Foo
        def use
          instance_eval { helper }
        end

        def use2
          instance_exec { helper }
        end

        def helper = "instance-side"
      end
    RUBY

    expect(unknown_methods(source)).to be_empty
  end

  it "does not report `superclass` on a class" do
    expect(unknown_methods("class Widget\nend\nWidget.superclass\n")).to be_empty
  end

  # The class/module difference cannot be shown through diagnostics: a
  # module receiver produces no unknown-method finding at all, on this
  # branch and on `main` alike (verified against both -- `Helper.no_such_thing`
  # is silent either way). So the distinction is pinned where it exists,
  # on the chain itself. A module is a `Module` but not a `Class`, which
  # is why `superclass` answers on one and not the other; giving both the
  # same tail would be the easy wrong version of this fix.
  it "ends a class's singleton chain in Class and a module's in Module" do
    index("class Widget\nend\nmodule Helper\nend\n")

    expect(hierarchy_index.ancestors("Widget", singleton: true).map(&:name_or_nil))
      .to eq(["::Widget", "Object", "BasicObject", "Class", "Module", "Object", "Kernel", "BasicObject"])
    expect(hierarchy_index.ancestors("Helper", singleton: true).map(&:name_or_nil))
      .to eq(["::Helper", "Module", "Object", "Kernel", "BasicObject"])
  end

  # The tail belongs at the end of the chain, once -- not at each step of
  # it. Appending it per class would put Class/Module *between* a child
  # and its parent, so a parent's own singleton method would rank below
  # `Module#name` and resolve to the wrong declaration.
  it "appends the tail once, after the whole superclass chain" do
    index("class Base\nend\nclass Widget < Base\nend\n")

    expect(hierarchy_index.ancestors("Widget", singleton: true).map(&:name_or_nil))
      .to eq(["::Widget", "::Base", "Object", "BasicObject", "Class", "Module", "Object", "Kernel", "BasicObject"])
  end

  # A name the workspace never declared is neither a class nor a module,
  # so there is no tail that would be true of it. Answering with the class
  # one would say `Class`'s methods are available on something we cannot
  # even confirm is a class.
  it "appends no tail to a name the workspace does not declare" do
    index("class Widget\nend\n")

    expect(hierarchy_index.ancestors("NeverDeclared", singleton: true).map(&:name_or_nil)).to eq(["NeverDeclared"])
  end

  # An unresolvable parent leaves the method set unbounded, so claiming
  # the chain ends in Class would say it is fully accounted for when its
  # middle is not -- the same reason the instance side omits its tail
  # there.
  it "appends no tail when the superclass is an expression" do
    index("class Widget < Struct.new(:a)\nend\n")

    expect(hierarchy_index.ancestors("Widget", singleton: true).map(&:name_or_nil)).to eq(["::Widget", nil])
  end
end
