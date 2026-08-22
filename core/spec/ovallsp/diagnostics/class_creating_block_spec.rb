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

  it "records nothing on the enclosing class for a Struct.new block" do
    expect(generated("class Outer\n  Seed = Struct.new(:x) do\n    attr_reader :label\n  end\nend\n"))
      .to be_empty
  end

  it "records nothing for a Class.new block, however deep" do
    source = "class Outer\n  def build\n    Class.new(Object) do\n      class << self\n" \
             "        attr_accessor :left_model\n      end\n    end\n  end\nend\n"

    expect(generated(source)).to be_empty
  end

  it "records nothing for a Module.new or Data.define block" do
    expect(generated("class Outer\n  M = Module.new do\n    attr_reader :m_x\n  end\nend\n")).to be_empty
    expect(generated("class Outer\n  D = Data.define(:a) do\n    attr_reader :d_x\n  end\nend\n")).to be_empty
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
