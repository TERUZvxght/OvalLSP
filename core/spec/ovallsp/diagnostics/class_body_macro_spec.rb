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
# Measured before the fix, with `scripts/corpus_diagnostics.rb`: 49 of
# the 62 `unknown-method` findings over this repository's own `core/lib`
# were this, and 209 of 776 over ActiveSupport 8.1.3. It was the largest
# single source of wrong reports the engine produced, on the most
# ordinary Ruby there is (024.23).
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
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) do
    Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
  end
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) do
    Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: @workspace_root) }
  end
  let(:local_inferencer) do
    Ovallsp::LocalInferencer.new(
      model_registry: model_registry, method_resolver: method_resolver, signatures: signatures,
      method_analyzer: Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver,
        summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
    )
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

    expect(hierarchy_index.ancestors("Derived", singleton: true).map(&:name).last(5))
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

  it "does not report `new` on a constant receiver" do
    expect(unknown_methods("class Widget\nend\nWidget.new\n")).to be_empty
  end

  # The point of the check is to still catch what is genuinely absent.
  # Without this, "report nothing on a singleton receiver" would pass
  # every example above.
  it "still reports a singleton call that nothing declares" do
    expect(unknown_methods("class Widget\n  definitely_not_a_macro :a\nend\n")).to eq(["definitely_not_a_macro"])
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

  # An ordinary block does *not* change self, so a class body's block
  # still resolves against the class. Without this, "treat every block as
  # an instance" would pass the two examples above.
  it "still reads an ordinary block in a class body as the class" do
    source = "class Widget\n  [1, 2].each { definitely_not_a_macro }\nend\n"

    expect(unknown_methods(source)).to eq(["definitely_not_a_macro"])
  end

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

    expect(hierarchy_index.ancestors("Widget", singleton: true).map(&:name))
      .to eq(["::Widget", "Class", "Module", "Object", "Kernel", "BasicObject"])
    expect(hierarchy_index.ancestors("Helper", singleton: true).map(&:name))
      .to eq(["::Helper", "Module", "Object", "Kernel", "BasicObject"])
  end

  # The tail belongs at the end of the chain, once -- not at each step of
  # it. Appending it per class would put Class/Module *between* a child
  # and its parent, so a parent's own singleton method would rank below
  # `Module#name` and resolve to the wrong declaration.
  it "appends the tail once, after the whole superclass chain" do
    index("class Base\nend\nclass Widget < Base\nend\n")

    expect(hierarchy_index.ancestors("Widget", singleton: true).map(&:name))
      .to eq(["::Widget", "::Base", "Class", "Module", "Object", "Kernel", "BasicObject"])
  end

  # A name the workspace never declared is neither a class nor a module,
  # so there is no tail that would be true of it. Answering with the class
  # one would say `Class`'s methods are available on something we cannot
  # even confirm is a class.
  it "appends no tail to a name the workspace does not declare" do
    index("class Widget\nend\n")

    expect(hierarchy_index.ancestors("NeverDeclared", singleton: true).map(&:name)).to eq(["NeverDeclared"])
  end

  # An unresolvable parent leaves the method set unbounded, so claiming
  # the chain ends in Class would say it is fully accounted for when its
  # middle is not -- the same reason the instance side omits its tail
  # there.
  it "appends no tail when the superclass is an expression" do
    index("class Widget < Struct.new(:a)\nend\n")

    expect(hierarchy_index.ancestors("Widget", singleton: true).map(&:name)).to eq(["::Widget", nil])
  end
end
