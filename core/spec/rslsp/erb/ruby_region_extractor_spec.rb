# frozen_string_literal: true

RSpec.describe Rslsp::Erb::RubyRegionExtractor do
  describe ".extract_ruby_source" do
    it "keeps the same length and line count as the original template" do
      source = "<h1><%= @title %></h1>\n<p><% if @user %>hi<% end %></p>\n"

      result = described_class.extract_ruby_source(source)

      expect(result.length).to eq(source.length)
      expect(result.count("\n")).to eq(source.count("\n"))
    end

    it "keeps Ruby code at its original byte offset" do
      source = "<p><%= @user %></p>\n"

      result = described_class.extract_ruby_source(source)

      offset = source.index("@user")
      expect(result[offset, 5]).to eq("@user")
    end

    it "blanks out HTML and tag delimiters, leaving only code and whitespace" do
      source = "<div class=\"x\"><%= @user.name %></div>\n"

      result = described_class.extract_ruby_source(source)

      expect(result).not_to include("<div", "</div>", "<%=", "%>")
      expect(result).to include("@user.name")
    end

    it "blanks out <%# comment %> tags entirely, extracting no Ruby from them" do
      source = "<%# @secret = 1 %>\n<%= @visible %>\n"

      result = described_class.extract_ruby_source(source)

      expect(result).not_to include("@secret")
      expect(result).to include("@visible")
    end

    it "preserves multi-line Ruby inside a single tag" do
      source = "<% items.each do |item| %>\n  <%= item %>\n<% end %>\n"

      result = described_class.extract_ruby_source(source)

      expect(result).to include("items.each do |item|")
      expect(result.count("\n")).to eq(source.count("\n"))
    end

    it "round-trips through Prism without a syntax error for ordinary ERB" do
      source = "<h1><%= @title %></h1>\n<% if @user %>\n  <%= @user.name %>\n<% end %>\n"

      result = Prism.parse(described_class.extract_ruby_source(source))

      expect(result.errors).to be_empty
    end

    describe "UTF-16 position alignment across non-BMP characters (Task 008.6)" do
      # The invariant that actually matters for LSP: the UTF-16 offset of
      # a Ruby token in the *original* .erb source (computed independently
      # here) must equal the UTF-16 offset Prism's byte-offset location
      # for that same token converts to when read against the *synthetic*
      # source -- not any particular Ruby character-count or byte-count
      # equality, which astral characters make impossible to hold
      # simultaneously with UTF-16 alignment.
      def utf16_offset_of(line_text, char_index)
        line_text[0...char_index].each_char.sum { |c| Rslsp::TextDocument.utf16_unit_count(c) }
      end

      it "keeps an ivar reference at its correct UTF-16 position after an astral emoji earlier on the line" do
        source = "<p>\u{1F600}</p><%= @user %>\n"
        extracted = described_class.extract_ruby_source(source)

        original_line = source.split("\n", -1).first
        expected_utf16 = utf16_offset_of(original_line, original_line.index("@user"))

        node = Prism.parse(extracted).value.statements.body.last
        synthetic_line = extracted.split("\n", -1).first
        actual_utf16 = Rslsp::Index::SourceLocation.byte_offset_to_utf16(synthetic_line, node.location.start_column)

        expect(node).to be_a(Prism::InstanceVariableReadNode)
        expect(actual_utf16).to eq(expected_utf16)
      end

      it "keeps a token aligned after two astral emoji and a BMP (Japanese) character on the same line" do
        source = "<p>\u{1F600}\u{1F600}日</p><%= @user %>\n"
        extracted = described_class.extract_ruby_source(source)

        original_line = source.split("\n", -1).first
        expected_utf16 = utf16_offset_of(original_line, original_line.index("@user"))

        node = Prism.parse(extracted).value.statements.body.last
        synthetic_line = extracted.split("\n", -1).first
        actual_utf16 = Rslsp::Index::SourceLocation.byte_offset_to_utf16(synthetic_line, node.location.start_column)

        expect(actual_utf16).to eq(expected_utf16)
      end

      it "keeps CRLF line endings from shifting positions on a later line" do
        source = "<p>\u{1F600}</p>\r\n<%= @user %>\r\n"
        extracted = described_class.extract_ruby_source(source)

        original_second_line = source.split("\n", -1)[1]
        expected_utf16 = utf16_offset_of(original_second_line, original_second_line.index("@user"))

        node = Prism.parse(extracted).value.statements.body.last
        synthetic_second_line = extracted.split("\n", -1)[1]
        actual_utf16 = Rslsp::Index::SourceLocation.byte_offset_to_utf16(synthetic_second_line, node.location.start_column)

        expect(node.location.start_line).to eq(2) # Prism lines are 1-based
        expect(actual_utf16).to eq(expected_utf16)
      end
    end

    describe "multiple tags on the same rendered line (Task 008.5)" do
      def assert_parses_cleanly(source)
        extracted = described_class.extract_ruby_source(source)

        expect(extracted.length).to eq(source.length)
        expect(extracted.count("\n")).to eq(source.count("\n"))
        expect(Prism.parse(extracted).errors).to be_empty
        extracted
      end

      it "inserts a separator between two adjacent output tags with nothing between them" do
        extracted = assert_parses_cleanly("<%= @a %><%= @b %>\n")

        expect(extracted).to include("@a")
        expect(extracted).to include("@b")
      end

      it "inserts a separator between two adjacent silent tags" do
        assert_parses_cleanly("<% foo %><% bar %>\n")
      end

      it "inserts a separator between two tags separated only by HTML on the same line" do
        extracted = assert_parses_cleanly("<div><%= @user.name %></div><%= @company.name %>\n")

        expect(extracted).to include("@user.name")
        expect(extracted).to include("@company.name")
      end

      it "inserts a separator after a tag whose own code spans multiple lines" do
        extracted = assert_parses_cleanly("<%= foo(\n  bar\n) %><%= baz %>\n")

        expect(extracted).to include("foo(")
        expect(extracted).to include("baz")
      end

      it "does not insert a separator across an actual line break between tags" do
        source = "<%= @a %>\n<%= @b %>\n"

        extracted = assert_parses_cleanly(source)

        expect(extracted).not_to include(";")
      end

      it "does not treat a comment tag as needing (or supplying) a code separator" do
        # The comment carries no code, so it neither needs a semicolon
        # before it nor establishes a "previous code" position for the
        # *following* tag to need one against — there's a comment, not
        # code, immediately before it.
        assert_parses_cleanly("<%# a comment %><%= @a %>\n")
      end
    end
  end
end
