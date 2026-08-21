# frozen_string_literal: true

# `024.118`. 0.2.10 gave the publish funnel a `buffer_id` so an answer
# could not be attributed to a buffer it was not computed from. 0.2.11's
# `drive` round found the reopen still dropped one layer earlier: the
# index compares `document_version` integers across buffers, and its own
# comment asserted the premise the funnel rejects -- "an LSP client
# always sends increasing versions per document".
#
# Two places compared a version across buffers and one of them was fixed.
#
# Ruby's own numbering has nothing to say here; what decides it is that
# two buffers of one uri are two documents, and "version 1" of the second
# is not older than "version 20" of the first. It is not comparable at
# all.
RSpec.describe "Ovallsp::WorkspaceIndex and two buffers of one uri" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:uri) { "file:///a.rb" }

  def summarize(text, version:)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
    Ovallsp::ParserService.new.summarize(document)
  end

  def method_names
    workspace_index.method_symbol_ids("First", kind: :instance_method).map(&:name) +
      workspace_index.method_symbol_ids("Second", kind: :instance_method).map(&:name)
  end

  it "takes a new buffer's first version over the old buffer's twentieth" do
    workspace_index.replace_file(summarize("class First\n  def from_first; end\nend\n", version: 20))
    expect(method_names).to eq(["from_first"])

    workspace_index.replace_file(summarize("class Second\n  def from_second; end\nend\n", version: 1))

    expect(method_names).to eq(["from_second"])
  end

  # The control, and the rule this must not undo: *within* one buffer, an
  # older version still loses. Without it an implementation that simply
  # stopped comparing versions would pass the example above.
  it "still refuses an older version of the same buffer" do
    document = Ovallsp::TextDocument.new(uri: uri, text: "class First\n  def from_first; end\nend\n",
                                         version: 20, language_id: "ruby")
    older = document.with_full_change(text: "class Second\n  def from_second; end\nend\n", version: 3)

    workspace_index.replace_file(Ovallsp::ParserService.new.summarize(document))
    workspace_index.replace_file(Ovallsp::ParserService.new.summarize(older))

    expect(method_names).to eq(["from_first"])
  end
end
