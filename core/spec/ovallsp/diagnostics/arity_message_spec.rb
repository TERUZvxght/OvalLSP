# frozen_string_literal: true

# **The noun followed the upper bound of the range rather than the range.**
#
# `#expected_arity` wrote `"argument#{maximum == 1 ? '' : 's'}"`, so a
# method accepting none or one, called with three, was reported as one
# that "takes 0..1 argument". The count printed beside it is a range and
# the sentence reads as though it were a single value. `024.310`.
#
# Two places agree about this string and only one of them formats it:
# `Server#diagnostic_maximum` parses the arity back out of the message
# with `/takes (?:\d+\.\.)?(\d+)(?: positional)? argument/`. That pattern
# has no word boundary after `argument`, so it survives the plural
# either way — but it is the reason this file asserts the exact
# sentence rather than a fragment of it, and the reason the surplus
# action's own example is here as the control.
RSpec.describe "the sentence an argument-count report is written in" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, signatures: signatures) }
  let(:signatures) { AnalysisStackHelper.shared_signatures }

  def index(text)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    document
  end

  def messages(text)
    document = index(text)
    context = stack.semantic_context(route_registry: Ovallsp::Routes::RouteRegistry.new, generation: 1)
    engine.analyze(document: document, semantic_context: context, mode: :standard)
          .select { |finding| finding.code == "argument-count" }
          .map(&:message)
  end

  # The subject. `def opt(a = 1)` accepts none or one, so the count is a
  # range and the noun has to follow the range.
  it "pluralises a range of accepted counts" do
    expect(messages(<<~RUBY)).to eq(["`opt` takes 0..1 arguments, but 3 given"])
      class Probe
        def opt(a = 1); end

        def go
          Probe.new.opt(1, 2, 3)
        end
      end
    RUBY
  end

  # The control, and the reason the fix is not "always plural": a method
  # that takes exactly one really does take one argument, and this is the
  # sentence `forward_alias_spec.rb` already pins elsewhere.
  it "keeps the singular where the count is exactly one" do
    expect(messages(<<~RUBY)).to eq(["`one` takes 1 argument, but 3 given"])
      class Probe
        def one(a); end

        def go
          Probe.new.one(1, 2, 3)
        end
      end
    RUBY
  end

  # And the other end of it: a method taking none is plural, which the
  # old rule got right by accident — `maximum == 1` is false at zero.
  it "keeps the plural at zero" do
    expect(messages(<<~RUBY)).to eq(["`none` takes 0 arguments, but 2 given"])
      class Probe
        def none; end

        def go
          Probe.new.none(1, 2)
        end
      end
    RUBY
  end

  # The other reader of this string. `Server#diagnostic_maximum` parses
  # the upper bound back out of the message to decide how many arguments
  # the surplus quick fix removes, so a change to the sentence that broke
  # the pattern would break the action silently.
  it "is still parsed by the reader that recovers the maximum from it" do
    pattern = /takes (?:\d+\.\.)?(\d+)(?: positional)? argument/

    expect(messages(<<~RUBY).first&.match(pattern)&.captures).to eq(["1"])
      class Probe
        def opt(a = 1); end

        def go
          Probe.new.opt(1, 2, 3)
        end
      end
    RUBY
  end
end
