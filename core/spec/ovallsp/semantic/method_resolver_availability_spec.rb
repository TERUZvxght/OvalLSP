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
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }
  subject(:resolver) do
    Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
  end

  def index(source, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
  end

  # `signatures:` defaults to the loaded environment here because that is
  # what the server passes; the one example about its absence passes nil
  # explicitly, so the difference is visible where it matters rather than
  # hidden in a helper.
  def availability_of(name, receiver: Ovallsp::Types::Nominal.new(name: "Widget"), signatures: self.signatures)
    resolver.availability(receiver_type: receiver, name: name, signatures: signatures)
  end

  it "is present when the workspace declares the method" do
    index("class Widget\n  def build; end\nend\n")

    expect(availability_of("build")).to be_present
  end

  # Step 1 shipped this asserting `unknown`, because nothing produced
  # `absent` yet -- absence was still to be earned. Step 3 is what earns
  # it: with a signature environment accounting for the chain, a name
  # that is not among its members is genuinely not there.
  it "is absent once the whole chain is accounted for" do
    index("class Widget\n  def build; end\nend\n")

    expect(availability_of("definitely_not_here")).to be_absent
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

  # **Step 2 of C2**: the reasons `Diagnostics::Engine#closed_nominal?`
  # kept for itself, moved to where the enumeration happens. Four of its
  # six are answerable here today; the two that need the signature
  # environment stay in the engine until it is passed one.
  #
  # Each one used to be a `return false` the engine had learned to make,
  # one review round at a time. As a reason on the resolver's answer it
  # is stated once and every reader gets it.
  describe "the reasons an enumeration was incomplete" do
    it "cannot account for a chain that does not reach BasicObject" do
      index("class Widget < Unfindable\nend\n")

      expect(availability_of("anything").reason).to eq(:ancestor_not_identified)
    end

    # A class nothing declares is its own unidentified link -- the chain
    # holds the receiver and nothing else, and that entry has no kind.
    # This example was written expecting a separate `:receiver_not_declared`,
    # which turned out to describe a state that cannot occur: a chain is
    # never empty. The engine's equivalent guard could not fire either,
    # and is not carried over.
    it "cannot account for a class nothing declares at all" do
      expect(availability_of("anything", receiver: Ovallsp::Types::Nominal.new(name: "NeverSeen")).reason)
        .to eq(:ancestor_not_identified)
    end

    # A surface that answers at call time cannot be enumerated, so
    # nothing about it supports a claim of absence.
    it "cannot account for a class that declares method_missing" do
      index("class Widget\n  def method_missing(name, *args); end\nend\n")

      expect(availability_of("anything").reason).to eq(:responds_at_call_time)
    end

    # And the other direction: a surface whose members were written by a
    # macro this parser cannot read.
    it "cannot account for a class whose body runs a macro it cannot read" do
      index("class Widget\n  attr_atomic :value\nend\n")

      expect(availability_of("value").reason).to eq(:surface_open)
    end

    # The control: a chain this resolver can account for entirely carries
    # no reason at all, because there is nothing it could not see.
    it "carries no reason when it could account for the whole chain" do
      index("class Widget\n  def build; end\nend\n")

      expect(availability_of("definitely_not_here").reason).to be_nil
    end
  end

  # **Step 3**: the last two reasons, and the first `absent` this query
  # can produce. Both needed the signature environment, to say whether an
  # ancestor is one RBS declares -- an ancestor nothing in the workspace
  # and nothing in RBS accounts for means the receiver's real method set
  # could include anything.
  describe "with the signature environment" do
    it "can account for a chain whose links RBS declares, and says the method is absent" do
      index("class Widget\n  def build; end\nend\n")

      expect(availability_of("definitely_not_here")).to be_absent
    end

    # An `include` of something nobody declares: the chain still reaches
    # BasicObject, so it is not the *identification* that fails -- it is
    # that nothing can say what that link contributes.
    it "still cannot account for an ancestor neither the workspace nor RBS declares" do
      index("class Widget\n  include Sidekiq::Worker\n  def build; end\nend\n")

      availability = availability_of("definitely_not_here")

      expect(availability).to be_unknown
      expect(availability.reason).to eq(:ancestor_not_declared_anywhere)
    end

    # The singleton half, which 0.2.6 spent a round learning: `include`
    # puts a module on the *instance* chain, and `included`/`extended`
    # hooks are how a module adds class methods -- so a class-level
    # lookup depends on the instance chain being accounted for too.
    it "cannot account for a class-level lookup when the instance chain has an unaccounted link" do
      index("class Widget\n  include Sidekiq::Worker\nend\n")

      availability = resolver.availability(receiver_type: Ovallsp::Types::Nominal.new(name: "Widget"),
                                           name: "sidekiq_options", context: { singleton: true })

      expect(availability).to be_unknown
    end

    # And without a signature environment the query stays honest rather
    # than optimistic: nothing can be called absent when the thing that
    # would account for RBS is not there.
    it "answers unknown when it is given no signature environment at all" do
      index("class Widget\n  def build; end\nend\n")

      expect(availability_of("definitely_not_here", signatures: nil)).to be_unknown
    end
  end
end

