# frozen_string_literal: true

# `024.31`. A block that *creates a class* has an owner this parser
# cannot name, and the declarations inside it were attributed to the
# lexically enclosing class instead -- so `Outer` grew members it does
# not have.
#
#   $ ruby -e '
#   class Outer
#     Seed = Struct.new(:x) do
#       attr_reader :label
#     end
#   end
#   p [Outer.new.respond_to?(:label), Outer.instance_methods(false)]
#   p Outer::Seed.new(1).respond_to?(:label)
#   '
#   # => [false, []]
#   # => true
#   # ruby 3.4.10
#
# The accessor belongs to the Struct. Recording it on `Outer` is the
# direction that *invents* a member, which is the one this engine refuses
# everywhere else.
RSpec.describe "Ovallsp::ParserService and a block that creates a class" do
  def generated(text)
    Ovallsp::ParserService.new
      .summarize(Ovallsp::TextDocument.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby"))
      .declarations.select { |d| d.origin == :generated }
      .map { |d| [d.symbol_id.kind, d.symbol_id.owner, d.symbol_id.name] }.sort
  end

  # **`x` and `x=` are the Struct's own, and they belong to it.** They
  # are recorded since 0.3.0 (`024.237`) -- the point this example
  # makes is where they land, not whether they exist. `label`, which
  # the *block* declares, is still attributed to nothing: the block's
  # owner is a class this parser cannot name.
  it "puts a Struct.new block's members on the Struct and nothing on the enclosing class" do
    recorded = generated("class Outer\n  Seed = Struct.new(:x) do\n    attr_reader :label\n  end\nend\n")

    expect(recorded).to eq([[:instance_method, "::Outer::Seed", "x"],
                            [:instance_method, "::Outer::Seed", "x="]])
    expect(recorded.map { |(_, owner, _)| owner }).not_to include("::Outer")
    expect(recorded.map(&:last)).not_to include("label")
  end

  it "records nothing for a Class.new block, however deep" do
    source = "class Outer\n  def build\n    Class.new(Object) do\n      class << self\n" \
             "        attr_accessor :left_model\n      end\n    end\n  end\nend\n"

    expect(generated(source)).to be_empty
  end

  it "records a Data.define block's members on the Data class, and a Module.new block's nowhere" do
    expect(generated("class Outer\n  M = Module.new do\n    attr_reader :m_x\n  end\nend\n")).to be_empty

    # `Data.define(:a)` generates a reader and no writer, so `a` is the
    # whole of it; `d_x` is the block's and stays unattributed.
    expect(generated("class Outer\n  D = Data.define(:a) do\n    attr_reader :d_x\n  end\nend\n"))
      .to eq([[:instance_method, "::Outer::D", "a"]])
  end

  # The control, and what an implementation that simply dropped every
  # block would break: `included do attr_accessor :tracked_at end` really
  # does define on the concern, and `Outer` keeps its own macros.
  it "still records an ordinary class-body accessor and an included block's" do
    expect(generated("class Outer\n  attr_accessor :own\nend\n"))
      .to eq([[:instance_method, "::Outer", "own"], [:instance_method, "::Outer", "own="]])
    expect(generated("module Taggable\n  included do\n    attr_accessor :tracked_at\n  end\nend\n"))
      .to eq([[:instance_method, "::Taggable", "tracked_at"], [:instance_method, "::Taggable", "tracked_at="]])
  end
end
