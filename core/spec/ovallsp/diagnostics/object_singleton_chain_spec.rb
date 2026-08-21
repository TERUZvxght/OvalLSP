# frozen_string_literal: true

# `024.26`. A workspace `def self.foo` written on `Object` is reachable
# from every class in Ruby, and from none here:
#
#   $ ruby -e '
#   class Object; def self.foo; :ok; end; end
#   class Widget; end
#   p Widget.foo
#   p Widget.singleton_class.ancestors.first(3)
#   '
#   # => :ok
#   # => [#<Class:Widget>, #<Class:Object>, #<Class:BasicObject>]
#   # ruby 3.4.10
#
# The chain a class's *singleton* side ends in started at `Class`, so the
# two links Ruby puts before it -- the singleton classes of `Object` and
# `BasicObject` -- had nowhere to be. An `AncestorEntry` names a *type*,
# and "the singleton class of that type" was not expressible.
RSpec.describe "Ovallsp::Diagnostics::Engine and a class method on Object" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }

  def index(text, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    document
  end

  def unknown_methods(document)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
      method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
      model_registry: model_registry, route_registry: Ovallsp::Routes::RouteRegistry.new,
      signatures: signatures, generation: 1
    )
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
                                .select { |f| f.code == "unknown-method" }
                                .map { |f| f.message[/named `(.+)`/, 1] }
  end

  before do
    index("class Object\n  def self.foo; :ok; end\nend\n", uri: "file:///core_ext.rb")
    index("class Widget\nend\n", uri: "file:///widget.rb")
  end

  it "says nothing about a class-level call every class inherits" do
    expect(unknown_methods(index("Widget.foo\n", uri: "file:///caller.rb"))).to be_empty
  end

  # The control, and the reason this is not "stop reporting on classes":
  # a name `Object` does *not* declare is still reported, so the chain
  # gained a link rather than losing its edge.
  it "still reports a class-level call nothing declares" do
    expect(unknown_methods(index("Widget.nope\n", uri: "file:///caller.rb"))).to eq(["nope"])
  end

  # And the instance side is untouched: `def self.foo` on Object is not
  # an instance method of anything.
  it "still reports the same name called on an instance" do
    expect(unknown_methods(index("Widget.new.foo\n", uri: "file:///caller.rb"))).to eq(["foo"])
  end
end
