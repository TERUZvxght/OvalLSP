# frozen_string_literal: true

require "stringio"

# `024.85`. `self.` offered nothing, anywhere: `LocalInferencer` had no
# `Prism::SelfNode` case, so completion, hover and go-to-definition all
# asked "what is the type before the dot" and were told Unknown.
#
# What `self` *is* was taken from Ruby rather than reasoned about, because
# two of these answers are not what a reader guesses:
#
#   $ ruby -e '
#   class S
#     def inst; p ["instance method", self.class]; end
#     def self.cls; p ["def self.x", self]; end
#     class << self
#       def sing; p ["def in class << self", self]; end
#       p ["class << self body", self]
#     end
#     def blk; [1].each { p ["block in instance method", self.class] }; end
#     p ["class body", self]
#   end
#   S.new.inst; S.cls; S.sing; S.new.blk
#   p ["top level", self, self.class]
#   '
#   # => ["class << self body", #<Class:S>]
#   # => ["class body", S]
#   # => ["instance method", S]
#   # => ["def self.x", S]
#   # => ["def in class << self", S]
#   # => ["block in instance method", S]
#   # => ["top level", main, Object]
#   # ruby 3.4.10
#
# So: an instance method body is the only place `self` is an *instance*.
# A class body, a `def self.x` body and a `def` written inside
# `class << self` are all the class object -- which this engine spells
# `ClassOf[S]`. A block does not change it. The top level is `main`, an
# ordinary Object with no useful members to offer, and is declined.
#
# A nested `def` is the case a reader gets wrong, and Ruby was asked:
#
#   $ ruby -e '
#   class S
#     class << self
#       def build; def helper; :h; end; end
#     end
#     def self.outer; def inner; :i; end; end
#   end
#   S.build; S.outer
#   p [S.respond_to?(:helper), S.new.respond_to?(:helper)]
#   p [S.respond_to?(:inner), S.new.respond_to?(:inner)]
#   '
#   # => [true, false]
#   # => [false, true]
#   # ruby 3.4.10
#
# The default definee does not change when a method body opens, so
# `helper` is a singleton method (its `self` is the class object) while
# `inner`, written inside `def self.outer`, is an ordinary instance
# method (its `self` is an instance).
RSpec.describe "`self` as a receiver" do
  describe Ovallsp::LocalInferencer do
    # The server's own stack, not a bare `LocalInferencer`. One without
    # `signatures:`/`workspace_index:`/`hierarchy_index:` is a different
    # program, and an example green against it says nothing about the one
    # that ships (`042`'s D8, `024.109`, `024.119`).
    subject(:inferencer) { build_analysis_stack.local_inferencer }

    # The offset just past the receiver written before a dot -- exactly
    # the position `Server#receiver_type_before_dot` asks about when the
    # user has typed `self.`.
    #
    # Anchored on the whole `<receiver>.<message>`, not on the receiver
    # alone: a fixture that contains `def self.outer` also contains the
    # text `self.`, and searching for that queried the *header* while the
    # example claimed to be asking about the body. Both fixtures that
    # needed it caught it by answering Unknown.
    def self_type(source, receiver: "self", message: "foo")
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
      index = source.index("#{receiver}.#{message}")
      raise ArgumentError, "no `#{receiver}.#{message}` in the fixture" unless index

      offset = index + receiver.length
      before = source[0...offset]
      newline = before.rindex("\n")
      position = { line: before.count("\n"), character: offset - (newline ? newline + 1 : 0) }
      inferencer.infer_at(document, position).to_s
    end

    it "is an instance of the enclosing class inside an instance method body" do
      expect(self_type("class W\n  def a\n    self.foo\n  end\nend\n")).to eq("W")
    end

    it "is the class object inside a `def self.x` body" do
      expect(self_type("class W\n  def self.a\n    self.foo\n  end\nend\n")).to eq("ClassOf[W]")
    end

    it "is the class object inside a `def` written in `class << self`" do
      expect(self_type("class W\n  class << self\n    def a\n      self.foo\n    end\n  end\nend\n"))
        .to eq("ClassOf[W]")
    end

    it "is the class object in a class body" do
      expect(self_type("class W\n  self.foo\nend\n")).to eq("ClassOf[W]")
    end

    it "is an instance inside a `def` nested in a `def self.x` body" do
      expect(self_type("class W\n  def self.outer\n    def inner\n      self.foo\n    end\n  end\nend\n")).to eq("W")
    end

    it "is the class object inside a `def` nested in a `def` in `class << self`" do
      source = "class W\n  class << self\n    def build\n      def helper\n        self.foo\n      end\n    end\n  end\nend\n"

      expect(self_type(source)).to eq("ClassOf[W]")
    end

    # The other side of that: a *class* opened inside `class << self` is
    # an ordinary class, and a `def` in it an ordinary instance method.
    # The singleton context does not survive it, which the flag has to be
    # scoped to say:
    #
    #   $ ruby -e '
    #   class W
    #     class << self
    #       class Inner; def a; self; end; end
    #     end
    #   end
    #   inner = W.singleton_class.const_get(:Inner)
    #   p inner.new.a.class == inner
    #   '
    #   # => true
    #   # ruby 3.4.10
    it "is an instance inside a `def` in a class nested in `class << self`" do
      source = "class W\n  class << self\n    class Inner\n      def a\n        self.foo\n      end\n    end\n  end\nend\n"

      expect(self_type(source)).to eq("Inner")
    end

    it "is unchanged inside a block" do
      expect(self_type("class W\n  def a\n    [1].each { self.foo }\n  end\nend\n")).to eq("W")
    end

    it "is the named constant's class object inside a `def Const.x` body" do
      expect(self_type("class W\nend\ndef W.a\n  self.foo\nend\n")).to eq("ClassOf[W]")
    end

    # `main` is an ordinary Object. Offering Object's members for `self.`
    # in a script would be an answer nobody asked for, and asserting
    # about them is worse -- a top-level `def` is a private method of
    # Object that this engine does not attribute to Object at all.
    it "declines at the top level of a file" do
      expect(self_type("self.foo\n")).to eq("Unknown")
    end

    # The same shape a `def self.x` at the top level of a file has: there
    # is no enclosing frame to be the class object of, and `ClassOf[]` --
    # a class object over nothing, which is what wrapping nil renders as
    # -- is not something any reader has a case for.
    it "declines inside a `def self.x` at the top level of a file" do
      expect(self_type("def self.a\n  self.foo\nend\n")).to eq("Unknown")
    end

    it "declines inside a singleton class opened on something other than `self`" do
      expect(self_type("class W\n  obj = Object.new\n  class << obj\n    def a\n      self.foo\n    end\n  end\nend\n"))
        .to eq("Unknown")
    end

    # `def obj.a` names a receiver this engine cannot resolve to a class.
    # Handing back the enclosing one instead is the assertion `024.46`
    # measured 55 false reports of, so the fixture is written inside a
    # class: an implementation that fell back to the enclosing frame
    # would answer `ClassOf[W]` here rather than merely something vague.
    it "declines inside a `def` written on a local variable" do
      expect(self_type("class W\n  obj = Object.new\n  def obj.a\n    self.foo\n  end\nend\n")).to eq("Unknown")
    end

    # `#class` answers the receiver's *class object*, which is the whole
    # of what `ClassOf` is for. Without this, `self` typing as `W` made
    # `self.class` resolve through RBS to `Class` and every workspace
    # class method called on it was reported unknown -- three of the
    # families that got the 0.2.1 attempt reverted.
    it "answers a class object for `#class` on an instance" do
      expect(self_type("class W\n  def a\n    self.class.foo\n  end\nend\n", receiver: "self.class")).to eq("ClassOf[W]")
    end

    it "answers a class object for `#class` on any other receiver" do
      expect(self_type("s = \"x\"\ns.class.foo\n", receiver: "s.class")).to eq("ClassOf[String]")
    end

    # **Declines**, and this example asserted `ClassOf[Class]` until a
    # review round drove it. That answer is right for a class and wrong
    # for a module, and `Types` holds no index and cannot tell which it
    # has:
    #
    #   $ ruby -e '
    #   module M; end
    #   class C; end
    #   p [M.class, C.class, Comparable.class]
    #   '
    #   # => [Module, Class, Module]
    #   # ruby 3.4.10
    #
    # So `M.class` would have answered `Class`. Section 0 ranks a wrong
    # answer below no answer, and nothing regresses by declining: before
    # `024.85` this question had no answer at all.
    it "declines for `#class` on a class object, where it cannot tell a class from a module" do
      expect(self_type("class W\nend\nW.class.foo\n", receiver: "W.class")).to eq("Unknown")
      expect(self_type("module M\nend\nM.class.foo\n", receiver: "M.class")).to eq("Unknown")
    end

    # The remaining branches of `Types.class_of`, each with a fixture
    # whose two candidate answers differ. Ruby, for the three values this
    # engine does not spell as a plain Nominal:
    #
    #   $ ruby -e 'p nil.class; p [1].class; p({ a: 1 }.class)'
    #   # => NilClass
    #   # => Array
    #   # => Hash
    #   # ruby 3.4.10
    it "answers `ClassOf[NilClass]` for `#class` on nil" do
      expect(self_type("x = nil\nx.class.foo\n", receiver: "x.class")).to eq("ClassOf[NilClass]")
    end

    # A container is a `Generic` whose name really is a class, unlike
    # `ClassOf`/`Relation`/`CollectionProxy` -- `Types.base_nominal`
    # already draws that line and this reads it rather than redrawing it.
    it "answers a class object for `#class` on a container" do
      expect(self_type("x = [1]\nx.class.foo\n", receiver: "x.class")).to eq("ClassOf[Array]")
    end

    # A union is answered branch by branch. The nil branch is what makes
    # the fixture distinguishing: `#resolve_call`'s own per-branch
    # fallback drops it, so an implementation that left unions to the
    # caller would answer `ClassOf[String]` alone.
    it "answers about every branch of a union, including the nil one" do
      expect(self_type("x = 1 > 0 ? \"s\" : nil\nx.class.foo\n", receiver: "x.class"))
        .to eq("ClassOf[NilClass] | ClassOf[String]")
    end

    # And it is all-or-nothing: one branch `class_of` cannot name and the
    # whole answer is declined, leaving `#resolve_call` to fall back.
    # Without that rule the declined branch enters `normalize_union` as a
    # bare Ruby nil and renders as an empty member -- ` | ClassOf[String]`
    # -- which is a type nothing downstream can read.
    it "declines whole for a union with a branch it cannot name" do
      expect(self_type("def m(p1)\n  x = 1 > 0 ? p1 : \"s\"\n  x.class.foo\nend\n", receiver: "x.class"))
        .to eq("ClassOf[String]")
    end

    # `#class` is recognised by shape, and the shape is a receiver and
    # nothing else. Ruby distinguishes the two ways of writing more:
    #
    #   $ ruby -e '
    #   s = "x"
    #   p(s.class { })
    #   begin; p s.class(1); rescue ArgumentError => e; p e.class; end
    #   '
    #   # => String
    #   # => ArgumentError
    #   # ruby 3.4.10
    #
    # An argument means it is not `Object#class`; a block is merely
    # ignored, so declining there gives up an answer Ruby would have,
    # which is the safe direction of the two. `Class` rather than
    # Unknown, because ordinary resolution still runs and RBS answers
    # `Class` -- which is exactly the useless answer `Types.class_of`
    # exists to replace for the shape it does recognise. Asserted through
    # a local, because a cursor placed just past a block's `}` is inside
    # the block.
    it "leaves a `class` call carrying arguments or a block to ordinary resolution" do
      expect(self_type("s = \"x\"\nk = s.class(1)\nk.foo\n", receiver: "k")).to eq("Class")
      expect(self_type("s = \"x\"\nk = s.class { }\nk.foo\n", receiver: "k")).to eq("Class")
    end
  end

  # Two evaluators answer `#class`, and a rule either one owned is a rule
  # the other drifts from -- `Types::LiteralTypes` is here because that
  # happened twice, and each time the symptom was this exact pair
  # disagreeing: the expression typed correctly on its own line and lost
  # its type as a method's return.
  #
  # The fixture distinguishes them. A body of `self.class` returns the
  # class object; anything reading it as RBS's `Class` answers `Class`,
  # which is a different string.
  describe "the two evaluators agree about `#class`" do
    # The stack the server gets, not one assembled here: an example built
    # against a differently-wired engine is green against a program that
    # does not ship (`042`'s D8, and the meta spec that enforces it).
    let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
    let(:stack) { build_analysis_stack(workspace_index: workspace_index) }

    let(:source) { "class W\n  def klass\n    self.class\n  end\nend\n" }
    let(:document) { Ovallsp::TextDocument.new(uri: "file:///w.rb", text: source, version: 1, language_id: "ruby") }

    before do
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      stack.hierarchy_index.replace_file(summary)
    end

    it "summarises a method returning `self.class` as the class object" do
      symbol_id = Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::W", name: "klass",
                                               discriminator: nil)

      expect(stack.method_analyzer.summarize(symbol_id: symbol_id).return_type.to_s).to eq("ClassOf[W]")
    end

    it "answers the same for the expression itself" do
      # The end of `self.class` on line 2.
      type = stack.local_inferencer.infer_at(document, { line: 2, character: 14 })

      expect(type.to_s).to eq("ClassOf[W]")
    end
  end

  # Through the server, because the empty popup is what the entry
  # measured. The fixture names an instance method and a class method
  # differently, so each context's answer is distinguishable from the
  # other's rather than merely non-empty.
  describe "completion after `self.`" do
    let(:output) { StringIO.new }
    let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

    def frame(message)
      body = JSON.generate(message)
      "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
    end

    def completion_labels(source, line:, character:)
      input =
        frame(jsonrpc: "2.0", method: "textDocument/didOpen",
              params: { textDocument: { uri: "file:///w.rb", text: source, version: 1, languageId: "ruby" } }) +
        frame(jsonrpc: "2.0", id: 1, method: "textDocument/completion",
              params: { textDocument: { uri: "file:///w.rb" }, position: { line: line, character: character } }) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)
      Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run

      output.rewind
      reader = Ovallsp::IO::FramedReader.new(output)
      messages = []
      begin
        loop { messages << reader.read_message }
      rescue Ovallsp::IO::FramedReader::EOF
        nil
      end
      messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
              .first[:result][:items].map { |item| item[:label] }
    end

    # A `let`, not a constant. A constant written inside `RSpec.describe`
    # is defined at *top level*, so a generic name silently takes another
    # spec file's value depending on load order -- this file's first
    # version named it after the fixture and quietly ran
    # `server_receiverless_spec.rb`'s source instead, passing alone and
    # failing in the whole-directory run. `capabilities_spec.rb` records
    # the same collision from 0.2.x.
    let(:source) do
      "class W\n  def self.build_all\n  end\n  def label\n  end\n  def a\n    self.\n  end\n" \
        "  def self.b\n    self.\n  end\nend\n"
    end

    it "offers the class's instance methods inside an instance method" do
      labels = completion_labels(source, line: 6, character: 9)

      expect(labels).to include("label")
      expect(labels).not_to include("build_all")
    end

    it "offers the class's singleton methods inside a `def self.x` body" do
      labels = completion_labels(source, line: 9, character: 9)

      expect(labels).to include("build_all")
      expect(labels).not_to include("label")
    end
  end

  # The other side of typing `self`: the undefined-method check reads the
  # same inference, so a genuine typo behind `self.` becomes reportable.
  # Every example below carries its own control in the same body, because
  # "nothing is reported" is also what a check that has been switched off
  # wholesale looks like.
  describe "the undefined-method check behind `self.`" do
    let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
    let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
    let(:signatures) { AnalysisStackHelper.shared_signatures }
    let(:stack) do
      build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures)
    end

    def index(text, uri: "file:///a.rb")
      document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      stack.hierarchy_index.replace_file(summary)
      document
    end

    def unknown_methods(document)
      context = Ovallsp::Diagnostics::SemanticContext.new(
        workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
        method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
        model_registry: model_registry, route_registry: Ovallsp::Routes::RouteRegistry.new,
        signatures: signatures, generation: 1
      )
      Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
                                  .select { |f| f.code == "unknown-method" }
                                  .map { |f| f.message[/named `(.+)`/, 1] }
    end

    # **The check says nothing about a written `self`, and these two
    # examples asserted the opposite until the corpus was driven.**
    #
    # `self` typed from the enclosing class body is an *upper bound*:
    # every instance reaching the body may be a subclass that supplies the
    # method. Measured over activesupport-8.1.3.1/lib, 289 files, with
    # `unresolved-constant` held at 827 as the control, admitting a `self`
    # receiver took `unknown-method` from 21 to 30 — all nine new ones
    # `Numeric has no method named `*`` on that gem's own
    # `self * KILOBYTE`, where `*` lives on Integer and Float.
    #
    # `self.labell` really is a typo and really does go unreported now.
    # That is the trade section 0 settles: a missed report rather than a
    # wrong one. The direction that would get both is to ask the
    # *subclasses* rather than the class — recorded rather than built
    # here, because it is a new query and this is a review round.
    it "says nothing about a typo behind `self.`, and nothing about the real method either" do
      document = index("class W\n  def label; :l; end\n  def a\n    self.label\n    self.labell\n  end\nend\n")

      expect(unknown_methods(document)).to be_empty
    end

    it "says nothing behind `self.` even where the ancestor is entirely a workspace one" do
      index("class Base\n  def inherited_one; :i; end\nend\n", uri: "file:///base.rb")
      document = index("class Sub < Base\n  def a\n    self.inherited_one\n    self.inheritedd_one\n  end\nend\n",
                       uri: "file:///sub.rb")

      expect(unknown_methods(document)).to be_empty
    end

    # Family 1 of the 0.2.1 rollback: `self` typed as a Nominal made
    # `self.class` resolve to `Class`, whose chain RBS closes, so every
    # workspace class method reached through it was reported.
    it "says nothing about a class method reached through `self.class`" do
      document = index("class W\n  def self.correct?(v); !v.nil?; end\n  def a\n    self.class.correct?(1)\n  end\nend\n")

      expect(unknown_methods(document)).to be_empty
    end

    # The control for that one: the check has not been switched off for
    # the file, only for a receiver it declines to assert about.
    # The control that keeps the two examples above from being an
    # assertion that cannot fail: the check is switched off for a `self`
    # receiver, not for the file it is written in.
    it "still reports an ordinary typo in the same body as a `self.` call" do
      document = index("class W\n  def self.correct?(v); !v.nil?; end\n  def label; :l; end\n" \
                       "  def a\n    self.class.correct?(1)\n    self.labell\n    " \
                       "W.new.definitely_not_a_member\n  end\nend\n")

      expect(unknown_methods(document)).to eq(["definitely_not_a_member"])
    end
  end
end
