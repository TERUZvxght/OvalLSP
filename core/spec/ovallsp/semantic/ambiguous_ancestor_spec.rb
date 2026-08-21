# frozen_string_literal: true

# `include Helpers` inside `Rackish::Request` resolved to `Aaa::Helpers`
# -- a module from a namespace the file never mentions -- because
# `AncestorFact` carries the target as written, `resolve_type_name`
# resolves a bare name by picking the first ordered candidate, and Ruby's
# constant lookup is lexical.
#
# The chain then still reaches BasicObject and every entry resolves, so
# `closed_nominal?` calls it closed and reports the class's own methods
# missing. That is 12 of the 54 false `unknown-method` findings measured
# over real gem source, and the corpus is full of modules named
# `Helpers`, `Base`, `Error` and `Node`.
#
# Found by an external review reading `AncestorFact`'s shape against
# Ruby's semantics; reproduced here before fixing. The briefing's own
# earlier reproduction was a harness error and is retracted -- neither an
# adjacent nor a nested module reproduces this on its own. Ambiguity is
# what does.
RSpec.describe "Ovallsp::Semantic::HierarchyIndex and an ambiguous ancestor name" do
  def build(sources)
    index = Ovallsp::WorkspaceIndex.new
    hierarchy = build_analysis_stack(workspace_index: index).hierarchy_index
    sources.each do |uri, text|
      document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      index.replace_file(summary)
      hierarchy.replace_file(summary)
    end
    [index, hierarchy]
  end

  let(:own) do
    <<~RUBY_SRC
      module Rackish
        class Request
          module Helpers
            def request_method; end
          end
          include Helpers
        end
      end
    RUBY_SRC
  end

  let(:stranger) do
    <<~RUBY_SRC
      module Aaa
        module Helpers
          def someone_elses_method; end
        end
      end
    RUBY_SRC
  end

  it "does not put a stranger's module in the chain" do
    _index, hierarchy = build("file:///aaa.rb" => stranger, "file:///rackish.rb" => own)

    names = hierarchy.ancestors("Rackish::Request", singleton: false).map(&:name_or_nil)

    expect(names).not_to include("::Aaa::Helpers")
  end

  # **This stopped being the ambiguous case in 0.2.12.** The refusal was
  # a stand-in for a lookup this index could not do: `AncestorFact` did
  # not carry `Module.nesting`, so `include Helpers` inside
  # `Rackish::Request` could only be *picked* between two `Helpers`. It
  # carries it now (`024.81`), and Ruby's lexical rule decides -- so the
  # right module is in the chain and the chain is complete.
  it "resolves the nested module rather than reporting the chain incomplete" do
    _index, hierarchy = build("file:///aaa.rb" => stranger, "file:///rackish.rb" => own)

    names = hierarchy.ancestors("Rackish::Request", singleton: false).map(&:name_or_nil)

    expect(names).to include("::Rackish::Request::Helpers")
    expect(names).not_to include(nil)
  end

  # And the refusal is still there for the case nesting cannot decide:
  # a bare name no enclosing frame declares, claimed by two strangers.
  # Dropping it silently would leave `closed_nominal?` reporting the same
  # methods missing, for a new reason.
  it "reports the chain as incomplete when no nesting frame can decide" do
    _index, hierarchy = build(
      "file:///aaa.rb" => "module Aaa\n  module Loose; end\nend\n",
      "file:///bbb.rb" => "module Bbb\n  module Loose; end\nend\n",
      "file:///consumer.rb" => "class Consumer\n  include Loose\nend\n"
    )

    expect(hierarchy.ancestors("Consumer", singleton: false).map(&:name_or_nil)).to include(nil)
  end

  # The control: with no competing name, the correct module still
  # resolves. Without this, "resolve nothing when in doubt" would satisfy
  # both examples above and break every ordinary include.
  it "still resolves an unambiguous include" do
    _index, hierarchy = build("file:///rackish.rb" => own)

    names = hierarchy.ancestors("Rackish::Request", singleton: false).map(&:name_or_nil)

    expect(names).to include("::Rackish::Request::Helpers")
  end
end
