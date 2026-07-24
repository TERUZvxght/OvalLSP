# frozen_string_literal: true

RSpec.describe Rslsp::ParserService do
  subject(:service) { described_class.new }

  def document(text, uri: "file:///a.rb", version: 1)
    Rslsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
  end

  def symbol_ids(summary)
    summary.declarations.map(&:symbol_id)
  end

  it "extracts nested class/module/method declarations with absolute owner names" do
    source = <<~RUBY
      module Blog
        class Post
          def title
          end

          def self.published
          end
        end
      end
    RUBY

    summary = service.summarize(document(source))

    expect(symbol_ids(summary)).to contain_exactly(
      Rslsp::Index::SymbolId.new(kind: :module, owner: nil, name: "::Blog", discriminator: nil),
      Rslsp::Index::SymbolId.new(kind: :class, owner: "::Blog", name: "::Blog::Post", discriminator: nil),
      Rslsp::Index::SymbolId.new(kind: :instance_method, owner: "::Blog::Post", name: "title", discriminator: nil),
      Rslsp::Index::SymbolId.new(kind: :singleton_method, owner: "::Blog::Post", name: "published", discriminator: nil)
    )
  end

  it "records the document's uri, version, and a stable content hash" do
    summary = service.summarize(document("class A; end\n", uri: "file:///a.rb", version: 7))

    expect(summary.uri).to eq("file:///a.rb")
    expect(summary.document_version).to eq(7)
    expect(summary.content_hash).to eq(service.summarize(document("class A; end\n", version: 99)).content_hash)
    expect(summary.content_hash).not_to eq(service.summarize(document("class B; end\n", version: 7)).content_hash)
  end

  describe "ERB documents (Task 008.6)" do
    # Before Task 008.6, #summarize fed a .erb document's raw HTML+`<% %>`
    # source directly to Prism, which parsed it as (mostly invalid) Ruby
    # via error recovery -- only Cold Index applied ERB extraction itself,
    # so a constant assigned inside a `<% %>` tag was never actually
    # captured by #summarize when reached through didOpen/didChange or
    # didChangeWatchedFiles' disk reindex, even though the exact same tag
    # indexed correctly through Cold Index. #summarize is now the single
    # place ERB extraction happens, so every caller gets it uniformly
    # (docs/design/tasks/008.6-agent-and-index-hardening.md).
    def erb_document(text, uri: "file:///view.html.erb", version: 1)
      Rslsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "erb")
    end

    it "extracts a constant assigned inside a <% %> tag, surrounded by ordinary HTML" do
      summary = service.summarize(erb_document("<p><% MyHelperConst = 1 %></p>\n"))

      expect(symbol_ids(summary)).to include(
        Rslsp::Index::SymbolId.new(kind: :constant, owner: nil, name: "MyHelperConst", discriminator: nil)
      )
    end

    it "reports no syntax errors for ordinary ERB (HTML isn't Ruby, and must not be parsed as such)" do
      summary = service.summarize(erb_document("<div class=\"x\"><%= @user.name %></div>\n"))

      expect(summary.diagnostics).to be_empty
    end

    it "does not run non-.erb documents through ERB extraction" do
      summary = service.summarize(document("class A\nend\n"))

      expect(symbol_ids(summary)).to contain_exactly(
        Rslsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::A", discriminator: nil)
      )
    end

    it "hashes content from the raw (pre-extraction) source, not the extracted Ruby" do
      raw_a = erb_document("<p>A</p><%= @x %>\n")
      raw_b = erb_document("<p>B</p><%= @x %>\n") # different HTML, identical extracted Ruby region

      expect(service.summarize(raw_a).content_hash).not_to eq(service.summarize(raw_b).content_hash)
    end
  end

  it "gives a reopened class the same SymbolId across both occurrences" do
    source = <<~RUBY
      class User
        def name
        end
      end

      class User
        def email
        end
      end
    RUBY

    summary = service.summarize(document(source))
    class_ids = summary.declarations.select { |d| d.symbol_id.kind == :class }.map(&:symbol_id)

    expect(class_ids.size).to eq(2)
    expect(class_ids[0]).to eq(class_ids[1])
  end

  it "distinguishes public, private, and singleton methods" do
    source = <<~RUBY
      class Account
        def deposit
        end

        def self.open
        end

        private

        def audit_log
        end
      end
    RUBY

    summary = service.summarize(document(source))
    by_name = summary.declarations.each_with_object({}) { |d, h| h[d.symbol_id.name] = d }

    expect(by_name["deposit"].visibility).to eq(:public)
    expect(by_name["audit_log"].visibility).to eq(:private)
    expect(by_name["open"].symbol_id.kind).to eq(:singleton_method)
  end

  it "still extracts declarations that appear before a syntax error" do
    source = <<~RUBY
      class Broken
        def first_method
          1
        end

        def second_method(
      RUBY

    summary = service.summarize(document(source))

    expect(summary.diagnostics).not_to be_empty
    expect(summary.declarations.map { |d| d.symbol_id.name }).to include("first_method")
  end

  it "converts parse errors into LSP-shaped diagnostics" do
    summary = service.summarize(document("def foo(\n"))

    expect(summary.diagnostics).not_to be_empty
    diagnostic = summary.diagnostics.first
    expect(diagnostic[:range][:start]).to include(:line, :character)
    expect(diagnostic[:severity]).to eq(1)
    expect(diagnostic[:source]).to eq("rslsp")
  end

  it "captures top-level constant assignments" do
    summary = service.summarize(document("MAX_RETRIES = 3\n"))

    expect(symbol_ids(summary)).to include(
      Rslsp::Index::SymbolId.new(kind: :constant, owner: nil, name: "MAX_RETRIES", discriminator: nil)
    )
  end

  it "captures required, optional, rest, keyword, keyrest, and block parameters" do
    source = "def m(a, b = 1, *rest, k:, ok: 2, **kw, &blk); end\n"

    summary = service.summarize(document(source))
    params = summary.declarations.first.parameters

    expect(params.map(&:kind)).to eq(%i[required optional rest keyword keyword_optional keyrest block])
    expect(params.map(&:name)).to eq(%w[a b rest k ok kw blk])
  end
end
