# frozen_string_literal: true

# `024.106`. `module_function` and `extend self` are the two everyday
# ways of writing a module whose methods you call on the module, and
# neither produced anything: `MF.` completed 190 items with no `mf_a`
# among them. `def self.x` and `class << self` in a module already
# worked, so it is these two idioms specifically.
#
# Ground truth, taken from the interpreter rather than from memory:
#
#   $ ruby -e '
#   module MF
#     module_function
#     def mf_a; end
#   end
#   module MF2
#     def mf_c; end
#     def mf_d; end
#     module_function :mf_c
#   end
#   module ES
#     extend self
#     def es_a; end
#   end
#   p [MF.respond_to?(:mf_a), MF.private_instance_methods(false)]
#   #   => [true, [:mf_a]]
#   p [MF2.respond_to?(:mf_c), MF2.respond_to?(:mf_d)]
#   #   => [true, false]
#   p [MF2.instance_methods(false), MF2.private_instance_methods(false)]
#   #   => [[:mf_d], [:mf_c]]
#   p [ES.respond_to?(:es_a), ES.instance_methods(false)]
#   #   => [true, [:es_a]]
#   '
#   # ruby 3.4.10
#
# Two different shapes, which is why they are fixed differently:
# `module_function` copies each method to the singleton side and makes
# the instance copy *private*; `extend self` adds no methods at all, it
# puts the module in its own singleton chain.
RSpec.describe "Ovallsp::ParserService and module-level self-calling idioms" do
  def summarize(text)
    Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: "file:///mf.rb", text: text, version: 1, language_id: "ruby")
    )
  end

  def declared(summary, kind)
    summary.declarations.select { |d| d.symbol_id.kind == kind }
           .map { |d| [d.symbol_id.name, d.visibility] }.sort
  end

  describe "a bare module_function" do
    let(:summary) { summarize("module MF\n  module_function\n  def mf_a; end\n  def mf_b; end\nend\n") }

    it "puts every method after it on the module's singleton side" do
      expect(declared(summary, :singleton_method).map(&:first)).to eq(%w[mf_a mf_b])
    end

    it "makes the instance copy private, which is what stops it being offered on an instance" do
      expect(declared(summary, :instance_method)).to eq([["mf_a", :private], ["mf_b", :private]])
    end
  end

  # Ruby keeps *one* scope-visibility value, so `public`/`private` after a
  # `module_function` replaces it; two independent flags do not:
  #
  #   $ ruby -e '
  #   module M; module_function; public; def x; end; end
  #   p [M.respond_to?(:x), M.public_instance_methods(false)]  # => [false, [:x]]
  #   module MFP; module_function; def a; end; private; def b; end; end
  #   p [MFP.respond_to?(:a), MFP.respond_to?(:b)]             # => [true, false]
  #   module P; module_function; def a; def b; end; end; end
  #   P.a; p P.respond_to?(:b)                                 # => false
  #   '
  #   # ruby 3.4.10
  describe "what cancels module_function" do
    it "is cancelled by a following public" do
      summary = summarize("module M\n  module_function\n  public\n  def x; end\nend\n")

      expect(declared(summary, :singleton_method)).to be_empty
      expect(declared(summary, :instance_method)).to eq([["x", :public]])
    end

    it "is cancelled by a following private" do
      summary = summarize("module MFP\n  module_function\n  def a; end\n  private\n  def b; end\nend\n")

      expect(declared(summary, :singleton_method).map(&:first)).to eq(["a"])
      expect(declared(summary, :instance_method)).to eq([["a", :private], ["b", :private]])
    end

    it "does not reach a def written inside another def" do
      summary = summarize("module P\n  module_function\n  def a\n    def b; end\n  end\nend\n")

      expect(declared(summary, :singleton_method).map(&:first)).to eq(["a"])
    end

    # Ruby raises `NameError: undefined local variable or method
    # 'module_function' for class CMF`, so a class body writing it is
    # broken code and the engine must not invent a module method from it.
    it "is not applied in a class body, where Ruby does not have it" do
      summary = summarize("class CMF\n  module_function\n  def a; end\nend\n")

      expect(declared(summary, :singleton_method)).to be_empty
      expect(declared(summary, :instance_method)).to eq([["a", :public]])
    end
  end

  # `module_function def a; end` is the inline form, and it recorded
  # nothing at all -- `apply_module_function_arguments` ran before the
  # `def` was visited, and reads symbols rather than definitions anyway.
  # Rails writes it: `action_cable.rb:77` is `module_function def server`,
  # and `ActionCable.server` was reported as missing.
  #
  #   $ ruby -e '
  #   module MF1; module_function def a; end
  #     def b; end
  #   end
  #   p [MF1.respond_to?(:a), MF1.private_instance_methods(false), MF1.instance_methods(false)]
  #   '
  #   # => [true, [:a], [:b]]
  #   # ruby 3.4.10
  describe "the inline module_function def form" do
    let(:summary) { summarize("module MF1\n  module_function def a; end\n  def b; end\nend\n") }

    it "records the module method" do
      expect(declared(summary, :singleton_method).map(&:first)).to eq(["a"])
    end

    it "makes only that one private, and leaves the sibling alone" do
      expect(declared(summary, :instance_method)).to eq([["a", :private], ["b", :public]])
    end
  end

  # `024.114`. `module_function :name` names methods that may be declared
  # in a *different file* -- which is what the by-name form is for, since
  # the section form covers the same-file case. The recorder ran over the
  # per-file visitor accumulator, so cross-file never worked and
  # `Reopened.r_a` was reported as missing:
  #
  #   $ ruby -e '
  #   module Reopened; def r_a; :a; end; end
  #   module Reopened; module_function :r_a; end
  #   p [Reopened.r_a, Reopened.private_instance_methods(false)]
  #   '
  #   # => [:a, [:r_a]]
  #   # ruby 3.4.10
  #
  # Recorded as a fact the index applies once every file is in, the way
  # `AncestorFact` already is, rather than as a rewrite the parser
  # performs on what it happens to have seen.
  describe "module_function naming a method declared in another file" do
    it "makes the module method reachable" do
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index)
      hierarchy_index = stack.hierarchy_index
      [["file:///a.rb", "module Reopened\n  def r_a; end\nend\n"],
       ["file:///b.rb", "module Reopened\n  module_function :r_a\nend\n"]].each do |uri, text|
        summary = Ovallsp::ParserService.new.summarize(
          Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
        )
        workspace_index.replace_file(summary)
        hierarchy_index.replace_file(summary)
      end
      resolver = stack.method_resolver

      candidates = resolver.resolve(receiver_type: Ovallsp::Types::Nominal.new(name: "Reopened"),
                                    name: "r_a", context: { singleton: true })

      expect(candidates.map { |c| c.symbol_id.name }).to eq(["r_a"])
    end

    # **The count has to come back down when the file goes away.** The
    # decrement in `remove_file_locked` was unpinned: reverting it leaks a
    # `module_function` across a re-index, so a module keeps a class-level
    # method after the line that made it was deleted, and nothing failed.
    it "forgets the module method when the file naming it is removed" do
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index)
      hierarchy_index = stack.hierarchy_index
      [["file:///a.rb", "module Reopened\n  def r_a; end\nend\n"],
       ["file:///b.rb", "module Reopened\n  module_function :r_a\nend\n"]].each do |uri, text|
        summary = Ovallsp::ParserService.new.summarize(
          Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
        )
        workspace_index.replace_file(summary)
        hierarchy_index.replace_file(summary)
      end
      expect(workspace_index.method_symbol_ids("Reopened", kind: :singleton_method).map(&:name)).to eq(["r_a"])

      workspace_index.remove_file("file:///b.rb")

      expect(workspace_index.method_symbol_ids("Reopened", kind: :singleton_method)).to be_empty
    end

    # The control: a name it does not mention stays off the module. An
    # implementation that put every instance method on the singleton side
    # once any `module_function` appeared would pass the example above.
    it "leaves a method it does not name alone" do
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index)
      hierarchy_index = stack.hierarchy_index
      [["file:///a.rb", "module Reopened\n  def r_a; end\n  def r_b; end\nend\n"],
       ["file:///b.rb", "module Reopened\n  module_function :r_a\nend\n"]].each do |uri, text|
        summary = Ovallsp::ParserService.new.summarize(
          Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
        )
        workspace_index.replace_file(summary)
        hierarchy_index.replace_file(summary)
      end
      resolver = stack.method_resolver

      expect(resolver.resolve(receiver_type: Ovallsp::Types::Nominal.new(name: "Reopened"),
                              name: "r_b", context: { singleton: true })).to be_empty
    end
  end

  describe "module_function with names" do
    let(:summary) do
      summarize("module MF2\n  def mf_c; end\n  def mf_d; end\n  module_function :mf_c\nend\n")
    end

    # The distinguishing half: `mf_d` is *not* named, so it stays a public
    # instance method and off the singleton side entirely. An
    # implementation that treated the argument form as the bare form
    # would pass the first assertion and fail this one.
    it "moves only the methods it names" do
      expect(declared(summary, :singleton_method).map(&:first)).to eq(["mf_c"])
      expect(declared(summary, :instance_method)).to eq([["mf_c", :private], ["mf_d", :public]])
    end
  end

  # Ruby has no `extend self` in a class body -- `self` there is a Class,
  # and `Module#extend` wants a Module:
  #
  #   $ ruby -e 'class ESC; extend self; end'
  #   # => wrong argument type Class (expected Module) (TypeError)
  #   # ruby 3.4.10
  #
  # So a class writing it is broken code, and the engine must not record
  # an ancestor edge that Ruby refuses to make.
  it "does not record extend self in a class body, where Ruby raises" do
    summary = summarize("class ESC\n  extend self\n  def a; end\nend\n")

    expect(summary.ancestor_facts.map { |f| [f.owner, f.relation, f.target] }).to be_empty
  end

  describe "extend self" do
    let(:summary) { summarize("module ES\n  extend self\n  def es_a; end\nend\n") }

    # No singleton declaration: Ruby adds no methods here, it puts the
    # module in its own singleton chain, and the methods stay public
    # instance methods. Recording a singleton copy would answer the same
    # completion question by the wrong means and would be wrong about
    # `ES.instance_methods(false)`.
    # **Ruby names it twice, and they are two different things:**
    #
    #   $ ruby -e 'module ES; extend self; def es_a; end; end
    #              p ES.singleton_class.ancestors.first(3)'
    #   # => [#<Class:ES>, ES, Module]
    #   # ruby 3.4.10
    #
    # The singleton class supplies `def self.` methods; the module
    # supplies its instance methods, which is what `extend self` is for.
    # This index writes both under the name `"::ES"` and tells them apart
    # by `origin`. An earlier version of this example asserted the chain
    # listed the name once -- round 2's reading -- and the dedupe written
    # to satisfy it switched `extend self` off entirely.
    it "lists each side of itself once in its own singleton chain" do
      summary = Ovallsp::ParserService.new.summarize(
        Ovallsp::TextDocument.new(uri: "file:///es.rb", version: 1, language_id: "ruby",
                                   text: "module ES\n  extend self\n  def es_a; end\nend\n")
      )
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index)
      hierarchy_index = stack.hierarchy_index
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)

      links = hierarchy_index.ancestors("::ES", singleton: true)
                             .map { |e| [e.name, e.declaration_kind(singleton: true)] }

      expect(links).to eq(links.uniq)
      expect(links.first(2)).to eq([["::ES", :singleton_method], ["::ES", :instance_method]])
    end

    # **The question the other examples here do not ask.** They assert the
    # ancestor fact is recorded and that the chain lists each name once,
    # and both stayed true while `#dedupe_named` -- added to fix the
    # duplicate -- silently cancelled the whole feature: `ES.es_a`
    # stopped resolving, and `ActiveSupport::Inflector.pluralize` lost
    # hover, go-to-definition and completion and gained a false report.
    # 0.2.9 answered it correctly. `024.109`'s own category, in this
    # release's own new spec.
    it "answers about a method reached through extending itself" do
      summary = Ovallsp::ParserService.new.summarize(
        Ovallsp::TextDocument.new(uri: "file:///es.rb", version: 1, language_id: "ruby",
                                   text: "module ES\n  extend self\n  def es_a; end\nend\n")
      )
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index)
      hierarchy_index = stack.hierarchy_index
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)
      resolver = stack.method_resolver

      candidates = resolver.resolve(receiver_type: Ovallsp::Types::Nominal.new(name: "ES"),
                                    name: "es_a", context: { singleton: true })

      expect(candidates.map { |c| c.symbol_id.name }).to eq(["es_a"])
    end

    it "records the module extending itself, and leaves the methods where they are" do
      expect(declared(summary, :instance_method)).to eq([["es_a", :public]])
      expect(declared(summary, :singleton_method)).to be_empty
      expect(summary.ancestor_facts.map { |f| [f.owner, f.relation, f.target] })
        .to include(["::ES", :extend, "::ES"])
    end
  end
