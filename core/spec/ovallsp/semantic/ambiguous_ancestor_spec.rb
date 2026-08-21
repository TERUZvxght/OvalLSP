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

  # The chain must also stop claiming to be complete. Dropping the wrong
  # entry without saying anything would leave `closed_nominal?` reporting
  # the same methods missing, for a new reason.
  it "reports the chain as incomplete when an ancestor name is ambiguous" do
    _index, hierarchy = build("file:///aaa.rb" => stranger, "file:///rackish.rb" => own)

    expect(hierarchy.ancestors("Rackish::Request", singleton: false).map(&:name_or_nil)).to include(nil)
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
