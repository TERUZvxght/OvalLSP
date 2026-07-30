# frozen_string_literal: true

# `WorkspaceIndex#method_symbol_ids` is asked with a name that arrives
# qualified or bare depending on where it came from (0.1.11).
#
# `ParserService` indexes a declaration's owner qualified (`::Object`),
# while `HierarchyIndex::DEFAULT_OBJECT_CHAIN` names its entries bare
# (`Object`). Every caller that walks an ancestor chain and then asks this
# hands over whichever form it happened to get, so an exact string
# comparison answered "nothing" for half of them -- and the visible
# consequence is a workspace that reopens `class Object` with
# `method_missing` still getting a false `unknown-method` on every closed
# receiver, which is the report this release exists to stop making.
RSpec.describe "Ovallsp::WorkspaceIndex#method_symbol_ids owner qualification (0.1.11)" do
  subject(:workspace_index) { Ovallsp::WorkspaceIndex.new }

  before do
    document = Ovallsp::TextDocument.new(
      uri: "file:///core_ext.rb", text: "class Object\n  def method_missing(name, *args)\n  end\nend\n",
      version: 1, language_id: "ruby"
    )
    workspace_index.replace_file(Ovallsp::ParserService.new.summarize(document))
  end

  it "answers for the qualified form the index stores" do
    names = workspace_index.method_symbol_ids("::Object", kind: :instance_method).map(&:name)

    expect(names).to include("method_missing")
  end

  it "answers the same for the bare form an ancestor chain hands over" do
    names = workspace_index.method_symbol_ids("Object", kind: :instance_method).map(&:name)

    expect(names).to include("method_missing")
  end

  # Tolerating a missing prefix must not turn into matching by simple
  # name: `Admin::Object` is a different class from `::Object`.
  it "does not answer for a different class with the same simple name" do
    names = workspace_index.method_symbol_ids("Admin::Object", kind: :instance_method).map(&:name)

    expect(names).to be_empty
  end
end
