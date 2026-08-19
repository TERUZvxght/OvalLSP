# frozen_string_literal: true

# `#resolve` answers a list, and an empty one means either "not there" or
# "I could not look" -- its second line is `return [] if types.empty?`.
# `#availability` is the same question answered in three states, and the
# default is **unknown**: something has to earn `absent`.
#
# That inversion is the whole of `037`'s C2. Today a caller assumes
# absence and subtracts the ways of not knowing it has heard about --
# 0.2.6 added four such subtractions, one per review round, each after a
# false report on working code. With the default the other way round, a
# way of not knowing that nobody has thought of yet produces silence
# rather than a wrong answer.
RSpec.describe "Ovallsp::Semantic::MethodResolver#availability" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  subject(:resolver) do
    Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
  end

  def index(source, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
  end

  def availability_of(name, receiver: Ovallsp::Types::Nominal.new(name: "Widget"))
    resolver.availability(receiver_type: receiver, name: name)
  end

  it "is present when the workspace declares the method" do
    index("class Widget\n  def build; end\nend\n")

    expect(availability_of("build")).to be_present
  end

  it "is unknown, not absent, for a method nothing declares" do
    index("class Widget\n  def build; end\nend\n")

    availability = availability_of("definitely_not_here")

    expect(availability).to be_unknown
    expect(availability).not_to be_absent
  end

  # The two the resolver can answer for itself. Everything else it cannot
  # see -- RBS, the Runtime Agent, a reopened core class -- is somebody
  # else's `unknown` to rule out, and until they do it stays unknown.
  it "says why: a receiver that is not a class at all" do
    expect(availability_of("anything", receiver: Ovallsp::Types::UNKNOWN).reason).to eq(:receiver_not_nominal)
  end

  it "says why: an ancestor it could not identify" do
    index("class Widget < Unfindable\n  def build; end\nend\n")

    expect(availability_of("definitely_not_here").reason).to eq(:ancestor_not_identified)
  end

  # And the resolver's own answer stays the resolver's: `#resolve` is
  # untouched, so nothing that reads it changes behaviour on the strength
  # of this alone.
  it "agrees with #resolve about what it did find" do
    index("class Widget\n  def build; end\nend\n")
    receiver = Ovallsp::Types::Nominal.new(name: "Widget")

    expect(availability_of("build").candidates)
      .to eq(resolver.resolve(receiver_type: receiver, name: "build"))
  end
end
