# frozen_string_literal: true

# `024.34`. `attr_accessor` written inside a `def` inside `class << self`
# was recorded as a *singleton* accessor, because the recorder asked
# `Cref#declares_singleton?` -- the right answer to a bare `def`'s
# question and the wrong one to this. Ruby:
#
#   $ ruby -e '
#   class S
#     class << self
#       def setup
#         attr_accessor :attr_x
#       end
#     end
#   end
#   S.setup
#   p [S.new.respond_to?(:attr_x), S.respond_to?(:attr_x)]
#   '
#   # => [true, false]
#   # ruby 3.4.10
#
# The engine reported `S.attr_x` -- a false positive on code that runs,
# which is the unsafe direction.
RSpec.describe "Ovallsp::ParserService and attr_* inside a singleton def" do
  def summarize(text)
    Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby")
    )
  end

  def generated(summary, kind)
    summary.declarations.select { |d| d.symbol_id.kind == kind && d.origin == :generated }
           .map { |d| d.symbol_id.name }.sort
  end

  let(:source) do
    "class S\n  class << self\n    def setup\n      attr_accessor :attr_x\n    end\n  end\nend\n"
  end

  it "records an instance accessor, as Ruby defines one" do
    expect(generated(summarize(source), :instance_method)).to eq(["attr_x", "attr_x="])
  end

  it "records no singleton accessor" do
    expect(generated(summarize(source), :singleton_method)).to be_empty
  end

  # The control, and the reason this is not "attr_* is never singleton":
  # written *directly* in `class << self`, it defines a class-level
  # accessor and Ruby answers `S.direct_x`.
  #
  #   $ ruby -e '
  #   class D; class << self; attr_accessor :direct_x; end; end
  #   p [D.respond_to?(:direct_x), D.new.respond_to?(:direct_x)]
  #   '
  #   # => [true, false]
  #   # ruby 3.4.10
  it "still records a singleton accessor written directly in class << self" do
    summary = summarize("class D\n  class << self\n    attr_accessor :direct_x\n  end\nend\n")

    expect(generated(summary, :singleton_method)).to eq(["direct_x", "direct_x="])
    expect(generated(summary, :instance_method)).to be_empty
  end
end
