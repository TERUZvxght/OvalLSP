# frozen_string_literal: true

RSpec.describe Ovallsp::ParserService do
  subject(:service) { described_class.new }

  def document(text, uri: "file:///a.rb", version: 1)
    Ovallsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
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
      Ovallsp::Index::SymbolId.new(kind: :module, owner: nil, name: "::Blog", discriminator: nil),
      Ovallsp::Index::SymbolId.new(kind: :class, owner: "::Blog", name: "::Blog::Post", discriminator: nil),
      Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::Blog::Post", name: "title", discriminator: nil),
      Ovallsp::Index::SymbolId.new(kind: :singleton_method, owner: "::Blog::Post", name: "published", discriminator: nil)
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
      Ovallsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "erb")
    end

    it "extracts a constant assigned inside a <% %> tag, surrounded by ordinary HTML" do
      summary = service.summarize(erb_document("<p><% MyHelperConst = 1 %></p>\n"))

      expect(symbol_ids(summary)).to include(
        Ovallsp::Index::SymbolId.new(kind: :constant, owner: nil, name: "MyHelperConst", discriminator: nil)
      )
    end

    it "reports no syntax errors for ordinary ERB (HTML isn't Ruby, and must not be parsed as such)" do
      summary = service.summarize(erb_document("<div class=\"x\"><%= @user.name %></div>\n"))

      expect(summary.diagnostics).to be_empty
    end

    it "does not run non-.erb documents through ERB extraction" do
      summary = service.summarize(document("class A\nend\n"))

      expect(symbol_ids(summary)).to contain_exactly(
        Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::A", discriminator: nil)
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
    expect(diagnostic[:source]).to eq("ovallsp")
  end

  it "captures top-level constant assignments" do
    summary = service.summarize(document("MAX_RETRIES = 3\n"))

    expect(symbol_ids(summary)).to include(
      Ovallsp::Index::SymbolId.new(kind: :constant, owner: nil, name: "MAX_RETRIES", discriminator: nil)
    )
  end

  describe "ancestor and alias facts (Task 009)" do
    def ancestor_facts(summary) = summary.ancestor_facts
    def alias_facts(summary) = summary.alias_facts

    it "captures a superclass declaration, owned by the subclass itself" do
      summary = service.summarize(document("class Admin < User\nend\n"))

      expect(ancestor_facts(summary)).to contain_exactly(
        have_attributes(owner: "::Admin", relation: :superclass, target: "User")
      )
    end

    it "does not record a superclass fact when none is written" do
      summary = service.summarize(document("class Plain\nend\n"))

      expect(ancestor_facts(summary)).to be_empty
    end

    it "captures include/prepend/extend as separate facts, each owned by the enclosing class" do
      source = <<~RUBY
        class Widget
          include Comparable
          prepend Loud
          extend Helpers
        end
      RUBY

      facts = ancestor_facts(service.summarize(document(source)))

      expect(facts).to contain_exactly(
        have_attributes(owner: "::Widget", relation: :include, target: "Comparable"),
        have_attributes(owner: "::Widget", relation: :prepend, target: "Loud"),
        have_attributes(owner: "::Widget", relation: :extend, target: "Helpers")
      )
    end

    it "captures multiple modules from one include call, in argument order" do
      summary = service.summarize(document("class Widget\n  include Comparable, Enumerable\nend\n"))

      expect(ancestor_facts(summary).map(&:target)).to eq(%w[Comparable Enumerable])
    end

    it "does not record include/prepend/extend called with an explicit receiver (out of scope: dynamic reopening)" do
      summary = service.summarize(document("SomeClass.include(Foo)\n"))

      expect(ancestor_facts(summary)).to be_empty
    end

    it "captures `alias new old` (the keyword form)" do
      summary = service.summarize(document("class Widget\n  alias short_name name\nend\n"))

      expect(alias_facts(summary)).to contain_exactly(
        have_attributes(owner: "::Widget", new_name: "short_name", old_name: "name", singleton: false)
      )
    end

    it "captures `alias_method :new, :old` (the method-call form, with symbol arguments)" do
      summary = service.summarize(document("class Widget\n  alias_method :short_name, :name\nend\n"))

      expect(alias_facts(summary)).to contain_exactly(
        have_attributes(owner: "::Widget", new_name: "short_name", old_name: "name", singleton: false)
      )
    end

    it "marks an alias inside `class << self` as singleton" do
      summary = service.summarize(document("class Widget\n  class << self\n    alias short create\n  end\nend\n"))

      expect(alias_facts(summary)).to contain_exactly(
        have_attributes(owner: "::Widget", singleton: true)
      )
    end

    it "does not record alias_method with a non-literal (dynamic) argument" do
      summary = service.summarize(document("class Widget\n  alias_method :short_name, some_variable\nend\n"))

      expect(alias_facts(summary)).to be_empty
    end
  end

  it "captures required, optional, rest, keyword, keyrest, and block parameters" do
    source = "def m(a, b = 1, *rest, k:, ok: 2, **kw, &blk); end\n"

    summary = service.summarize(document(source))
    params = summary.declarations.first.parameters

    expect(params.map(&:kind)).to eq(%i[required optional rest keyword keyword_optional keyrest block])
    expect(params.map(&:name)).to eq(%w[a b rest k ok kw blk])
  end

  # Found by an independent review (round 28). A destructuring parameter is a
  # `Prism::MultiTargetNode`, which has no `#name` at all, and
  # #extract_parameters read `#name` off every entry in `requireds`. The
  # NoMethodError propagated out of #summarize, so the failure was never a
  # degraded parameter list -- it was the loss of the *whole file*: no
  # FileSummary at all, every declaration in it gone from the index, and
  # hover/definition/completion/diagnostics dark for it. Measured against a
  # real workspace file, Server logged `cold index: failed to index <file>:
  # NoMethodError: undefined method 'name' for an instance of
  # Prism::MultiTargetNode` and indexed none of it.
  #
  # `other` is here specifically so the example fails on the *collateral*
  # loss rather than only on the one method's parameter list.
  it "indexes a whole file containing a method with a destructuring parameter" do
    source = "class A\n  def m(a, (b, c))\n  end\n\n  def other\n  end\nend\n"

    summary = service.summarize(document(source))

    expect(summary.declarations.map { |d| d.symbol_id.name }).to eq(%w[::A m other])
    params = summary.declarations.find { |d| d.symbol_id.name == "m" }.parameters
    # The nameless slot is kept, never dropped -- dropping it would shift
    # every later parameter out of its own position. `nil` is already an
    # ordinary shape here (an anonymous `*`/`**`/`&` produces one too).
    expect(params.map(&:kind)).to eq(%i[required required])
    expect(params.map(&:name)).to eq(["a", nil])
  end

  # Same round, same method: `posts` -- the required parameters that follow a
  # `*rest` -- were never read at all, so a parameter that plainly exists was
  # reported as not existing and signature help rendered `m(a, rest)`.
  it "captures a required parameter that follows a rest parameter" do
    source = "def m(a, *rest, b, k: 1, &blk); end\n"

    params = service.summarize(document(source)).declarations.first.parameters

    expect(params.map(&:name)).to eq(%w[a rest b k blk])
    expect(params.map(&:kind)).to eq(%i[required rest required keyword_optional block])
  end

  describe "Rails DSL generated methods (Task 017)" do
    def generated(summary) = summary.generated_method_facts

    it "generates a predicate method per enum value, keyword-argument form" do
      summary = service.summarize(document("class Widget\n  enum status: { active: 0, archived: 1 }\nend\n"))

      expect(generated(summary)).to contain_exactly(
        have_attributes(owner: "::Widget", name: "active?", kind: :instance_method, origin: :enum,
                         return_type: Ovallsp::Types::Nominal.new(name: "Boolean")),
        have_attributes(owner: "::Widget", name: "archived?", kind: :instance_method, origin: :enum)
      )
    end

    it "generates a predicate method per enum value, positional-array form" do
      summary = service.summarize(document("class Widget\n  enum :status, %i[active archived]\nend\n"))

      expect(generated(summary).map(&:name)).to contain_exactly("active?", "archived?")
    end

    it "also records the enum-generated methods as ordinary Declarations (origin: :generated)" do
      summary = service.summarize(document("class Widget\n  enum status: { active: 0 }\nend\n"))

      decl = summary.declarations.find { |d| d.symbol_id.name == "active?" }
      expect(decl.origin).to eq(:generated)
      expect(decl.symbol_id.owner).to eq("::Widget")
    end

    it "generates a singleton method returning Relation[Model] for scope" do
      summary = service.summarize(document("class Widget\n  scope :active, -> { where(active: true) }\nend\n"))

      expect(generated(summary)).to contain_exactly(
        have_attributes(
          owner: "::Widget", name: "active", kind: :singleton_method, origin: :scope,
          return_type: Ovallsp::Types::Generic.new(name: "Relation", type_arg: Ovallsp::Types::Nominal.new(name: "Widget"))
        )
      )
    end

    it "generates a delegate method per delegated name, with metadata for later return-type resolution" do
      summary = service.summarize(document("class Widget\n  delegate :name, :age, to: :company\nend\n"))

      expect(generated(summary)).to contain_exactly(
        have_attributes(name: "name", origin: :delegate, metadata: { to: "company", delegated_name: "name", allow_nil: false }),
        have_attributes(name: "age", origin: :delegate, metadata: { to: "company", delegated_name: "age", allow_nil: false })
      )
    end

    it "prefixes the delegated method name when prefix: true" do
      summary = service.summarize(document("class Widget\n  delegate :name, to: :company, prefix: true\nend\n"))

      expect(generated(summary).map(&:name)).to eq(["company_name"])
    end

    it "records allow_nil: true in metadata" do
      summary = service.summarize(document("class Widget\n  delegate :name, to: :company, allow_nil: true\nend\n"))

      expect(generated(summary).first.metadata[:allow_nil]).to be(true)
    end

    it "does not recognize enum/scope/delegate written outside any class/module body" do
      summary = service.summarize(document("enum status: { active: 0 }\n"))

      expect(generated(summary)).to be_empty
    end
  end
end
