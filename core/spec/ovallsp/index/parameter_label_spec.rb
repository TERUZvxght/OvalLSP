# frozen_string_literal: true

# `024.89`. `Index::Parameter#label` spells a parameter the way the
# source declares it. Signature help and hover both render from it, and
# both used to join bare names -- so
# `def simple(a, b = 2, *rest, key:, opt: 1, **others, &blk)` presented
# as `simple(a, b, rest, key, opt, others, blk)`, telling the reader
# `key` was the fourth positional argument when it is a required
# keyword.
#
# The kinds are Ruby's, one for one, taken from the interpreter:
#
#   $ ruby -e 'def simple(a, b = 2, *rest, key:, opt: 1, **others, &blk); end
#              p method(:simple).parameters'
#   # => [[:req, :a], [:opt, :b], [:rest, :rest], [:keyreq, :key],
#   #     [:key, :opt], [:keyrest, :others], [:block, :blk]]
#   # ruby 3.4.10
RSpec.describe Ovallsp::Index::Parameter do
  def parameters_for(source)
    document = Ovallsp::TextDocument.new(uri: "file:///p.rb", text: source, version: 1, language_id: "ruby")
    Ovallsp::ParserService.new.summarize(document)
                          .declarations.find { |d| d.symbol_id.kind == :instance_method }
                          .parameters
  end

  it "renders every kind the way the source wrote it" do
    source = "class S\n  def simple(a, b = 2, *rest, key:, opt: 1, **others, &blk)\n  end\nend\n"

    expect(parameters_for(source).map(&:label))
      .to eq(["a", "b = 2", "*rest", "key:", "opt: 1", "**others", "&blk"])
  end

  # **A buffer mid-edit, which is the state an editor spends most of its
  # time in.** Prism is error-tolerant and gives `a = ` a `MissingNode`
  # whose `slice` is the `=` itself, so `default_source` was recorded as
  # `"="` -- latent since Task 016 and invisible until something
  # rendered it, at which point the label would have read `a = =`.
  #
  # Both halves are asserted: the recorded value, and what it renders
  # as. Asserting only the label would pass on a parser that still
  # recorded `"="` and a renderer that happened to hide it.
  it "records no default for one that is still being typed" do
    parameter = parameters_for("class H\n  def half(a = )\n  end\nend\n").first

    expect(parameter).to have_attributes(name: "a", kind: :optional, default_source: nil)
  end

  it "says the default is unreadable rather than inventing one" do
    expect(parameters_for("class H\n  def half(a = )\n  end\nend\n").map(&:label)).to eq(["a = ..."])
  end

  # The control for the pair above: a default that *is* readable must
  # still be rendered, or "records no default" would be satisfied by a
  # parser that recorded none of them.
  it "still records a default it can read" do
    parameter = parameters_for("class H\n  def half(a = 41 + 1)\n  end\nend\n").first

    expect(parameter).to have_attributes(default_source: "41 + 1", label: "a = 41 + 1")
  end
end
