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

  def argument_counts(body)
    engine.analyze(document: index(body), semantic_context: context, mode: :standard)
          .select { |finding| finding.code == "argument-count" }
          .map(&:message)
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

  # An unresolvable parent leaves the method set unbounded, so claiming
  # the chain ends in Class would say it is fully accounted for when its
  # middle is not -- the same reason the instance side omits its tail
  # there.
  it "appends no tail when the superclass is an expression" do
    index("class Widget < Struct.new(:a)\nend\n")

    expect(hierarchy_index.ancestors("Widget", singleton: true).map(&:name)).to eq(["::Widget", nil])
  end
end
