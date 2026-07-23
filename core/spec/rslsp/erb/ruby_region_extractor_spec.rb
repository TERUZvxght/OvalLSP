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
