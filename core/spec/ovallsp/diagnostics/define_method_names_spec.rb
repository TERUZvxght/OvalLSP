# frozen_string_literal: true

# `024.116`'s residue. `define_method(:x)` and `define_singleton_method(:x)`
# open the owner's surface, so calls to `x` stopped being reported -- but
# the *name* was never recorded, so hover, go to definition and completion
# all answered nothing. Silence instead of an answer, which is the safe
# direction and not the right one.
#
# A literal symbol or string argument names the method as plainly as a
# `def` does:
#
#   $ ruby -e '
#   class R
#     define_singleton_method(:lookup) { 1 }
#     define_method(:each_thing) { 2 }
#   end
#   p [R.respond_to?(:lookup), R.new.respond_to?(:each_thing)]
#   '
#   # => [true, true]
#   # ruby 3.4.10
RSpec.describe "Ovallsp::ParserService and define_method's name" do
  def declared(text)
    Ovallsp::ParserService.new
      .summarize(Ovallsp::TextDocument.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby"))
      .declarations.select { |d| d.origin == :generated }
      .map { |d| [d.symbol_id.kind, d.symbol_id.owner, d.symbol_id.name] }.sort
  end

  it "records a define_method name as an instance method" do
    expect(declared("class R\n  define_method(:each_thing) { 2 }\nend\n"))
      .to eq([[:instance_method, "::R", "each_thing"]])
  end

  it "records a define_singleton_method name as a class method" do
    expect(declared("class R\n  define_singleton_method(:lookup) { 1 }\nend\n"))
      .to eq([[:singleton_method, "::R", "lookup"]])
  end

  it "records a string argument too" do
    expect(declared("class R\n  define_method(\"from_string\") { 3 }\nend\n"))
      .to eq([[:instance_method, "::R", "from_string"]])
  end

  # The control, and the reason the surface still opens: a *computed*
  # name is exactly what this parser cannot read, and recording nothing
  # for it is why the owner has to stay unenumerable.
  it "records nothing for a computed name, leaving the surface open" do
    source = "class R\n  %i[a b].each { |n| define_method(n) { 1 } }\nend\n"

    expect(declared(source)).to be_empty
    summary = Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    )
    expect(summary.open_surface_owners).to include(["R", :instance])
  end
end
