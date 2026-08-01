# frozen_string_literal: true

# The two decisions in PrefixCompletion that no end-to-end fixture can
# distinguish, because neither changes the answer -- only what the answer
# costs to produce, and what shape it leaves the wire in (0.2.0).
RSpec.describe Ovallsp::Semantic::PrefixCompletion do
  let(:scope) { Ovallsp::LocalInferencer::Scope.new(locals: {}, self_type: self_type) }
  let(:query_service) do
    instance_double(Ovallsp::Semantic::QueryService, scope_at: scope, members_of: [])
  end
  let(:workspace_index) { instance_double(Ovallsp::WorkspaceIndex, prefix_search: []) }
  let(:document) { Ovallsp::TextDocument.new(uri: "file:///a.rb", text: "", version: 1, language_id: "ruby") }

  subject(:completion) do
    described_class.new(query_service: query_service, workspace_index: workspace_index)
  end

  def complete(prefix)
    completion.items(document: document, position: { line: 0, character: 0 }, prefix: prefix)
  end

  context "at the top level of a file, where self has no useful type" do
    let(:self_type) { nil }

    # `members_of` answers empty for a nil receiver, so skipping it cannot
    # change the result -- which is exactly why the saving is invisible to
    # every other spec. It runs on the request path, holding the index
    # lock, on every keystroke.
    it "does not ask for the members of a receiver it does not have" do
      complete("art")

      expect(query_service).not_to have_received(:members_of)
        .with(nil, any_args)
    end
  end

  context "inside a class" do
    let(:self_type) { Ovallsp::Types::Nominal.new(name: "Article") }

    it "asks for the members of that class" do
      complete("art")

      expect(query_service).to have_received(:members_of)
        .with(Ovallsp::Types::Nominal.new(name: "Article"), prefix: "art")
    end

    # The group index is how the ranking is computed; `sortText` is how it
    # is communicated. Leaving the raw key on the item ships an unknown
    # field to every editor and invites someone to read it as the contract.
    it "never leaks the internal ranking key onto an item" do
      allow(query_service).to receive(:members_of).and_return(
        [Ovallsp::Semantic::Member.new(name: "article_body", origin: :source,
                                       conditional: false, visibility: :public, detail: nil)]
      )

      items = complete("art").items

      expect(items).not_to be_empty
      expect(items.flat_map(&:keys)).not_to include(:__group)
    end
  end
end
