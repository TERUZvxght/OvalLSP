# frozen_string_literal: true

# `024.80`. An ancestor this index could not identify was expressed as an
# entry whose `name` is `nil` -- and `nil` is also the owner a *top-level*
# `def` is indexed under. So asking an unidentified ancestor for its
# members answered with every top-level method in the workspace, offered
# as completions on a class that has none of them.
#
# Two call sites guarded it by hand, each with `next if entry.name.nil?`,
# and each was added after the same bug was found in that reader. The
# durable answer is that an unresolved edge should not be *expressible*
# as an owner -- which is what this pins.
RSpec.describe Ovallsp::Semantic::AncestorEntry do
  let(:identified) do
    described_class.identified(name: "::Widget", kind: :class, origin: :superclass, location: nil)
  end
  let(:unidentified) { described_class.unidentified(origin: :superclass, location: nil) }

  it "answers a name for an ancestor it identified" do
    expect(identified).to be_identified
    expect(identified.name).to eq("::Widget")
  end

  # The point of the whole entry: there is no accessor that yields an
  # owner for an edge nobody resolved. A reader that forgets to ask
  # `#identified?` finds out here rather than by listing every top-level
  # method in the workspace as a class's members.
  it "refuses to answer a name for an ancestor it could not identify" do
    expect(unidentified).not_to be_identified
    expect { unidentified.name }.to raise_error(Ovallsp::Semantic::UnidentifiedAncestor, /could not be identified/)
  end

  # And it is still an entry: the chain has to *contain* it, because
  # omitting it makes the class look parentless and therefore fully
  # known, which is what made every Rails migration report its own DSL
  # calls as undefined methods.
  it "keeps its place in the chain, with the statement that introduced it" do
    entry = described_class.unidentified(origin: :include, location: { start: 1 })

    expect([entry.origin, entry.location]).to eq([:include, { start: 1 }])
  end
end
