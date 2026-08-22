# frozen_string_literal: true

# `024.33`. `K.instance_eval { attr_accessor :x }` was reported and
# `K.class_eval { attr_accessor :x }` was not -- one construct, two
# spellings, opposite answers. Ruby treats them the same here, because
# `attr_accessor` is a *call on self* and self is `K` either way:
#
#   $ ruby -e '
#   class K; end
#   K.instance_eval { attr_accessor :k_x }
#   p ["instance_eval", K.respond_to?(:k_x), K.new.respond_to?(:k_x)]
#   class L; end
#   L.class_eval { attr_accessor :l_x }
#   p ["class_eval", L.respond_to?(:l_x), L.new.respond_to?(:l_x)]
#   '
#   # => ["instance_eval", false, true]
#   # => ["class_eval", false, true]
#   # ruby 3.4.10
#
# Both define an *instance* accessor on the named class. The visitor
# could not say *which* module self was, which is why the two spellings
# were split; a written constant says which.
RSpec.describe "Ovallsp::ParserService and an eval block on a constant" do
  def generated(text)
    Ovallsp::ParserService.new
      .summarize(Ovallsp::TextDocument.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby"))
      .declarations.select { |d| d.origin == :generated }
      .map { |d| [d.symbol_id.kind, d.symbol_id.owner, d.symbol_id.name] }.sort
  end

  it "records an instance accessor on the constant for instance_eval" do
    expect(generated("class K\nend\nK.instance_eval { attr_accessor :k_x }\n"))
      .to eq([[:instance_method, "::K", "k_x"], [:instance_method, "::K", "k_x="]])
  end

  it "records the same for class_eval, which is the same thing in Ruby" do
    expect(generated("class L\nend\nL.class_eval { attr_accessor :l_x }\n"))
      .to eq([[:instance_method, "::L", "l_x"], [:instance_method, "::L", "l_x="]])
  end

  # The control: an eval block on an *expression* is not a constant, and
  # this visitor still cannot say what self is there. It must not invent
  # an owner from the enclosing class.
  it "records nothing for an eval block on an expression" do
    expect(generated("class Outer\n  def go(other)\n    other.instance_eval { attr_accessor :o_x }\n  end\nend\n"))
      .to be_empty
  end
end
