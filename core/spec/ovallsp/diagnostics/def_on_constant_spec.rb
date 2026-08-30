# frozen_string_literal: true

# `024.32`. `def Foo.bar` defines a *singleton* method on `Foo`, and the
# parser recorded an *instance* method -- so both answers inverted: the
# call Ruby runs was reported, and the call Ruby raises on was accepted.
#
#   $ ruby -e '
#   class Foo; end
#   def Foo.bar; end
#   p [Foo.singleton_methods(false), Foo.instance_methods(false)]
#   p (Foo.new.bar rescue $!.class)
#   '
#   # => [[:bar], []]
#   # => NoMethodError
#   # ruby 3.4.10
#
# And the owner was wrong as well as the kind: `def Fetcher.start` written
# *inside* `class Fetcher` was recorded under `::Fetcher::Fetcher`, a
# class that does not exist. Ruby's constant lookup finds the enclosing
# `Fetcher`, because `Fetcher::Fetcher` is not declared.
RSpec.describe "Ovallsp::ParserService and `def Const.name`" do
  def declarations(text)
    Ovallsp::ParserService.new
      .summarize(Ovallsp::TextDocument.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby"))
      .declarations.reject { |d| d.symbol_id.kind == :class || d.symbol_id.kind == :module }
      .map { |d| [d.symbol_id.kind, d.symbol_id.owner, d.symbol_id.name] }
  end

  it "records a singleton method on the named constant" do
    expect(declarations("class Foo\nend\ndef Foo.bar; end\n"))
      .to eq([[:singleton_method, "::Foo", "bar"]])
  end

  # The half round 22 added: `def Fetcher.start` inside `class Fetcher`
  # is the enclosing `Fetcher`, not a nested one that does not exist.
  it "resolves the receiver against the nesting, as Ruby does" do
    expect(declarations("class Fetcher\n  def Fetcher.start; end\nend\n"))
      .to eq([[:singleton_method, "::Fetcher", "start"]])
  end

  # The control, and what an implementation that simply qualified nothing
  # would break: a genuinely nested constant is still nested.
  it "keeps a nested receiver nested when the nesting declares it" do
    expect(declarations("module App\n  class Config\n  end\n  def Config.load; end\nend\n"))
      .to eq([[:singleton_method, "::App::Config", "load"]])
  end

  # And the other control: `def self.x` and a bare `def` are untouched.
  it "leaves def self.x and a bare def alone" do
    expect(declarations("class Foo\n  def self.a; end\n  def b; end\nend\n"))
      .to eq([[:singleton_method, "::Foo", "a"], [:instance_method, "::Foo", "b"]])
  end

  # **A receiver this parser cannot name is not the enclosing class.**
  # `024.251`. `#receiver_owner_name` answers nil for a local-variable
  # receiver, and the `|| current_owner` standing behind it turned "I
  # cannot say" into that class -- inventing a singleton method Ruby
  # attaches to the singleton class of whatever the local holds. The
  # shape is real gem source; the entry reduced it from `rbs`'s runtime
  # prototype generator.
  #
  #   $ ruby -e '
  #   class Runner
  #     def go
  #       ty = Object.new
  #       def ty.tagged_zzz; :from_local; end
  #       ty
  #     end
  #   end
  #   p [Runner.singleton_methods(false), Runner.new.go.tagged_zzz,
  #      Runner.respond_to?(:tagged_zzz), Runner.new.respond_to?(:tagged_zzz)]
  #   '
  #   # => [[], :from_local, false, false]
  #   # ruby 3.4.10
  #
  # The owner is that singleton class, which this parser cannot know, so
  # nothing is recorded -- the same answer a block whose owner cannot be
  # named already gives (`024.31`). `go` beside it is the control:
  # withholding one declaration must not withhold the file's.
  it "records nothing for a `def` on a local-variable receiver" do
    source = "class Runner\n  def go\n    ty = Thing.new\n    def ty.to_s\n      :x\n    end\n    ty\n  end\nend\n"

    expect(declarations(source)).to eq([[:instance_method, "::Runner", "go"]])
  end

  # A local variable is not the only receiver `def` accepts and this
  # parser cannot name. Both of these parse, and both landed on
  # `::Runner`.
  #
  #   $ ruby -e '
  #   src = ["class R; def go; def build_it.a; end; end; end",
  #          "class R; def go; def @thing.b; end; end; end"]
  #   p src.map { |s| RubyVM::InstructionSequence.compile(s) ? :parses : nil }
  #   '
  #   # => [:parses, :parses]
  #   # ruby 3.4.10
  it "records nothing for a `def` on any unnameable receiver expression" do
    expect(declarations("class Runner\n  def go\n    def build_it.a; end\n  end\nend\n"))
      .to eq([[:instance_method, "::Runner", "go"]])
    expect(declarations("class Runner\n  def go\n    def @thing.b; end\n  end\nend\n"))
      .to eq([[:instance_method, "::Runner", "go"]])
  end

  # **What declining costs, stated as the interpreter states it.** A
  # `def` written *inside* such a body really does land on the lexically
  # enclosing class, because Ruby's default definee there is the cref:
  #
  #   $ ruby -e '
  #   class Runner
  #     def go
  #       ty = Object.new
  #       def ty.outer_zzz
  #         def inner_zzz; :inner; end
  #         :outer
  #       end
  #       ty
  #     end
  #   end
  #   obj = Runner.new.go
  #   obj.outer_zzz
  #   p [Runner.instance_methods(false).sort, obj.singleton_class.instance_methods(false)]
  #   '
  #   # => [[:go, :inner_zzz], [:outer_zzz]]
  #   # ruby 3.4.10
  #
  # `inner_zzz` is declined too rather than recorded on `::Runner`, and
  # that is the one shape where declining gives up a true answer. It is
  # given up because keeping it means keeping the owner that produces the
  # false reports the diagnostics example below measures, and because
  # "nothing written here can be attributed" is already what a block
  # whose owner cannot be named answers.
  it "declines a `def` nested inside a `def` on an unnameable receiver" do
    source = "class Runner\n  def go\n    ty = Thing.new\n    def ty.outer\n      def inner; end\n    end\n  end\nend\n"

    expect(declarations(source)).to eq([[:instance_method, "::Runner", "go"]])
  end

  # **Declining a declaration must not decline a scope.** A `def` written
  # inside an unnameable body is walked by the path that records nothing,
  # and that path still has to open a local-variable frame of its own:
  # without one, the two `z`s below land in a single `owner#scope_id`,
  # which is the key Find References and Rename are built on -- so
  # renaming either would rewrite both.
  #
  # The fixture is built to tell those two answers apart. `inner_a` and
  # `inner_b` are siblings, so a frame each puts their `z`s in two scopes
  # and no frame at all puts them in one; a single nested `def` cannot
  # distinguish them, because the enclosing `def ty.outer` opens a frame
  # regardless. The two `q`s in the sibling methods are the control.
  it "gives each declined `def` inside an unnameable body a scope of its own" do
    source = <<~RUBY_SRC
      class Runner
        def go
          ty = Thing.new
          def ty.outer
            def inner_a
              z = 1
              z
            end

            def inner_b
              z = 2
              z
            end
          end
          w = 3
          w
        end

        def first
          q = 4
          q
        end

        def second
          q = 5
          q
        end
      end
    RUBY_SRC

    summary = Ovallsp::ParserService.new
                                    .summarize(Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source,
                                                                         version: 1, language_id: "ruby"))
    locals = summary.reference_candidates.select { |c| c.kind == :local_variable }
    scopes = locals.group_by(&:name).transform_values { |c| c.map(&:scope_id).uniq }

    # The two declined `def`s are two scopes, not one.
    expect(scopes.fetch("z").length).to eq(2)
    # `w` is written in the enclosing method, so it is one frame and not
    # either of theirs.
    expect(scopes.fetch("w").length).to eq(1)
    expect(scopes.fetch("w") & scopes.fetch("z")).to be_empty
    # And the two `q`s are in different methods, so they must not share.
    expect(scopes.fetch("q").length).to eq(2)
    expect(locals.map(&:scope_id)).to all(be_a(Integer))
  end

  # **`def <local>.included` is not the enclosing module's hook.** The
  # parser binds the parameter of a singleton `included`/`prepended` so
  # that a `base.extend(…)` in its body is recognisable as a Concern
  # arranging class methods for whoever includes it -- and inside an
  # unnameable body that reading is wrong twice over: the object whose
  # singleton carries the method is not the module, and nobody including
  # the module ever calls it.
  #
  #   $ ruby -e '
  #   module Helpers; def helper_zzz; :h; end; end
  #   module M
  #     def self.build
  #       ty = Object.new
  #       def ty.included(base)
  #         base.extend(Helpers)
  #       end
  #       ty
  #     end
  #   end
  #   M.build
  #   class C; include M; end
  #   p [C.respond_to?(:helper_zzz), M.singleton_class.instance_methods(false)]
  #   '
  #   # => [false, [:build]]
  #   # ruby 3.4.10
  #
  # It was recorded against `::M`, which is a chain edge the module does
  # not have; nothing is recorded now. The same file's real Concern is
  # the control -- withholding this fact must not withhold that one.
  it "records no concern hook for an `included` written on an unnameable receiver" do
    source = <<~RUBY_SRC
      module M
        def go
          ty = Thing.new
          def ty.included(base)
            base.extend(Helpers)
          end
          ty
        end
      end

      module Real
        def self.included(base)
          base.extend(RealHelpers)
        end
      end
    RUBY_SRC

    summary = Ovallsp::ParserService.new
                                    .summarize(Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source,
                                                                         version: 1, language_id: "ruby"))
    hooks = summary.ancestor_facts.select { |f| f.relation == :concern_class_methods }

    expect(hooks.map { |f| [f.owner, f.target] }).to eq([["::Real", "RealHelpers"]])
  end
