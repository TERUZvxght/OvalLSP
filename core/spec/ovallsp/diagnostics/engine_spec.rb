# frozen_string_literal: true

RSpec.describe Ovallsp::Diagnostics::Engine do
  subject(:engine) { described_class.new }

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:method_resolver) { stack.method_resolver }
  let(:local_inferencer) { stack.local_inferencer }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:route_registry) { Ovallsp::Routes::RouteRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) } }

  def context(**overrides)
    Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry, route_registry: route_registry,
      signatures: signatures, generation: 1, **overrides
    )
  end

  def index(text, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  it "raises for an unrecognized mode rather than silently degrading" do
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: "1\n", version: 1, language_id: "ruby")

    expect { engine.analyze(document: document, semantic_context: context, mode: :bogus) }.to raise_error(ArgumentError)
  end

  describe "syntax findings" do
    it "surfaces a Prism syntax error as a high-confidence finding" do
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: "def foo(\nend\n", version: 1, language_id: "ruby")

      findings = engine.analyze(document: document, semantic_context: context)

      expect(findings.map(&:code)).to include("syntax-error")
      expect(findings.find { |f| f.code == "syntax-error" }.confidence).to eq(:high)
    end
  end

  describe "unknown-method (Safe mode)" do
    it "flags a call with no such method on a closed, single-Nominal receiver" do
      document = index("class Widget\n  def show\n    totally_bogus_method\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)
      finding = findings.find { |f| f.code == "unknown-method" }

      expect(finding).not_to be_nil
      expect(finding.confidence).to eq(:high)
      expect(finding.range[:start][:line]).to eq(2)
    end

    it "does not flag a real Kernel/Object builtin call (resolved through RBS)" do
      document = index("class Widget\n  def show\n    puts \"hi\"\n    freeze\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not flag a call on an Unknown-typed receiver (a method parameter)" do
      document = index("class Widget\n  def show(arg)\n    arg.whatever_unknown\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    # Reversed in 0.2.6, and the old title said why it had to be: it
    # called this "ambiguous". It is not. Neither branch has the method,
    # so the call raises `NoMethodError` whichever branch the value is --
    # confirmed, not uncertain. Ambiguity is the *other* shape, where one
    # branch has it and another does not, and that one is still silent
    # (the example below, and `union_receiver_spec.rb`).
    #
    # The bar a Union clears is stricter than the one a Nominal cleared,
    # not looser: every branch must independently be closed and
    # independently lack the method. Measured over 213 files of real gem
    # source this added nothing -- 34 findings before and after -- so the
    # recall costs no precision there.
    #
    # What it buys: `Order.recent.first.missing` was reported by nothing
    # while `Order.find(id).missing` was reported normally, because
    # `Relation[T]#first` infers `T | nil` and Unions were discarded
    # before anything was asked (`024.77`). `Model.scope.first` is an
    # everyday idiom.
    it "flags a call through a Union receiver when no branch has the method" do
      document = index(<<~RUBY)
        class User
          def name
          end
        end

        class Admin
          def name
          end
        end

        class Owner
          def pick(flag)
            user = flag ? User.new : Admin.new
            user.something_neither_has
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).to include("unknown-method")
    end

    it "still does not flag one when a branch does have the method" do
      document = index(<<~RUBY)
        class User
          def only_user_has_this
          end
        end

        class Admin
        end

        class Owner
          def pick(flag)
            user = flag ? User.new : Admin.new
            user.only_user_has_this
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not flag a call on a receiver whose ancestor chain includes an unresolved external constant" do
      document = index("class Widget < SomeExternalGemBaseClass\n  def show\n    something_the_gem_defines\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not flag a call inside an open, namespaced class just because an unrelated top-level class shares its simple name" do
      # Found by the Task 014-018 independent review's live repro: a
      # closed top-level `Bar` and an open `Api::Bar` (whose real
      # ancestor is an unresolved external gem class) share the simple
      # name "Bar" -- resolving the receiver by simple name alone
      # (the previous behavior) picked the wrong, closed `Bar` and
      # wrongly flagged a call that's only unresolvable because it
      # legitimately comes from the gem.
      document = index(<<~RUBY)
        class Bar
          def known_method
          end
        end

        module Api
          class Bar < SomeExternalGemBaseClass
            def show
              mystery_call_from_the_gem
            end
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not flag an explicit same-named constant call inside a nested namespace as unknown, when it lexically resolves to the enclosing class itself" do
      # Found by the Task 014-018 independent review's follow-up pass:
      # the earlier fix only handled the *implicit*-self shape of this
      # false positive (`ReceiverResolution`'s owner-only fast path) --
      # an *explicit* bare receiver (`Bar.foo`, not just `foo`) written
      # inside `Api::Bar`'s own body needs the same real-Ruby lexical
      # nesting behavior: a bare `Bar` referenced from inside
      # `module Api; class Bar; ...; end; end` resolves to `Api::Bar`
      # itself (via `Api`'s own constant table), never an unrelated
      # top-level `Bar`, even when both exist -- verified live with a
      # real `ruby -e` probe before writing this test.
      document = index(<<~RUBY)
        class Bar
          def known_method
          end
        end

        module Api
          class Bar < SomeExternalGemBaseClass
            def self.show
              Bar.mystery_call_from_the_gem
            end
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "still flags a genuinely unknown call inside a compact-nested class, rather than over-matching it against an unrelated same-named nested class" do
      # Found by the Task 014-018 independent review's third pass: real
      # Ruby's Module.nesting differs between `module Api; class Bar` (two
      # frames: [Api::Bar, Api]) and compact `class Api::V1::Thing`, whose
      # own nesting is `[Api::V1::Thing]` *only* -- it does NOT implicitly
      # include `Api::V1` or `Api`. So a bare `Bar` referenced from inside
      # `class Api::V1::Thing`'s own methods must NOT resolve via `Api`
      # the way it would from inside a *nested*-form `module Api; class
      # Bar`'s own body -- it should fall through to the closed top-level
      # `Bar`, which genuinely has no `totally_bogus_method`. Verified
      # live with real `ruby -e` (raises NoMethodError on the top-level
      # Bar, not Api::Bar) before writing this test.
      document = index(<<~RUBY)
        class Bar
          def known_method
          end
        end

        module Api
          class Bar < SomeExternalGemBaseClass
            def known_method
            end
          end
        end

        class Api::V1::Thing
          def self.show
            Bar.totally_bogus_method
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).to include("unknown-method")
    end

    it "does not flag any call at all when Signatures::Environment isn't available" do
      document = index("class Widget\n  def show\n    puts \"hi\"\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context(signatures: nil), mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "suppresses unknown-method entirely for a class that declares method_missing" do
      document = index(<<~RUBY)
        class Widget
          def method_missing(name, *)
            super
          end

          def show
            anything_dynamic
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    # A workspace file that reopens a class living in a gem is
    # syntactically identical to one that defines it, so the static chain
    # reads [itself, Object, Kernel, BasicObject] -- complete -- and every
    # call into the gem's own API is reported. Every Rails application's
    # test/test_helper.rb has exactly this shape (024.R5).
    describe "a class the workspace reopens rather than defines" do
      # The call is inside a method body rather than written bare in the
      # class body. 0.2.11 briefly made a bare class-body call open the
      # owner's surface on both sides, which would have made a
      # `fixtures :all` fixture silent whatever the ancestry rule
      # decided; that change was rolled back inside the same release, so
      # either spelling works today. This one is kept because it does not
      # depend on which way `024.110` is eventually settled.
      let(:reopened) do
        index(<<~RUBY)
          module ActiveSupport
            class TestCase
              def prepare
                definitely_not_defined_zzz
              end
            end
          end
        RUBY
      end

      let(:ancestry_registry) { Ovallsp::Runtime::AncestryRegistry.new }

      def with_ancestry(**overrides)
        context(ancestry_registry: ancestry_registry, **overrides)
      end

      it "still reports it when no Runtime Agent can be asked" do
        findings = engine.analyze(document: reopened, semantic_context: context, mode: :safe)

        expect(findings.map(&:code)).to include("unknown-method")
      end

      it "stays silent once the application reports ancestors the workspace never declared" do
        ancestry_registry.install(
          object_ancestors: %w[Object Kernel BasicObject],
          classes: { "ActiveSupport::TestCase" =>
            { ancestors: %w[ActiveSupport::TestCase ActiveSupport::Testing::Assertions Object Kernel BasicObject] } }
        )

        findings = engine.analyze(document: reopened, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).not_to include("unknown-method")
      end

      # The distinguishing case for the rule: the same shape of answer,
      # with nothing foreign in it, must leave the check firing. A class
      # the workspace really does define completely carries no ancestors
      # beyond the running Object's.
      it "still reports it when the application confirms the workspace's own ancestry" do
        ancestry_registry.install(
          object_ancestors: %w[Object Kernel BasicObject],
          classes: { "ActiveSupport::TestCase" => { ancestors: %w[ActiveSupport::TestCase Object Kernel BasicObject] } }
        )

        findings = engine.analyze(document: reopened, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).to include("unknown-method")
      end

      # The case the real application needed. `ActiveSupport::TestCase` is
      # never loaded in the environment the Agent boots -- test_helper.rb
      # is the one file that only loads in a different one -- so there is
      # no ancestry to compare, and the autoload registration is what
      # settles it.
      it "stays silent when the class is only registered for autoload, from outside the workspace" do
        ancestry_registry.install(object_ancestors: %w[Object Kernel BasicObject],
                                  classes: { "ActiveSupport::TestCase" => { definedOutsideWorkspace: true } })

        findings = engine.analyze(document: reopened, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).not_to include("unknown-method")
      end

      it "still reports it when the application does not define the class at all" do
        ancestry_registry.install(object_ancestors: %w[Object Kernel BasicObject],
                                  classes: { "ActiveSupport::TestCase" => nil })

        findings = engine.analyze(document: reopened, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).to include("unknown-method")
      end

      # A workspace superclass or concern is not evidence of anything --
      # it is the workspace's own code, which the static chain already
      # walked.
      it "still reports it when every extra ancestor is one the workspace itself declares" do
        index("module Shared\nend\n", uri: "file:///shared.rb")
        ancestry_registry.install(
          object_ancestors: %w[Object Kernel BasicObject],
          classes: { "ActiveSupport::TestCase" => { ancestors: %w[ActiveSupport::TestCase Shared Object Kernel BasicObject] } }
        )

        findings = engine.analyze(document: reopened, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).to include("unknown-method")
      end

      # `include Comparable` is not evidence either: RBS knows what it
      # contributes, and #rbs_resolves? already resolves calls into it.
      it "still reports it when every extra ancestor is one RBS knows" do
        ancestry_registry.install(
          object_ancestors: %w[Object Kernel BasicObject],
          classes: { "ActiveSupport::TestCase" => { ancestors: %w[ActiveSupport::TestCase Comparable Object Kernel BasicObject] } }
        )

        findings = engine.analyze(document: reopened, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).to include("unknown-method")
      end

      # Before the answer arrives, reporting would be a guess -- and it is
      # the guess already known to be wrong for this shape. Silence is the
      # only safe answer, and the question gets asked.
      it "stays silent and asks the application, when an Agent is connected but has not answered yet" do
        ancestry_registry.install(object_ancestors: %w[Object Kernel BasicObject], classes: { "Unrelated" => nil })

        findings = engine.analyze(document: reopened, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).not_to include("unknown-method")
        expect(ancestry_registry.drain_pending).to include("ActiveSupport::TestCase")
      end

      # `::ActiveSupport::TestCase` names the same class as
      # `ActiveSupport::TestCase`. Before the name was normalised these
      # were two registry keys, and the Agent split the prefixed one into
      # an empty first segment and answered "no such constant" -- which is
      # a permanent answer, so the whole fix was defeated for any receiver
      # the user happened to write with a leading `::`.
      #
      # Asserts the diagnostic IS produced, not that it is absent. An
      # absence here is satisfied two ways -- the fix working, or the
      # receiver failing to resolve at all, which is what an unnormalised
      # `::ActiveSupport::TestCase` does (it matches no hierarchy entry, so
      # the check bails before ever reaching the registry). Only a fixture
      # whose answer *differs* between the two tells them apart.
      let(:rooted_receiver) do
        index(<<~RUBY, uri: "file:///rooted.rb")
          module ActiveSupport
            class TestCase
            end
          end

          t = ::ActiveSupport::TestCase.new
          t.fixtures
        RUBY
      end

      it "resolves a root-prefixed receiver against the unprefixed answer" do
        ancestry_registry.install(
          object_ancestors: %w[Object Kernel BasicObject],
          classes: { "ActiveSupport::TestCase" =>
            { ancestors: %w[ActiveSupport::TestCase Object Kernel BasicObject] } }
        )

        findings = engine.analyze(document: rooted_receiver, semantic_context: with_ancestry, mode: :safe)

        # The application confirms the workspace's own ancestry, so the
        # call really is unknown -- and saying so requires having resolved
        # `::ActiveSupport::TestCase` to the same class as the answer.
        expect(findings.map(&:code)).to include("unknown-method")
      end

      it "asks about a root-prefixed receiver under its unprefixed name" do
        ancestry_registry.activate!

        engine.analyze(document: rooted_receiver, semantic_context: with_ancestry, mode: :safe)

        expect(ancestry_registry.drain_pending).to include("ActiveSupport::TestCase")
      end

      it "stays silent for a root-prefixed receiver the application says is foreign" do
        ancestry_registry.install(
          object_ancestors: %w[Object Kernel BasicObject],
          classes: { "ActiveSupport::TestCase" =>
            { ancestors: %w[ActiveSupport::TestCase ActiveSupport::Testing::Assertions Object Kernel BasicObject] } }
        )

        findings = engine.analyze(document: rooted_receiver, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).not_to include("unknown-method")
      end

      # `resolve_type_name` matches by *simple* name, so a workspace module
      # called `Assertions` used to dismiss the gem's
      # `ActiveSupport::Testing::Assertions` as the workspace's own -- one
      # same-named constant anywhere defeats the evidence entirely.
      it "does not accept a workspace constant that merely shares an ancestor's last segment" do
        index("module Assertions\nend\n", uri: "file:///assertions.rb")
        ancestry_registry.install(
          object_ancestors: %w[Object Kernel BasicObject],
          classes: { "ActiveSupport::TestCase" =>
            { ancestors: %w[ActiveSupport::TestCase ActiveSupport::Testing::Assertions Object Kernel BasicObject] } }
        )

        findings = engine.analyze(document: reopened, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).not_to include("unknown-method")
      end

      # The common case, and the one the release is actually about: once
      # `test/test_helper.rb` has reopened `ActiveSupport::TestCase`, that
      # name is workspace-declared, so every test file inheriting from it
      # has a static chain that reaches BasicObject through it. Asking only
      # about the receiver misses that entirely -- the subclass is a
      # genuine workspace class, and the Agent rightly cannot place it.
      it "stays silent for a workspace subclass of a class the workspace only reopened" do
        document = index(<<~RUBY, uri: "file:///subclass_test.rb")
          module ActiveSupport
            class TestCase
            end
          end

          class ProbeTest < ActiveSupport::TestCase
            def test_something
              assert_equal(1, 1)
            end
          end
        RUBY
        ancestry_registry.install(
          object_ancestors: %w[Object Kernel BasicObject],
          classes: { "ActiveSupport::TestCase" => { definedOutsideWorkspace: true }, "ProbeTest" => nil }
        )

        findings = engine.analyze(document: document, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).not_to include("unknown-method")
      end

      # The distinguishing case: a subclass of a class the workspace really
      # does own must still be checked.
      it "still reports on a workspace subclass of a class the workspace really defines" do
        document = index(<<~RUBY, uri: "file:///own_subclass.rb")
          class OwnBase
          end

          class OwnChild < OwnBase
            def run
              totally_bogus_method
            end
          end
        RUBY
        ancestry_registry.install(
          object_ancestors: %w[Object Kernel BasicObject],
          classes: { "OwnBase" => { ancestors: %w[OwnBase Object Kernel BasicObject] },
                     "OwnChild" => { ancestors: %w[OwnChild OwnBase Object Kernel BasicObject] } }
        )

        findings = engine.analyze(document: document, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).to include("unknown-method")
      end

      # 024.13. A container literal is deliberately kept out of this check:
    # a workspace that reopens a core class makes its chain look closed
    # while gems keep adding to it, so admitting these receivers reported
    # ActiveSupport's `[1,2,3].second` and `{}.deep_symbolize_keys` as
    # unknown. Pinned because it is a *change* -- a hash literal inferred
    # as a plain `Hash` before 0.1.9 and was checked -- and because the
    # obvious edit (reading the receiver as its class, which is right
    # everywhere else in the engine) silently undoes it.
    it "does not report an unknown method on a container-literal receiver" do
      document = index(<<~RUBY, uri: "file:///container.rb")
        class Hash
          def deep_keys
          end
        end

        class Widget
          def show
            h = {}
            h.totally_bogus_method
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not count arguments on a container-literal receiver" do
      document = index(<<~RUBY, uri: "file:///arity.rb")
        class Hash
          def deep_dig(a)
          end
        end

        class Widget
          def show
            h = {}
            h.deep_dig(1, 2)
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("argument-count")
    end

    # A round trip to another process is the most expensive test here,
      # so it is asked only of a receiver every cheaper one has already
      # called closed. A model, or anything the static tests rule out,
      # must not queue a question whose answer cannot change the outcome.
      it "does not ask about a receiver the static tests have already ruled open" do
        ancestry_registry.activate!
        document = index(<<~RUBY, uri: "file:///open.rb")
          class OpenThing < SomeExternalGemBaseClass
            def show
              mystery_call_from_the_gem
            end
          end
        RUBY

        engine.analyze(document: document, semantic_context: with_ancestry, mode: :safe)

        expect(ancestry_registry.drain_pending).to be_empty
      end

      it "does not ask about a receiver whose class declares method_missing" do
        ancestry_registry.activate!
        document = index(<<~RUBY, uri: "file:///dynamic.rb")
          class DynamicThing
            def method_missing(name, *)
              super
            end

            def show
              anything_dynamic
            end
          end
        RUBY

        engine.analyze(document: document, semantic_context: with_ancestry, mode: :safe)

        expect(ancestry_registry.drain_pending).to be_empty
      end

      # An inactive registry is a workspace with no Agent at all: an
      # untrusted one, or a plain Ruby project. Deferring there would
      # disable the check permanently, since the answer can never come.
      it "does not ask, and does not defer, when no Agent has ever answered" do
        findings = engine.analyze(document: reopened, semantic_context: with_ancestry, mode: :safe)

        expect(findings.map(&:code)).to include("unknown-method")
        expect(ancestry_registry.drain_pending).to be_empty
      end
    end
  end

  describe "unresolved-constant" do
    it "does not run in :safe mode" do
      document = index("TotallyUnknownConstant.new\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unresolved-constant")
    end

    it "flags a constant that resolves neither in the workspace nor via RBS in :standard mode" do
      document = index("TotallyUnknownConstant.new\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :standard)

      expect(findings.map(&:code)).to include("unresolved-constant")
    end

    it "does not flag a workspace-declared constant" do
      document = index("class Widget\nend\n\nWidget.new\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :standard)

      expect(findings.map(&:code)).not_to include("unresolved-constant")
    end

    it "does not flag an RBS-known stdlib constant" do
      document = index("String.new\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :standard)

      expect(findings.map(&:code)).not_to include("unresolved-constant")
    end
  end

  # `resolve_type_name` answers a bare name by picking among every
  # declared class that ends with it. That is the right trade for
  # completion and for go-to-definition, where a plausible answer beats
  # none -- and the wrong one for a diagnostic, which is asserting
  # something about a class it has not identified. This release put two
  # `Collector`s in this repository's own source and the check reported
  # `SemanticTokens::Collector#tokens`, a method the parser records,
  # because the name resolved to `Observation::Collector`. Recorded as
  # the same cause as 024.19, which reached the argument-type check.
  describe "a bare constant that matches more than one declared class" do
    def two_collectors
      index(<<~RUBY, uri: "file:///observation.rb")
        module Observation
          class Collector
            def start; end
          end
        end
      RUBY
      index(<<~RUBY, uri: "file:///tokens.rb")
        module Tokens
          class Collector
            attr_reader :tokens
            def initialize
              @tokens = []
            end
          end
        end
      RUBY
    end

    it "says nothing about a method on a receiver it had to guess" do
      two_collectors
      document = index("module Tokens\n  def self.collect\n    Collector.new.tokens\n  end\nend\n",
                       uri: "file:///call.rb")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    # The control: one `Collector` in the workspace is not a guess, and
    # the check is still on. Without this the example above passes for a
    # check that has stopped reporting anything.
    # The written name is what the index was asked about, and a name
    # carrying a namespace that resolves to something else entirely is a
    # substitution whether or not two classes are involved. The first
    # version of this guard counted candidates, so `::Vendor::Gadgets::
    # Widget` still resolved to the single workspace `Widget` and every
    # check acted on it. On shipped Ruby: `ripper.lex` in prism's
    # `lex_compat.rb` was reported unknown, because `Ripper::Lexer`
    # resolved to `Prism::Translation::Parser::Lexer`.
    it "says nothing about a qualified name that resolved to a different class" do
      index(<<~RUBY, uri: "file:///widget.rb")
        class Widget
          def start; end
        end
      RUBY
      document = index("Vendor::Gadgets::Widget.new.nope\n", uri: "file:///call.rb")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    # The control, and the reason the rule is about the *name* rather
    # than about qualification: a qualified name the workspace really
    # declares resolved as written, so the check is on.
    it "still reports on a qualified name the workspace declares" do
      index(<<~RUBY, uri: "file:///widget.rb")
        module Vendor
          module Gadgets
            class Widget
              def start; end
            end
          end
        end
      RUBY
      document = index("Vendor::Gadgets::Widget.new.nope\n", uri: "file:///call.rb")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).to include("unknown-method")
    end

    it "still reports when the name matches exactly one declared class" do
      index(<<~RUBY, uri: "file:///tokens.rb")
        module Tokens
          class Collector
            attr_reader :tokens
          end
        end
      RUBY
      document = index("module Tokens\n  def self.collect\n    Collector.new.nope\n  end\nend\n",
                       uri: "file:///call.rb")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).to include("unknown-method")
    end
  end

  # A superclass name resolves through the same last-segment pick as a
  # receiver, so a chain can be about a different class entirely without
  # anything downstream knowing. ActiveRecord 8.1.3 has three classes
  # named `Association`, and `class ThroughAssociation < Association`
  # inside `Preloader` picked the wrong one: `loaded?(owner)` there takes
  # an argument and the one picked takes none, so
  # `preloader/through_association.rb` was reported twice for a correct
  # call.
  describe "an ancestor whose name the index had to guess" do
    PRELOADER = <<~RUBY
      module Preloader
        class Association
          def loaded?(owner); owner; end
        end

        class ThroughAssociation < Association
          def run(owner)
            loaded?(owner)
          end
        end
      end
    RUBY

    it "says nothing about a call resolved through it" do
      index(<<~RUBY, uri: "file:///outer.rb")
        module Outer
          class Association
            def loaded?; end
          end
        end
      RUBY
      document = index(PRELOADER, uri: "file:///preloader.rb")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("argument-count")
    end

    # The control: with only one `Association` in the workspace the
    # superclass resolved as written, and the arity check is still on
    # through the chain -- here against a `loaded?` that really does take
    # none.
    it "still reports through an ancestor that resolved as written" do
      document = index(<<~RUBY, uri: "file:///preloader.rb")
        module Preloader
          class Association
            def loaded?; end
          end

          class ThroughAssociation < Association
            def run(owner)
              loaded?(owner)
            end
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).to include("argument-count")
    end
  end

  # The receiver of a call is looked up by *position*, and the position
  # recorded was one character inside the receiver rather than one past
  # it. `contains?` treats a node's exclusive end offset as inclusive, so
  # the receiver's last character belongs to its own last *element* too --
  # and the walk answers with the innermost node, which is that element.
  #
  # Any receiver whose text ends in `]` or `)` is therefore judged as its
  # own last inner expression. `[w].each` is the plainest case there is,
  # and it reported that a class the workspace wrote has no `each`.
  # Measured over Ruby's standard library, five Rails gems and minitest:
  # 1,545 of 3,362 `unknown-method` reports have a receiver of that shape,
  # 604 of them in prism's `dispatcher.rb` alone (024.20).
  describe "a receiver whose text ends in a bracket" do
    it "says nothing about a method called on an array literal of workspace objects" do
      index("class Widget\n  def known; end\nend\n", uri: "file:///widget.rb")
      document = index(<<~RUBY, uri: "file:///caller.rb")
        class Caller
          def run
            w = Widget.new
            [w].each { |x| x }
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:message)).to be_empty
    end

    # The control: the check is still on for the receiver the call really
    # has. Without this the example above passes for an engine that has
    # stopped looking at bracketed receivers altogether.
    it "still reports an unknown method on the object inside the brackets" do
      index("class Widget\n  def known; end\nend\n", uri: "file:///widget.rb")
      document = index(<<~RUBY, uri: "file:///caller2.rb")
        class Caller2
          def run
            w = Widget.new
            w.definitely_not_here
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:message)).to include(a_string_matching(/definitely_not_here/))
    end
  end

  # Prism is error-tolerant, so a file that does not parse still produces
  # a tree -- one error recovery invented parts of. Running the semantic
  # checks over it reports things nobody wrote: typing a `.` at the end
  # of a method gives `a.end`, and the engine said the class has no
  # method named `end`.
  #
  # A file with a syntax error gets its syntax errors and nothing else.
  # The first thing to fix is the syntax error, and a report derived from
  # a guessed tree is not evidence about anything.
  describe "a document that does not parse" do
    it "reports the syntax error and nothing derived from the recovered tree" do
      document = index(<<~RUBY, uri: "file:///typing.rb")
        class Typing
          def go
            a = Typing.new
            a.
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code).uniq).to eq(["syntax-error"])
    end

    # The control: the same file once it parses. Without this the example
    # above passes for an engine that has stopped checking anything.
    it "still reports on a document that parses" do
      document = index(<<~RUBY, uri: "file:///parses.rb")
        class Parses
          def go
            a = Parses.new
            a.definitely_not_here
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).to include("unknown-method")
    end
  end

  # A workspace class whose simple name is a core class's -- however
  # deeply namespaced -- was answered for the core class itself, because
  # the index resolves a bare name by its last segment and one candidate
  # is not a "guess" by `guessed_type_name?`'s rule.
  #
  # The receiver here comes from a *literal*, so the name reaching the
  # index is bare `String` with nothing to disambiguate it. Hover still
  # answered `upcase() -> String` at the same position, so hover,
  # completion and diagnostics disagreed with each other.
  describe "a workspace class that shares a core class's simple name" do
    it "says nothing about a method called on the core class" do
      index(<<~RUBY, uri: "file:///serializer.rb")
        module Serializer
          module Elements
            class Element; end
            class String < Element; end
          end
        end
      RUBY
      document = index("class Use\n  def run\n    title = \"hello\"\n    title.upcase\n  end\nend\n",
                       uri: "file:///use.rb")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:message)).to be_empty
    end

    # The control: the refusal is about a name the workspace answered for
    # a *core* class, not about the shadowing class itself. With the same
    # file indexed, a call on a workspace class is still checked.
    it "still reports on a workspace class while the shadow is indexed" do
      index(<<~RUBY, uri: "file:///serializer.rb")
        module Serializer
          module Elements
            class Element; end
            class String < Element; end
          end
        end
      RUBY
      index("class Widget\n  def known; end\nend\n", uri: "file:///widget.rb")
      document = index("class Use2\n  def run\n    Widget.new.definitely_not_here\n  end\nend\n",
                       uri: "file:///use2.rb")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:message)).to include(a_string_matching(/definitely_not_here/))
    end
  end

  describe "unknown-route-helper" do
    def load_routes
      route_registry.replace([
                               { name: "widget", verb: "GET", pathTemplate: "/widgets/:id", requiredParts: ["id"],
                                 optionalParts: [], defaults: { controller: "widgets", action: "show" },
                                 sourceLocation: nil, routeSet: "main_app" }
                             ])
    end

    it "flags a bare _path/_url call that matches no known route" do
      load_routes
      document = index("class WidgetsController\n  def show\n    nope_this_route_path(1)\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)
      finding = findings.find { |f| f.code == "unknown-route-helper" }

      expect(finding).not_to be_nil
      expect(finding.confidence).to eq(:high)
    end

    # An empty table is not the same claim as a loaded one that lacks the
    # name. Without an Agent -- an untrusted workspace, or any project
    # that is not Rails -- no snapshot ever arrives, and every method
    # whose name ends `_path`/`_url` was answered "no such route":
    # 8 reports across Ruby's own standard library, every one of them an
    # ordinary method (024.24). 0.2.0 made it worse by publishing for
    # files nobody opened, so a project-wide pass broadcast it.
    it "says nothing when no routes have ever been loaded" do
      document = index("class WidgetsController\n  def show\n    nope_this_route_path(1)\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-route-helper")
    end

    # A Rails application with no named routes at all has a table that is
    # empty *and* loaded, and the check is on there: the distinction is
    # whether a snapshot arrived, not whether it carried anything.
    it "flags an unknown helper against a route table that loaded empty" do
      route_registry.replace([])
      document = index("class WidgetsController\n  def show\n    nope_this_route_path(1)\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).to include("unknown-route-helper")
    end

    it "does not flag a call resolving to a real route helper" do
      route_registry.replace([
                                { name: "widget", verb: "GET", pathTemplate: "/widgets/:id", requiredParts: ["id"],
                                  optionalParts: [], defaults: { controller: "widgets", action: "show" },
                                  sourceLocation: nil, routeSet: "main_app" }
                              ])
      document = index("class WidgetsController\n  def show\n    widget_path(1)\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-route-helper")
    end
  end

  it "truncates the result set when budget: is given" do
    document = index("TotallyUnknownConstant.new\nAnotherOne.new\nYetAnother.new\n")

    findings = engine.analyze(document: document, semantic_context: context, mode: :standard, budget: 1)

    expect(findings.size).to eq(1)
  end
end
