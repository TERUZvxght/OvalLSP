# frozen_string_literal: true

# What a block that keeps `self` carries out to the body around it.
#
# `Cref#in_block(shares_self: true)` returns the *same* cref, because a
# block iterating a literal does not rebind self. Three releases have
# adjusted that rule (`024.110`, `024.111`, `024.117`), and 0.2.13
# declared three behaviours fixed while pinning one of them -- see
# `024.219`. So the list lives here, once, as a table both directions are
# driven from, rather than as prose in a comment that a spec is trusted
# to have kept up with.
#
# Every row was established by asking ruby 3.4.10, not by reasoning about
# it:
#
#   $ ruby -e '
#   class BV; [1].each { private }; def x; end; end
#   p BV.private_instance_methods(false)
#   class BT; [1].each { protected }; def t; end; end
#   p BT.protected_instance_methods(false)
#   class BU; private; [1].each { public }; def u; end; end
#   p BU.public_instance_methods(false)
#   module BMF; 1.times { module_function }; def y; end; end
#   p [BMF.respond_to?(:y), BMF.private_instance_methods(false)]
#   class BS; [1].each { attr_accessor :bs_x }; end
#   p [BS.new.respond_to?(:bs_x), BS.respond_to?(:bs_x)]
#   '
#   # => [:x]
#   # => [:t]
#   # => [:u]
#   # => [true, [:y]]
#   # => [true, false]
#   # ruby 3.4.10
RSpec.describe "a block that keeps self" do
  def declarations(source)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    Ovallsp::ParserService.new.summarize(document).declarations
                          .select { |d| d.symbol_id.kind.to_s.include?("method") }
                          .map { |d| [d.symbol_id.kind, d.symbol_id.name, d.visibility] }
  end

  # Each row: what the block contains, the source, and every method
  # declaration the enclosing body must then have. A construct added to
  # this rule is added here, and is pinned by being here.
  CARRIED_OUT = {
    "private" => [
      "class BV\n  [1].each { private }\n  def x; end\nend\n",
      [[:instance_method, "x", :private]]
    ],
    "protected" => [
      "class BT\n  [1].each { protected }\n  def t; end\nend\n",
      [[:instance_method, "t", :protected]]
    ],
    "public, cancelling an open private" => [
      "class BU\n  private\n  [1].each { public }\n  def u; end\nend\n",
      [[:instance_method, "u", :public]]
    ],
    "module_function" => [
      "module BMF\n  1.times { module_function }\n  def y; end\nend\n",
      [[:instance_method, "y", :private], [:singleton_method, "y", :public]]
    ],
    "attr_accessor" => [
      "class BS\n  [1].each { attr_accessor :bs_x }\nend\n",
      [[:instance_method, "bs_x", :public], [:instance_method, "bs_x=", :public]]
    ]
  }.freeze

  CARRIED_OUT.each do |what, (source, expected)|
    it "carries #{what} out to the enclosing body" do
      expect(declarations(source)).to match_array(expected)
    end
  end

  # The other direction, and the reason the frame exists at all. Each of
  # these runs its `private` against a *different* module, so it must not
  # reach the enclosing body -- and 0.2.7 records what happened when one
  # did: every method written after such a block was recorded private,
  # actions were filtered out on `visibility == :public`, and their ivars
  # vanished from the matching views.
  CONTAINED = {
    "included do ... end" => "module C\n  included do\n    private\n  end\n  def z; end\nend\n",
    "class_eval on a constant" => "class K; end\nclass H\n  K.class_eval { private }\n  def z; end\nend\n",
    "concerning" => "class BQ\n  concerning :Auth do\n    private\n  end\n  def z; end\nend\n",
    # A constant receiver could be anything, and this parser cannot say
    # what its `each` does with self.
    "a constant receiver" => "class BR\n  SOME.each { private }\n  def z; end\nend\n"
  }.freeze

  CONTAINED.each do |what, source|
    it "does not carry a visibility section out of #{what}" do
      expect(declarations(source)).to eq([[:instance_method, "z", :public]])
    end
  end

  # The three nested scopes the shared frame could break by carrying too
  # much. Asked of ruby 3.4.10 rather than reasoned about, because "a
  # section written in a nested scope" is the shape this rule has already
  # been wrong about once:
  #
  #   $ ruby -e '
  #   class BB; [1].each { [2].each { private } }; def x; end; end
  #   p BB.private_instance_methods(false)
  #   class BN; [1].each { class Inner; private; def i; end; end }; def after; end; end
  #   p [BN.private_instance_methods(false), BN.public_instance_methods(false)]
  #   class BD; [1].each { def inner; private; end }; def after; end; end
  #   p [BD.private_instance_methods(false), BD.public_instance_methods(false).sort]
  #   '
  #   # => [:x]
  #   # => [[], [:after]]
  #   # => [[], [:after, :inner]]
  it "carries through two nested blocks that both keep self" do
    expect(declarations("class BB\n  [1].each { [2].each { private } }\n  def x; end\nend\n"))
      .to eq([[:instance_method, "x", :private]])
  end

  it "does not carry out of a class opened inside such a block" do
    source = "class BN\n  [1].each do\n    class Inner\n      private\n      def i; end\n    end\n  end\n  def after; end\nend\n"

    expect(declarations(source))
      .to eq([[:instance_method, "i", :private], [:instance_method, "after", :public]])
  end

  it "does not carry out of a method body written inside such a block" do
    source = "class BD\n  [1].each do\n    def inner\n      private\n    end\n  end\n  def after; end\nend\n"

    expect(declarations(source))
      .to eq([[:instance_method, "inner", :public], [:instance_method, "after", :public]])
  end

  # Without this the examples above would all pass on a parser that
  # recorded every method private, or every method public.
  it "still records an ordinary visibility section written with no block" do
    expect(declarations("class BC\n  private\n  def x; end\nend\n"))
      .to eq([[:instance_method, "x", :private]])
  end

  it "still records a public method where no section is open" do
    expect(declarations("class BP\n  def x; end\nend\n"))
      .to eq([[:instance_method, "x", :public]])
  end
end