end

# The other half of `024.106`: **nothing checked a module's class-level
# calls at all.** `PlainClass.nope_y` was reported and `PlainMod.nope_x`
# was not, on a module whose `def self.` methods the engine does know.
#
# The cause was one line asking every receiver's *instance* chain to
# reach `::BasicObject` before anything may be asserted about it. A
# module's does not, and correctly so:
#
#   $ ruby -e '
#   module PlainMod; def self.known; end; end
#   p PlainMod.ancestors                          # => [PlainMod]
#   p (PlainMod.nope_x rescue $!.class)           # => NoMethodError
#   '
#   # ruby 3.4.10
RSpec.describe "Ovallsp::Diagnostics::Engine and a module's class-level calls" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:method_resolver) { stack.method_resolver }
  let(:local_inferencer) { stack.local_inferencer }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }

  def index(text, uri:)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  def unknown_methods(document)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
                                .select { |f| f.code == "unknown-method" }
                                .map { |f| f.message[/named `(.+)`/, 1] }
  end

  before do
    index("module PlainMod\n  def self.known; end\nend\n", uri: "file:///pm.rb")
    index("class PlainClass\n  def self.known; end\nend\n", uri: "file:///pc.rb")
  end

  # **The mixin contract, which is what makes the module short-circuit a
  # singleton-only rule.** `self` inside a module's instance method is an
  # object of the *including* class, whose chain does reach `Kernel` and
  # `BasicObject` -- so the module's own two-entry chain says nothing
  # about it. Judging the instance side by it reported `Kernel#raise` and
  # `Kernel#puts` as missing on shipped Rails source: 21 -> 249
  # `unknown-method` findings over 172 files of actioncable, activejob and
  # activemodel.
  #
  #   $ ruby -e '
  #   module Helper
  #     def helped(x)
  #       raise ArgumentError, "no" unless x
  #       provided_by_includer
  #     end
  #   end
  #   class User
  #     include Helper
  #     def provided_by_includer = :ok
  #   end
  #   p User.new.helped("ok")   # => :ok
  #   '
  #   # ruby 3.4.10
  it "says nothing about a module's instance method calling Kernel or the includer" do
    document = index(<<~RUBY_SRC, uri: "file:///helper.rb")
      module Helper
        def helped(x)
          raise ArgumentError, "no" unless x
          puts x
          provided_by_includer
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to be_empty
  end

  # **Rolled back in 0.2.10's third round, and this example records what
  # it was.** Making the module's own chain count as complete reported
  # `Rails.application`, `Rails.env` and five more as missing, because
  # `module Rails` reopened by two generator files was enough to make the
  # workspace call it "declared". Measured: 41 findings added, 0 removed,
  # all 41 false, control identical. So a module's class-level typo is
  # *not* reported, which is `024.106`'s second half, open again.
  it "does not report a typo on a module, which a class-level typo still is" do
    document = index("PlainMod.nope_x\nPlainClass.nope_y\n", uri: "file:///use.rb")

    expect(unknown_methods(document)).to contain_exactly("nope_y")
  end

  # The control: the methods that *are* there stay silent, on both.
  it "says nothing about the calls that work" do
    document = index("PlainMod.known\nPlainClass.known\n", uri: "file:///ok.rb")

    expect(unknown_methods(document)).to be_empty
  end
end
