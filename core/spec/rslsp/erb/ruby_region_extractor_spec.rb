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
  end
end
