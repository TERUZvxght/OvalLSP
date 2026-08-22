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
