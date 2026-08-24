# frozen_string_literal: true

RSpec.describe Ovallsp::Semantic::MethodSummaryStore do
  subject(:store) { described_class.new }

  def sym(name) = Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::X", name: name, discriminator: nil)

  def summary(name, dependencies: [])
    Ovallsp::Semantic::MethodSummary.new(
      symbol_id: sym(name), return_type: Ovallsp::Types::UNKNOWN,
      dependencies: dependencies, confidence: :high, generation: 0, status: :complete
    )
  end

  it "starts empty and returns nil for an unknown symbol" do
    expect(store.fetch(sym("nope"))).to be_nil
  end

  it "stores and fetches a summary by symbol_id" do
    store.replace(summary("a"))

    expect(store.fetch(sym("a")).symbol_id).to eq(sym("a"))
  end

  it "bumps generation on every #replace and every #invalidate that actually removes something" do
    expect(store.generation).to eq(0)

    store.replace(summary("a"))
    expect(store.generation).to eq(1)

    store.invalidate([sym("a")])
    expect(store.generation).to eq(2)
  end

  it "does not bump generation when #invalidate removes nothing" do
    store.invalidate([sym("nope")])

    expect(store.generation).to eq(0)
  end

  it "transitively invalidates every summary that depended (directly or indirectly) on an invalidated one" do
    store.replace(summary("c"))
    store.replace(summary("b", dependencies: [sym("c")]))
    store.replace(summary("a", dependencies: [sym("b")]))

    removed = store.invalidate([sym("c")])

    expect(removed).to contain_exactly(sym("c"), sym("b"), sym("a"))
    expect(store.fetch(sym("a"))).to be_nil
    expect(store.fetch(sym("b"))).to be_nil
    expect(store.fetch(sym("c"))).to be_nil
  end

  it "does not invalidate an unrelated summary that shares no dependency edge" do
    store.replace(summary("c"))
    store.replace(summary("b", dependencies: [sym("c")]))
    store.replace(summary("unrelated"))

    store.invalidate([sym("c")])

    expect(store.fetch(sym("unrelated"))).not_to be_nil
  end

  it "replaces stale dependency edges when a summary is recomputed with different dependencies" do
    store.replace(summary("a", dependencies: [sym("old_dep")]))
    store.replace(summary("a", dependencies: [sym("new_dep")])) # recomputed -- no longer depends on old_dep

    removed = store.invalidate([sym("old_dep")])

    expect(removed).to contain_exactly(sym("old_dep")) # "a" is NOT pulled in -- the stale edge is gone
    expect(store.fetch(sym("a"))).not_to be_nil
  end
end
