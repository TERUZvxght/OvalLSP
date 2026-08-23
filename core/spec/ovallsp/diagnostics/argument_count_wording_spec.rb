# frozen_string_literal: true

# `024.133`. A positional argument passed to a keyword-only method was
# reported as ``takes 0 arguments, but 1 given`` — beside a `def` that
# plainly takes several. The count is of *positional* parameters, and
# saying so is the whole fix.
#
# Ruby's own message makes the same count and disambiguates it with a
# clause, taken from the interpreter rather than from memory:
#
#     def kwargs(name:, size: 1, **rest) = [name, size, rest]
#     kwargs("positional")
#     # => wrong number of arguments (given 1, expected 0; required keyword: name)
#
# So "0" is right and "arguments" is what was wrong.
RSpec.describe "Ovallsp::Diagnostics::Engine argument-count wording" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }
  let(:stack) do
    build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures)
  end

  def messages(source)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
      method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
      model_registry: model_registry, route_registry: Ovallsp::Routes::RouteRegistry.new,
      signatures: signatures, generation: 1
    )
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
                                .select { |f| f.code == "argument-count" }.map(&:message)
  end

  it "says positional when the method's parameters are keywords" do
    source = <<~RUBY
      class Widget
        def kwargs(name:, size: 1, **rest)
          [name, size, rest]
        end

        def call_it
          kwargs("positional")
        end
      end
    RUBY

    expect(messages(source)).to contain_exactly(
      "`kwargs` takes 0 positional arguments, but 1 given"
    )
  end

  # The distinguishing half: an ordinary method must not gain the word,
  # or the fix would be "always say positional", which is a different
  # and equally wrong message.
  it "does not say positional when the method takes positional parameters" do
    source = <<~RUBY
      class Widget
        def two(a, b)
          [a, b]
        end

        def call_it
          two(1, 2, 3)
        end
      end
    RUBY

    expect(messages(source)).to contain_exactly(
      "`two` takes 2 arguments, but 3 given"
    )
  end
end
