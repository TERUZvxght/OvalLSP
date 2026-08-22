# frozen_string_literal: true

# 0.1.14 gave a class's singleton chain its real tail -- `Class`,
# `Module`, `Object`, `Kernel`, `BasicObject` -- and then looked those
# entries up for *singleton* methods. That is backwards. Ruby puts them
# in the chain because the class object is an **instance** of them:
#
#   W.singleton_class.ancestors
#   # => [#<Class:W>, #<Class:Object>, #<Class:BasicObject>,
#   #     Class, Module, Object, Kernel, BasicObject]
#
# so what a class-level call reaches on those five is their *instance*
# methods. Getting the kind wrong is not academic -- it produced a wrong
# report, silenced a true one, and left the release's headline claim only
# accidentally true:
#
#   * `class Object; def patched; end; end` then `patched` in a class body
#     was reported, on code Ruby runs. Object core-ext is idiomatic Rails.
#   * `class Class; def self.only_on_class_object; end; end` then that
#     name in a class body was *not* reported, though Ruby raises
#     NameError.
#   * a workspace-declared `class Module; def my_macro; end; end` was
#     still reported -- 0.1.14 only appeared to fix class-body macros
#     because RBS declares `Module#private` and RBS's own builder models
#     this correctly.
RSpec.describe "a class object is an instance of Class (024.23 follow-up)" do
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
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: @workspace_root) } }

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

  # Ruby runs this. `patched_everywhere` is an instance method of Object,
  # and a class object is an Object.
  it "reaches an instance method the workspace adds to Object" do
    index("class Object\n  def patched_everywhere; end\nend\n", uri: "file:///core_ext.rb")

    expect(unknown_methods("class UsesPatch\n  patched_everywhere\nend\n")).to be_empty
  end

  # The same for Module, which is where a hand-written class-body macro
  # is defined. This is the case 0.1.14 claimed to fix and did not.
  it "reaches an instance method the workspace adds to Module" do
    index("class Module\n  def my_macro(name); end\nend\n", uri: "file:///core_ext.rb")

    expect(unknown_methods("class UsesMacro\n  my_macro :a\nend\n")).to be_empty
  end

  # Ruby raises NameError: `def self.x` on Class is a method of the Class
  # *object*, not something an ordinary class inherits.
  it "does not reach a singleton method the workspace adds to Class" do
    index("class Class\n  def self.only_on_class_object; end\nend\n", uri: "file:///core_ext.rb")

    expect(unknown_methods("class Victim\n  Victim.only_on_class_object\nend\n")).to eq(["only_on_class_object"])
  end

  # **`024.110`, fixed in 0.2.12.** The engine declines to enumerate what
  # an unreadable macro might define, so it no longer reports the macro
  # itself -- two answers about one fact. 0.2.11 shipped this and rolled
  # it back the same release, because the reader took `Module`'s open
  # surface as evidence about every class inheriting from it;
  # `#open_surface?` ignores a synthesised link now, so the claim is about
  # this owner alone.
  it "says nothing about a class-level call in a body it could not read" do
    expect(unknown_methods("class Widget\n  definitely_not_a_macro :a\nend\n")).to be_empty
  end

  # A call on a *receiver* is not evidence about the receiver's own body,
  # so it is reported whatever `024.110` is eventually settled as.
  it "still reports an absent class method on a constant receiver" do
    expect(unknown_methods("class Widget\nend\nWidget.no_such_class_method\n")).to eq(["no_such_class_method"])
  end

  # `extend` and the tail both contribute instance methods, but for
  # different reasons, and the chain has to keep them apart from
  # `def self.` on the class itself.
  it "still reaches a singleton method the class declares itself" do
    expect(unknown_methods("class Widget\n  def self.build; end\n  build\nend\n")).to be_empty
  end
end