end

# The other half of the same defect, and where a user sees it: `self`
# inside `def <local>.m` is the object the local holds, so a receiverless
# call written there is a call on *that* and not on the enclosing class.
# With the body attributed to the enclosing class, ordinary working code
# was reported (`024.251`).
RSpec.describe "Ovallsp::Diagnostics::Engine and a `def` on an unnameable receiver" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) do
    build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures)
  end
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }

  def unknown_methods(text)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
      method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
      model_registry: model_registry, route_registry: Ovallsp::Routes::RouteRegistry.new,
      signatures: signatures, generation: 1
    )
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
                                .select { |finding| finding.code == "unknown-method" }
                                .map { |finding| finding.message[/named `(.+)`/, 1] }
  end

  # The typo in the sibling method is the control: this has to be the
  # unnameable body falling silent, not the check falling silent. A fix
  # that opened the whole class's surface drops both names and would pass
  # a bare "reports nothing".
  it "says nothing about a receiverless call inside `def <local>.method`" do
    source = <<~RUBY_SRC
      class Runner
        def go
          ty = Thing.new
          def ty.to_s
            location or raise
            location.source
          end
          ty
        end

        def control_typo
          definitely_not_a_member_zzz
        end
      end
    RUBY_SRC

    expect(unknown_methods(source)).to eq(["definitely_not_a_member_zzz"])
  end
end
