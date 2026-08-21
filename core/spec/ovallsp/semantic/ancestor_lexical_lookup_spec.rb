# frozen_string_literal: true

# `024.81`. `AncestorFact` records the ancestor's constant *as written*
# and nothing about where it was written. Ruby's constant lookup is
# lexical, so the one thing needed to identify the ancestor was the one
# thing not recorded -- and the index, rather than picking wrongly,
# refused: a class whose ancestor name is claimed by any other namespace
# lost that module's members from completion, hover and go to definition
# as well as from the check.
#
#   $ ruby -e '
#   module Aaa; module Helpers; def unrelated; end; end; end
#   module Rackish
#     class Request
#       module Helpers; def request_method; :get; end; end
#       include Helpers
#     end
#   end
#   p Rackish::Request.new.request_method
#   '
#   # => :get
#   # ruby 3.4.10
#
# The nested `Helpers` is inside the includer, so Ruby's lookup makes it
# unambiguously right.
RSpec.describe "Ovallsp::Semantic::HierarchyIndex and an ancestor named ambiguously" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }

  def index(text, uri:)
    summary = Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    )
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
  end

  before do
    index(<<~RUBY_SRC, uri: "file:///rackish.rb")
      module Rackish
        class Request
          module Helpers
            def request_method; :get; end
          end
          include Helpers
        end
      end
    RUBY_SRC
  end

  it "resolves the nested module Ruby resolves, with a same-named module elsewhere" do
    index("module Aaa\n  module Helpers\n    def unrelated; end\n  end\nend\n", uri: "file:///aaa.rb")

    names = hierarchy_index.ancestors("Rackish::Request").map(&:name_or_nil)

    expect(names).to include("::Rackish::Request::Helpers")
    expect(names).not_to include(nil)
  end

  # The control: with nothing lexically enclosing to prefer, an ambiguous
  # name is still refused rather than picked. An implementation that went
  # back to picking the first candidate would pass the example above and
  # fail this one.
  it "still refuses a name that no nesting frame declares" do
    index("module Aaa\n  module Loose; end\nend\n", uri: "file:///aaa.rb")
    index("module Bbb\n  module Loose; end\nend\n", uri: "file:///bbb.rb")
    index("class Consumer\n  include Loose\nend\n", uri: "file:///consumer.rb")

    expect(hierarchy_index.ancestors("Consumer").map(&:name_or_nil)).to include(nil)
  end
end
