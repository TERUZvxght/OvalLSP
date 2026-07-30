# frozen_string_literal: true

RSpec.describe Ovallsp::Documentation do
  def above(text, line) = described_class.above(text, line)

  it "reads the comment block immediately above a declaration" do
    text = <<~RUBY
      # Charges the card.
      # Raises on a declined payment.
      def charge
      end
    RUBY

    expect(above(text, 2)).to eq("Charges the card.\nRaises on a declined payment.")
  end

  it "returns nil when the declaration has no comment above it" do
    expect(above("def charge\nend\n", 0)).to be_nil
  end

  # Contiguity is the whole rule. A blank line means the comment is about
  # something else -- most often the declaration before it -- and carrying
  # it forward puts one method's documentation on the next one.
  it "stops at a blank line rather than reaching past it" do
    text = <<~RUBY
      # About the method above.

      def charge
      end
    RUBY

    expect(above(text, 2)).to be_nil
  end

  it "keeps a bare `#` as a paragraph break inside a block" do
    text = <<~RUBY
      # First paragraph.
      #
      # Second paragraph.
      def charge
      end
    RUBY

    expect(above(text, 3)).to eq("First paragraph.\n\nSecond paragraph.")
  end

  # These sit above the first declaration in a great many files, and they
  # are addressed to the interpreter and the tools rather than to a
  # reader.
  it "drops magic comments and tool directives" do
    text = <<~RUBY
      # frozen_string_literal: true
      # rubocop:disable Metrics/MethodLength
      # Charges the card.
      def charge
      end
    RUBY

    expect(above(text, 3)).to eq("Charges the card.")
  end

  it "returns nil for a block that is only directives" do
    text = "# frozen_string_literal: true\ndef charge\nend\n"

    expect(above(text, 1)).to be_nil
  end

  # Only one space after the marker: the second one is indentation, and
  # eating it flattens a code example in a comment into prose.
  it "removes one space after the comment marker and no more" do
    text = <<~RUBY
      # Example:
      #     charge(100)
      def charge
      end
    RUBY

    expect(above(text, 2)).to eq("Example:\n    charge(100)")
  end

  it "handles a comment with no space after the marker" do
    expect(above("#Charges.\ndef charge\nend\n", 1)).to eq("Charges.")
  end

  it "returns nil for a declaration on the first line" do
    expect(above("def charge\nend\n", 0)).to be_nil
  end

  # A caller that could not locate the declaration at all hands over nil,
  # and arithmetic on it raises rather than answering.
  it "returns nil rather than raising when there is no line number" do
    expect(above("# Charges.\ndef charge\nend\n", nil)).to be_nil
  end

  it "returns nil rather than raising when the line is past the end of the text" do
    expect(above("def charge\nend\n", 99)).to be_nil
  end
end
