# frozen_string_literal: true

# `024.237`, the half of it that is syntactic. `Seed = Struct.new(:seed,
# :used)` names its members right there in the call, and the parser
# recorded none of them -- so `Seed.new.` offered 51 items and not
# `seed`, and hover and go-to-definition had nothing to answer either.
#
# Asked of Ruby rather than assumed, including the forms that are not
# members:
#
#   $ ruby -e '
#   p Struct.new(:a, :b).instance_methods(false).sort
#   p Struct.new(:a, keyword_init: true).instance_methods(false).sort
#   p Struct.new("Named", :c).instance_methods(false).sort
#   p Data.define(:x, :y).instance_methods(false).sort
#   p Data.define.instance_methods(false).sort
#   '
#   # => [:a, :a=, :b, :b=]
#   # => [:a, :a=]
#   # => [:c, :c=]
#   # => [:x, :y]
#   # => []
#   # ruby 3.4.10
#
# So: symbol arguments only, a writer for `Struct` and none for `Data`.
#
# **The surface stays open.** `024.110`'s rule is that an enumeration
# carries its own completeness and a generated one cannot -- naming the
# class without opening it produced ``HeredocData has no method named
# `common_whitespace=` `` over real gem source. Recording the members is
# a pure addition on the other side of that line: it gives completion
# and hover something to say and asserts nothing new about what is
# absent.
RSpec.describe "Ovallsp::ParserService and a Struct or Data constant's members" do
  def generated(text, owner)
    Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: "file:///s.rb", text: text, version: 1, language_id: "ruby")
    ).declarations.select { |d| d.origin == :generated && d.symbol_id.owner == owner }
     .map { |d| d.symbol_id.name }.sort
  end

  def open_surfaces(text)
    Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: "file:///s.rb", text: text, version: 1, language_id: "ruby")
    ).open_surface_owners
  end

  it "records a reader and a writer for each Struct member" do
    expect(generated("Seed = Struct.new(:seed, :used)\n", "::Seed"))
      .to eq(%w[seed seed= used used=])
  end

  it "records a reader only for each Data member" do
    expect(generated("Point = Data.define(:x, :y)\n", "::Point")).to eq(%w[x y])
  end

  it "ignores a keyword argument and a leading string name" do
    expect(generated("A = Struct.new(:a, keyword_init: true)\n", "::A")).to eq(%w[a a=])
    expect(generated("B = Struct.new(\"Named\", :c)\n", "::B")).to eq(%w[c c=])
  end

  # The control: a form that generates nothing still records nothing.
  it "records nothing for a plain Class.new" do
    expect(generated("C = Class.new(Object)\n", "::C")).to be_empty
  end

  # **And the surface is still open**, which is what stops this from
  # becoming an assertion about what the class does *not* have.
  it "leaves the Struct's surface open" do
    expect(open_surfaces("Seed = Struct.new(:seed, :used)\n")).to include(["Seed", :instance])
  end
end
