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

  # Regression: only the bare, argumentless section form was recognized,
  # so `private def …` -- idiomatic in Rails controllers -- and
  # `private :sym` both recorded the method as public. Everything reading
  # Declaration#visibility inherited that: Rails action detection (a
  # private helper was treated as an action, leaking its ivars into a
  # view), completion filtering, and method resolution.
  it "honors the argument forms of private/protected, not only the bare section form" do
    source = <<~RUBY
      class PostsController
        def edit
        end

        private def prepare_inline
        end

        def prepare_symbol
        end
        private :prepare_symbol

        protected def collaborate
        end

        def still_public
        end
      end
    RUBY

    summary = service.summarize(document(source))
    by_name = summary.declarations.each_with_object({}) { |d, h| h[d.symbol_id.name] = d }

    expect(by_name["prepare_inline"].visibility).to eq(:private)
    # (see also the `class << self` and method-body cases below)
    expect(by_name["prepare_symbol"].visibility).to eq(:private)
    expect(by_name["collaborate"].visibility).to eq(:protected)
    # The argument forms name specific methods; they must not open a
    # section that swallows everything declared after them.
    expect(by_name["edit"].visibility).to eq(:public)
    expect(by_name["still_public"].visibility).to eq(:public)
  end

  # Regression: visibility handling must be scoped to the body it appears
  # in. Both of these silently privatized a real Rails action, which the
  # action detector then dropped -- so a controller's ivars stopped
  # reaching its view with no error anywhere.
  it "keeps `class << self` visibility out of the enclosing class's instance methods" do
    source = <<~RUBY
      class UsersController
        class << self
          private

          def internal_helper
          end
        end

        def show
        end
      end
    RUBY

    summary = service.summarize(document(source))
    by_name = summary.declarations.each_with_object({}) { |d, h| h[d.symbol_id.name] = d }

    expect(by_name["show"].visibility).to eq(:public)
  end

  it "does not let `private :name` inside `class << self` privatize the same-named instance method" do
    source = <<~RUBY
      class UsersController
        def show
        end

        class << self
          def show
          end
          private :show
        end
      end
    RUBY

    summary = service.summarize(document(source))
    instance_show = summary.declarations.find do |d|
      d.symbol_id.kind == :instance_method && d.symbol_id.name == "show"
    end

    expect(instance_show.visibility).to eq(:public)
  end

  it "ignores `private :name` written inside a method body, which never runs at class level" do
    source = <<~RUBY
      class Foo
        def wrapper
          private :target
        end

        def target
        end
      end
    RUBY

    summary = service.summarize(document(source))
    by_name = summary.declarations.each_with_object({}) { |d, h| h[d.symbol_id.name] = d }

    expect(by_name["target"].visibility).to eq(:public)
  end

  # Regression: the same leak as `class << self`, through the door Rails
  # code actually walks through. `concerning`/`included do`/`class_eval
  # do` run their body against a different module, so a `private` inside
  # cannot reach the class body -- but with no frame for the block it set
  # the enclosing class's section and never restored it, and every method
  # written after the block was recorded private. The `class << self` fix
  # pushed a frame at exactly one of the three sites that need one.
  it "keeps a visibility section opened inside a block out of the enclosing class body" do
    source = <<~RUBY
      class UsersController
        concerning :Authentication do
          private

          def authenticate
          end
        end

        def show
        end
      end
    RUBY

    summary = service.summarize(document(source))
    by_name = summary.declarations.each_with_object({}) { |d, h| h[d.symbol_id.name] = d }

    expect(by_name["authenticate"].visibility).to eq(:private)
    expect(by_name["show"].visibility).to eq(:public)
  end

  # A plain iterator block opens no new cref, so a `def` inside it really
  # does take the enclosing section's visibility. The block frame has to
  # inherit for that reason -- resetting it to :public would trade this
  # leak for the opposite error.
  it "still applies the enclosing section to a method declared inside a plain block" do
    source = <<~RUBY
      class Foo
        private

        [1].each do |_i|
          def generated
          end
        end
      end
    RUBY

    summary = service.summarize(document(source))
    generated = summary.declarations.find { |d| d.symbol_id.name == "generated" }

    expect(generated.visibility).to eq(:private)
  end

  it "ignores a bare `private` written inside a method body, which never runs at class level" do
    source = <<~RUBY
      class Foo
        def wrapper
          private
        end

        def target
        end
      end
    RUBY

    summary = service.summarize(document(source))
    by_name = summary.declarations.each_with_object({}) { |d, h| h[d.symbol_id.name] = d }

    expect(by_name["target"].visibility).to eq(:public)
  end

  # Regression: the same cross-kind hit the `class << self` guard exists
  # to prevent, reached through the other two receiver-bearing `def`
  # forms. A singleton method records no visibility, so the rewrite found
  # nothing under its own kind and landed on the same-named *instance*
  # method -- privatizing a real Rails action and dropping it from view
  # propagation.
  it "does not let `private def self.name` privatize the same-named instance method" do
    source = <<~RUBY
      class PostsController
        def index
        end

        private def self.index
        end

        def show
        end
      end
    RUBY

    summary = service.summarize(document(source))
    instance_index = summary.declarations.find do |d|
      d.symbol_id.kind == :instance_method && d.symbol_id.name == "index"
    end

    expect(instance_index.visibility).to eq(:public)
  end

  # The pending entry leaked the same way: it is recorded under
  # `current_owner` but consumed under the def's own owner, so it sat
  # there until an unrelated instance method of the enclosing class
  # claimed it.
  it "does not let `private def Const.name` privatize a later same-named instance method" do
    source = <<~RUBY
      class A
        private def Helper.foo
        end

        def foo
        end
      end
    RUBY

    summary = service.summarize(document(source))
    own_foo = summary.declarations.find do |d|
      d.symbol_id.kind == :instance_method && d.symbol_id.owner == "::A" && d.symbol_id.name == "foo"
    end

    expect(own_foo.visibility).to eq(:public)
  end

  # Regression: a pending entry was recorded for *every* argument form,
  # but only a `def` argument needs one -- a symbol argument names a
  # method that already exists and is handled by the retroactive rewrite.
  # The extra entry was never consumed and never cleared, so the next
  # `def` of that name claimed it: a same-file reopen recorded its
  # second, public definition as private and lost the action.
  it "does not let `private :name` privatize a later redefinition of that name" do
    source = <<~RUBY
      class Foo
        def target
        end
        private :target

        def target
        end
      end
    RUBY

    summary = service.summarize(document(source))
    redefinition = summary.declarations.select { |d| d.symbol_id.name == "target" }.last

    expect(redefinition.visibility).to eq(:public)
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

  # Found by an independent review (round 29), and the same collateral round
  # 28 found one method below in #extract_parameters, reached through the same
  # "assume the Prism node answers" habit: #visit_namespace read
  # `node.constant_path.full_name` bare, and that method *raises*
  # `Prism::ConstantPathNode::DynamicPartsInConstantPathError` for a path with
  # a non-constant segment. The raise propagated out of #summarize, so the
  # failure was never one namespace's name -- it was the whole file: no
  # FileSummary at all, every declaration gone from the index.
  #
  # Two halves, both load-bearing. `Gamma` fails on the *collateral* loss
  # rather than only on `Beta`. And the skipped namespace is deliberately
  # *nested*, with a sibling declared after it: that is what rejects the
  # obvious wrong fix, a bare `return unless` above #visit_namespace's old
  # `ensure`, which pops four stacks that were never pushed. At the top level
  # that happens to rebalance (popping an empty @owner_stack is a no-op, and
  # the next namespace re-pushes @visibility_stack), so a top-level-only
  # example passes for the wrong implementation; nested, it unwinds `Outer`
  # early and `later_sibling` lands on the wrong owner -- silently, with the
  # file still indexing.
  it "indexes the rest of a file containing a namespace whose constant path is not statically resolvable" do
    source = <<~RUBY
      module Outer
        class self::Beta
          def b; end
        end

        def later_sibling; end
      end

      class Gamma
        def c; end
      end
    RUBY

    summary = service.summarize(document(source))

    expect(summary.declarations.map { |d| [d.symbol_id.kind, d.symbol_id.owner, d.symbol_id.name] }).to eq(
      [[:module, nil, "::Outer"], [:instance_method, "::Outer", "later_sibling"],
       [:class, nil, "::Gamma"], [:instance_method, "::Gamma", "c"]]
    )
  end

  # The same loss, one keystroke from anybody, and via the *other* half of
  # the guard. Prism is deliberately error-tolerant here -- this class's
  # whole premise is that "even when the source has a syntax error,
  # declarations before the error remain visible" (Task 002 acceptance
  # criterion) -- and the document is reparsed on every didChange. Half-way
  # through typing `class Foo::Bar`, at `class Foo::`, `node.constant_path`
  # is not a ConstantPathNode at all but a `Prism::CallNode`, which has no
  # `#full_name` to raise from: it raises `NoMethodError` instead. So this is
  # #extract_parameters' round-28 defect exactly -- a missing `respond_to?`
  # -- and it wiped the file's whole index mid-edit, which is when hover and
  # completion are most wanted. The diagnostics are asserted alongside
  # because reporting the error *while still indexing what parsed* is the
  # entire point of this path.
  it "keeps indexing, and still reports the error, mid-edit on an incomplete namespace path" do
    source = "class Alpha\n  def a; end\nend\n\nclass Foo::\n  def b; end\nend\n"

    summary = service.summarize(document(source))

    expect(summary.declarations.map { |d| d.symbol_id.name }).to include("::Alpha", "a")
    expect(summary.diagnostics).not_to be_empty
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

  # A file deep enough to exhaust the interpreter stack used to take the
  # whole process with it. `SystemStackError` is an `Exception`, not a
  # `StandardError`, so every rescue between the visitor and `Server#run`
  # let it through: opening one such file over `didOpen` ended the
  # editor's session with a raw Ruby backtrace on stderr, the cold-index
  # thread died silently (skipping the sweep, the reference-index bump and
  # the workspace diagnostics pass for the rest of the session), and
  # `BackgroundTasks#shutdown` -- documented "never raises" -- raised out
  # of `run`'s own ensure because `Thread#join` re-raises.
  #
  # Contained here, where the recursion is, rather than at each caller:
  # `Server#dispatch`, the cold indexer and `scripts/corpus_diagnostics.rb`
  # each had their own rescue and each was individually plausible, which
  # is the shape CLAUDE.md's containment rule is about.
  #
  # Measured before choosing the depth: a `.succ` chain fails at 2104,
  # nested hashes at 1147, nested `if` at 1145. 0 of 4582 `.rb` files
  # across every installed gem and the Ruby 3.4 stdlib reach any of them,
  # so this is generated or hostile input -- and a file arrives from
  # anywhere.
  describe "a file deep enough to exhaust the stack" do
    let(:document) do
      source = "class Chain\n  def go\n    x = 1\n    x#{'.succ' * 5_000}\n  end\nend\n"
      Ovallsp::TextDocument.new(uri: "file:///deep.rb", text: source, version: 1, language_id: "ruby")
    end

    it "answers a summary instead of taking the process with it" do
      summary = nil

      expect { summary = described_class.new.summarize(document) }.not_to raise_error
      expect(summary.uri).to eq("file:///deep.rb")
    end

    # What it answers is "nothing was read here", not a half-built index:
    # a partial walk would leave declarations from the top of the file and
    # none from the bottom, and the undefined-method check would then
    # assert absence on the strength of it.
    it "records nothing rather than a partial reading of the file" do
      summary = described_class.new.summarize(document)

      expect(summary.declarations).to be_empty
      expect(summary.reference_candidates).to be_empty
    end
  end
end

