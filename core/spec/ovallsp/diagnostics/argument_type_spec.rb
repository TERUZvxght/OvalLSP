# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# Argument *type* checking (0.2.0, closes 024.R2).
#
# 0.1.6 added an argument *count* check. Nothing looked at what the
# arguments actually were, so passing a String where an Integer is
# declared went unreported.
#
# The standard is the one the count check was held to: a wrong "expected
# Integer, got String" on code that runs is worse than saying nothing. So
# this reports only where the expected type is *stated* rather than
# inferred -- an RBS/RBI-declared parameter -- and only when the
# argument's own inferred type is a concrete class that cannot be one.
RSpec.describe "Ovallsp::Diagnostics::Engine argument type checking (0.2.0)" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  # A project `sig/` rather than stdlib, because the fixtures need to say
  # exactly what is declared. Everything the check reads comes through the
  # same Signatures::Environment either way.
  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "fixtures.rbs"), signature_source)
      @workspace_root = root
      example.run
    end
  end

  let(:signature_source) do
    <<~RBS
      class Widget
        def resize: (Integer size) -> void
        def label: (String text) -> void
        def anything: (int size) -> void
        def either: (Integer | String size) -> void
        def many: (String label, *Integer sizes) -> void
        def attach: (Widget other) -> void
        def pair: (String first, Integer second) -> void
        def zoom: (Float factor) -> void
        def hold: (Object value) -> void
        def each_thing: () { () -> void } -> Widget
        def >: (Widget other) -> bool
        def rotate: (Complex turns) -> void
        def divide: (Rational parts) -> void
        def pick: [T] (Array[T] items, Integer count) -> T
        def scale: (Numeric factor) -> void
        def handle: (Exception error) -> void
        def flag: (bool value) -> void
        def outline: (Shape item) -> void
        def slice: (Integer at) -> void
                 | (String at) -> void
        def span: (String first, ?Integer middle, Symbol last) -> void
      end

      class Shape
      end
    RBS
  end

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) do
    Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
  end
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) do
    Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: @workspace_root) }
  end
  let(:local_inferencer) do
    Ovallsp::LocalInferencer.new(
      model_registry: model_registry, method_resolver: method_resolver, signatures: signatures,
      method_analyzer: Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver,
        summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
    )
  end
  let(:route_registry) { Ovallsp::Routes::RouteRegistry.new }

  def context
    Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry, route_registry: route_registry,
      signatures: signatures, generation: 1
    )
  end

  def index(text, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  # The class exists in source too, so the receiver resolves; the
  # *signature* is what declares the parameter types.
  # The same shape as `findings`, with the signature coming from an RBI
  # rather than an RBS -- which is the difference the two examples above
  # turn on.
  def rbi_findings(body, rbi: <<~RBI)
    class Cage
      sig { params(a: Animal).void }
      def hold(a); end
    end
  RBI
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sorbet/rbi"))
      File.write(File.join(root, "sorbet/rbi/cage.rbi"), rbi)
      rbi_signatures = Ovallsp::Signatures::Environment.new
      rbi_signatures.load(workspace_root: root)
      rbi_context = Ovallsp::Diagnostics::SemanticContext.new(
        workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
        local_inferencer: local_inferencer, model_registry: model_registry, route_registry: route_registry,
        signatures: rbi_signatures, generation: 1
      )
      engine.analyze(document: index(body), semantic_context: rbi_context, mode: :standard)
            .select { |f| f.code == "argument-type" }
    end
  end

  def findings(body)
    index("class Widget\nend\n", uri: "file:///widget.rb")
    engine.analyze(document: index(body), semantic_context: context, mode: :standard)
          .select { |f| f.code == "argument-type" }
  end

  # Pre-existing, found while building the type check on the same lookup:
  # `HierarchyIndex` reports the class's own entry already qualified
  # (`::Widget`), so prefixing it again asked for `::::Widget` and found
  # nothing. The consequence is a false "has no method named" for anything
  # a project declares in its own `sig/` without also writing it in Ruby --
  # exactly the report this check exists to avoid making.
  it "does not call a method unknown when the project's own sig/ declares it" do
    index("class Widget\nend\n", uri: "file:///widget.rb")
    document = index("Widget.new.resize(3)\n")

    unknown = engine.analyze(document: document, semantic_context: context, mode: :standard)
                    .select { |f| f.code == "unknown-method" }

    expect(unknown).to be_empty
  end

  it "reports a String passed where the signature declares an Integer" do
    result = findings(<<~RUBY)
      Widget.new.resize("large")
    RUBY

    expect(result.size).to eq(1)
    expect(result.first.message).to include("Integer").and include("String")
  end

  # Ruby's numeric tower is not its class hierarchy: `Integer` is not a
  # `Float`, but `scale(2)` where a Float is declared is ordinary working
  # code -- Ruby coerces, and every arithmetic operation the method can
  # perform accepts both. Reporting it is the wrong-report-on-code-that-
  # runs this check refuses to make.
  it "says nothing about an Integer passed where a Float is declared" do
    expect(findings("Widget.new.zoom(2)")).to be_empty
  end

  # `Complex` and `Rational` are on the same table as `Float` and were
  # there on the strength of one spec covering `Float` alone.
  it "says nothing about an Integer passed where a Complex is declared" do
    expect(findings("Widget.new.rotate(2)")).to be_empty
  end

  it "says nothing about an Integer passed where a Rational is declared" do
    expect(findings("Widget.new.divide(2)")).to be_empty
  end

  # The other direction stays reported: a Float where an Integer is
  # declared is the one a `String#*` or an array index actually breaks on.
  it "still reports a Float passed where an Integer is declared" do
    expect(findings("Widget.new.resize(1.5)").size).to eq(1)
  end

  # `infer_at` is asked for the type at the argument's *end* offset, and
  # the innermost node containing that offset is the right operand of any
  # binary expression -- not the argument. `"=" * 80` is a String and was
  # reported as an Integer. Ordinary, working Ruby.
  {
    "a repeated string" => 'Widget.new.label("=" * 80)',
    "an indent expression" => 'Widget.new.label("  " * 2)',
    "a sum" => 'Widget.new.label("a" + "b" * 2)'
  }.each do |description, call|
    it "says nothing about #{description}" do
      expect(findings(call)).to be_empty
    end
  end

  # Enumerating operators cannot be finished: `<=>`, `==`, `..`, `&&`,
  # `!` and a dozen others all put a different node at the argument's end
  # offset. `"a" <=> "b"` is an Integer and was reported as a String.
  {
    "a comparison" => 'Widget.new.label("a" <=> "b")',
    "a range" => "Widget.new.label(1..5)",
    "a negation" => "Widget.new.label(!1)",
    "a conjunction" => "Widget.new.label(1 && 2)",
    "a ternary" => 'Widget.new.label(1 > 2 ? "a" : 7)',
    "a modifier unless" => 'Widget.new.label(("a" unless 1 > 2))',
    "a shift" => "Widget.new.label([] << 1)"
  }.each do |description, call|
    it "says nothing about #{description}" do
      expect(findings(call)).to be_empty
    end
  end

  # A generic declared parameter is declined: `Array[T]` is not a plain
  # class, and "an Integer cannot be an Array[T]" is a question this
  # narrow version does not answer.
  it "says nothing when the declared parameter type is generic" do
    expect(findings("Widget.new.pick(1, 2)")).to be_empty
  end

  # An RBI-declared parameter type has no RBS ancestry to fall back on:
  # `Environment#ancestors` is RBS-only and answers nothing for it. The
  # workspace chain arrives `::`-qualified, so a class was reported as
  # incompatible with *itself* -- eleven times over the `rbs` gem's own
  # source. Both the row and KNOWN_LIMITATIONS say "RBS/RBI".
  it "says nothing when an RBI-declared parameter type is passed itself" do
    index("class Animal\nend\n", uri: "file:///animal.rb")
    index("class Cage\nend\n", uri: "file:///cage.rb")

    expect(rbi_findings("Cage.new.hold(Animal.new)\n")).to be_empty
  end

  # Namespaced, so stripping the leading `::` is not enough: the RBI side
  # names the type `Animal`, and `::Zoo::Animal` has to reach that.
  it "says nothing when a namespaced class is passed to its own RBI declaration" do
    index("module Zoo\n  class Animal\n  end\nend\n", uri: "file:///zoo.rb")
    index("class Cage\nend\n", uri: "file:///cage.rb")

    expect(rbi_findings("Cage.new.hold(Zoo::Animal.new)\n")).to be_empty
  end

  it "says nothing when a subclass of an RBI-declared parameter type is passed" do
    index("class Animal\nend\n", uri: "file:///animal.rb")
    index("class Dog < Animal\nend\n", uri: "file:///dog.rb")
    index("class Cage\nend\n", uri: "file:///cage.rb")

    expect(rbi_findings("Cage.new.hold(Dog.new)\n")).to be_empty
  end

  # `Boolean` is what the converter calls RBS's `bool`, and no Ruby class
  # has that name -- so its ancestor walk can never succeed. The rule was
  # applied to the declared side and not to the argument's own, and every
  # `true`/`false` passed to a plain-class parameter was reported. Found
  # in the stdlib: `readline(@prompt, false)`.
  {
    "true" => "Widget.new.hold(true)",
    "false" => "Widget.new.hold(false)"
  }.each do |description, call|
    it "says nothing about #{description} passed where a class is declared" do
      expect(findings(call)).to be_empty
    end
  end

  # An operator call's receiver is recorded one character inside itself,
  # and when the receiver ends in `)` that offset belongs to its own last
  # argument -- so `(a - b) > 0` resolved `>`'s receiver to whatever `b`
  # was. The check declines an operator *argument* already; the receiver
  # needs the same care, and a method whose name is not an identifier is
  # where the two meet.
  it "says nothing about a call whose method name is an operator" do
    index("class Widget\nend\n", uri: "file:///widget.rb")

    expect(findings("(Widget.new) > 0\n")).to be_empty
  end

  # Inside a block whose receiver is not a generic, `infer_at` answers
  # Unknown -- not the enclosing call's own type, which is what it
  # answered before and what turned a correct argument three lines into
  # `Widget.new.each_thing do` into "expects Float, but Widget is given".
  it "says nothing about a correct argument inside a block" do
    expect(findings("Widget.new.each_thing do\n  Widget.new.zoom(1.0)\nend\n")).to be_empty
  end

  # A class made by `Data.define` or `Struct.new` is indexed as a
  # *constant*, and `HierarchyIndex` appends the implicit
  # Object/Kernel/BasicObject tail only for a name it has a class
  # declaration for -- so its reachable set was just its own name, and it
  # was reported incompatible with every plain-class parameter,
  # `Object` included. This codebase uses `Data.define` for `Types`,
  # `Finding`, `Outcome`, `Token` and `Scope`.
  {
    "a Data class" => "Point = Data.define(:x)\nWidget.new.hold(Point.new(1))\n",
    "a Struct class" => "Pair = Struct.new(:a, :b)\nWidget.new.hold(Pair.new(1, 2))\n"
  }.each do |description, body|
    it "says nothing about #{description} passed where Object is declared" do
      expect(findings(body)).to be_empty
    end
  end

  it "says nothing when the argument matches the declared type" do
    expect(findings("Widget.new.resize(3)\n")).to be_empty
  end

  # The finding has to land on the argument, not on the whole call: an
  # editor underlining the entire expression says the call is wrong rather
  # than which part of it is.
  it "underlines the argument, not the call" do
    result = findings(%(Widget.new.resize("large")\n))

    expect(result.first.range[:start][:character]).to eq(18)
    expect(result.first.range[:end][:character]).to eq(25)
  end

  it "checks each positional argument against its own parameter" do
    result = findings(%(Widget.new.resize(3)\nWidget.new.label(7)\n))

    expect(result.size).to eq(1)
    expect(result.first.evidence[:expected]).to eq("String")
  end

  # A subclass is a perfectly good instance of its parent. Reporting one
  # is the false positive this check most has to avoid, because it fires
  # on correct, idiomatic code.
  it "says nothing when the argument is a subclass of the declared type" do
    index("class SmallInteger < Integer\nend\n", uri: "file:///small.rb")

    expect(findings("Widget.new.resize(SmallInteger.new)\n")).to be_empty
  end

  # An argument is an expression, and its type is the expression's -- not
  # that of whatever token it happens to start with. Asking at the start
  # of `Widget.new` answers `ClassOf[Widget]`, the class object rather
  # than the instance being passed, and a Generic is silently outside this
  # check: the report simply disappears.
  it "types an argument by the expression, not by the token it starts with" do
    result = findings("Widget.new.label(Widget.new)\n")

    expect(result.size).to eq(1)
    expect(result.first.evidence[:actual]).to eq("Widget")
  end

  # `Integer < Numeric` is a fact only RBS has -- the workspace declares
  # neither class, so the hierarchy index knows nothing about the
  # relation. Half of any real chain lives on each side.
  it "says nothing for a subclass relation only RBS knows about" do
    expect(findings("Widget.new.scale(3)\n")).to be_empty
  end

  # The chain crosses the boundary between the two ancestry sources:
  # `MyError < StandardError` is in the workspace index, and
  # `StandardError < Exception` is only in RBS. Asking both sources about
  # `MyError` and taking either answer alone says "not compatible" for a
  # relation that plainly holds.
  it "says nothing for a chain that runs through both ancestry sources" do
    index("class MyError < StandardError\nend\n", uri: "file:///err.rb")

    expect(findings("Widget.new.handle(MyError.new)\n")).to be_empty
  end

  # Two levels, and the top one declared in Ruby as well as in the RBS --
  # which is what makes this exercise the two-source join. `Shape`
  # declared only in the signature arrives bare from `HierarchyIndex` and
  # the walk succeeds on the workspace side alone; declared in Ruby too it
  # arrives `::`-prefixed, and only the signature environment's own answer
  # supplies the bare form the comparison needs.
  it "says nothing for a workspace class two levels below the declared one" do
    index("class Shape\nend\n", uri: "file:///shape_class.rb")
    index("class Circle < Shape\nend\n", uri: "file:///shape.rb")
    index("class SmallCircle < Circle\nend\n", uri: "file:///small.rb")

    expect(findings("Widget.new.outline(SmallCircle.new)\n")).to be_empty
  end

  # RBS's `bool` converts to `Boolean`, which is capitalised and so passes
  # the alias rule -- but no such Ruby class exists, so its ancestor walk
  # can never succeed and every argument would be reported.
  it "says nothing for `bool`, which converts to a name no class has" do
    expect(findings(%(Widget.new.flag("yes")\n))).to be_empty
  end

  # Everything below is a case where the check does not know enough, and
  # the answer to not knowing enough is silence.
  it "says nothing when the argument's own type is unknown" do
    expect(findings("Widget.new.resize(whatever_this_is)\n")).to be_empty
  end

  it "says nothing when the call has no declared signature to check against" do
    index("class Undeclared\n  def resize(size)\n  end\nend\n", uri: "file:///undeclared.rb")

    expect(findings(%(Undeclared.new.resize("large")\n))).to be_empty
  end

  it "says nothing when a splat makes the positional arguments unknowable" do
    expect(findings(%(args = ["large"]\nWidget.new.resize(*args)\n))).to be_empty
  end

  # An overloaded signature means several declared parameter lists, and an
  # argument that cannot match one may be exactly right for another.
  # Choosing between them is the guessing this check refuses to do.
  it "says nothing for a method with more than one declared overload" do
    expect(findings(%(Widget.new.slice(:neither)\n))).to be_empty
  end

  # A union parameter is a stated type, but "cannot be any member of this
  # union" is a different question from "is not this class", and the
  # narrow version of the check does not answer it.
  it "says nothing when the declared parameter type is a union" do
    expect(findings("Widget.new.either(:neither)\n")).to be_empty
  end

  # RBS's `int` is not the class Integer -- it means "anything that
  # responds to #to_int". An object of an entirely unrelated class can
  # satisfy it, so reporting against it is a false positive by
  # construction. Ruby constants are capitalised; RBS's built-in aliases
  # are not, which is what tells the two apart.
  it "says nothing for an RBS alias like `int`, which is not a class" do
    expect(findings(%(Widget.new.anything("large")\n))).to be_empty
  end

  # A `*rest` parameter makes the declared positionals a prefix rather
  # than a mapping, so argument N is no longer necessarily parameter N.
  # Deliberately conservative: the arguments *before* the rest do line up,
  # and this gives up on them too rather than reason about where the rest
  # begins. The fixture passes an Integer where the leading parameter is
  # declared String, so the silence is a choice and not an absence.
  it "says nothing when the signature takes a rest parameter" do
    expect(findings("Widget.new.many(1)\n")).to be_empty
  end

  # A splat does not have to come last. A leading one shifts every
  # argument after it, so position 0 in the source is no longer parameter
  # 0 -- which is exactly the false report the splat guard prevents.
  it "says nothing when a leading splat shifts the remaining arguments" do
    expect(findings(%(rest = ["x"]\nWidget.new.pair(*rest, 1)\n))).to be_empty
  end

  # A workspace class compared against itself: `HierarchyIndex` reports a
  # class's own entry qualified (`::Widget`) while a signature names it
  # bare (`Widget`), so the ancestor walk alone answers "not compatible"
  # for a value that is exactly the declared type.
  it "says nothing when the argument is the declared workspace class itself" do
    expect(findings("Widget.new.attach(Widget.new)\n")).to be_empty
  end

  # A generic signature binds `T` from the receiver; the parameters that
  # are *not* generic are still stated, and still worth checking.
  it "still checks a concrete parameter alongside a generic one" do
    result = findings(%(Widget.new.pick([1], "two")\n))

    expect(result.size).to eq(1)
    expect(result.first.evidence[:expected]).to eq("Integer")
  end

  # The synthesised `Class`/`Module`/`Object`/`Kernel` tail exists so that
  # a class-level call *resolves*. A signature read from it is not one the
  # workspace stated, and judging parameters against it reports correct
  # code: `Invariants.initialize(cb, ocb)` in Ruby's own
  # `ruby_vm/rjit/compiler.rb` was the single `argument-type` finding the
  # whole standard library produced, against RBS's
  # `Class#initialize: (?Class superclass)`. The arity check states this
  # rule at `sole_source_declaration`; the type check did not carry it.
  it "does not judge a class-level call against a signature on the synthesised tail" do
    index(<<~RUBY, uri: "file:///shape_class.rb")
      class Shape
      end
    RUBY
    index(<<~RUBY, uri: "file:///invariants.rb")
      class Invariants
        class << self
          def initialize(first, second)
            @first = first
          end
        end
      end
    RUBY

    document = index("Invariants.initialize(Shape.new, Shape.new)\n")

    result = engine.analyze(document: document, semantic_context: context, mode: :standard)

    expect(result.select { |finding| finding.code == "argument-type" }).to be_empty
  end

  # The same rule, reached through an ancestor the tail's `:class_object`
  # origin does not mark. `Kernel` arrives on an instance chain with
  # `:default`, so a guard keyed on the origin would let this through --
  # which is why the rule is "the workspace already answered nearer"
  # rather than "the signature came from the tail".
  it "does not judge a workspace `def self.load` against `Kernel#load`" do
    index(<<~RUBY, uri: "file:///shape_class.rb")
      class Shape
      end
    RUBY
    index(<<~RUBY, uri: "file:///settings.rb")
      class Settings
        def self.load(config)
          config
        end
      end
    RUBY

    document = index("Settings.load(Shape.new)\n")

    result = engine.analyze(document: document, semantic_context: context, mode: :standard)

    expect(result.select { |finding| finding.code == "argument-type" }).to be_empty
  end

  # `def hold(a, b = 1, c)` -- a required parameter *after* an optional
  # one. Ruby fills `a` first, `c` last and `b` with whatever is left, so
  # the third argument is `c`'s. The RBI parser filed `posts` in with
  # `requireds`, and the check read `required + optional` as the
  # positional order, which put `c`'s type at index 1 and `b`'s at index
  # 2 -- reporting both of a correct call's last two arguments.
  it "orders a required parameter written after an optional one last" do
    result = rbi_findings(%(Cage.new.hold("x", 2, "y")\n), rbi: <<~RBI)
      class Cage
        sig { params(a: String, b: Integer, c: String).void }
        def hold(a, b = 1, c); end
      end
    RBI

    expect(result).to be_empty
  end

  # The same shape from RBS, where the trailing parameter was dropped
  # from the model entirely rather than mis-filed. With `middle` left
  # out, `:sym` is `last`'s argument -- and a list that stops at
  # `?Integer middle` judged it against `Integer`.
  it "maps an omitted optional parameter to the argument the caller left out" do
    result = findings(%(Widget.new.span("a", :sym)\n))

    expect(result).to be_empty
  end

  # And still reports when the same call really is wrong: `1` is not the
  # `Symbol` that `last` declares. Without this the example above passes
  # for a check that has simply stopped looking at trailing parameters.
  it "still reports an argument that lands on a trailing parameter" do
    result = findings(%(Widget.new.span("a", 1)\n))

    expect(result.size).to eq(1)
    expect(result.first.evidence).to include(expected: "Symbol", actual: "Integer", position: 1)
  end

  # RBS answers an inherited method at the *subclass's* own name, so a
  # signature found there is not necessarily declared there. `Gizmo <
  # Widget` in RBS, and the workspace overriding `resize` in Ruby, was
  # judged against `Widget`'s `(Integer size)` -- reporting a String the
  # override declares nothing about.
  it "does not judge an override against the parent signature it replaced" do
    index(<<~RUBY, uri: "file:///gizmo.rb")
      class Gizmo < Widget
        def resize(label)
        end
      end
    RUBY

    document = index(%(Gizmo.new.resize("wide")\n))
    result = engine.analyze(document: document, semantic_context: context, mode: :standard)

    expect(result.select { |finding| finding.code == "argument-type" }).to be_empty
  end

  # And the parent's own call is still judged, so the example above is
  # not passing because the check stopped looking at inherited RBS.
  it "still judges a call on the class that declares the signature" do
    result = findings(%(Widget.new.resize("wide")\n))

    expect(result.size).to eq(1)
    expect(result.first.evidence).to include(expected: "Integer", actual: "String")
  end

  # Too few arguments. They still bind to the required parameters in
  # order -- Ruby fills those first -- so the ones that were passed are
  # checkable, and `1` is not the `String` that `first` declares. The
  # first version of this method dropped the whole call instead, on the
  # stated grounds that a bad arity is the arity check's report to make.
  # That is false for a method declared only in a signature:
  # `argument_count_findings` reads *source* declarations, so nobody
  # reports it and nobody checks the arguments either.
  it "checks the arguments that were passed when the call passes too few" do
    result = findings(%(Widget.new.pair(1)\n))

    expect(result.size).to eq(1)
    expect(result.first.evidence).to include(expected: "String", actual: "Integer", position: 0)
  end

  # Too many is the other direction and genuinely unmappable: nothing
  # says which parameter the extra argument was meant for. Silence rather
  # than a guess -- and silence that does not raise, which is what the
  # refusal is really for: `optional_positionals.first(-1)` is an
  # `ArgumentError` out of `Engine#analyze`, and `Server` rescues and
  # logs, so the file would get no diagnostics at all.
  it "says nothing about a call that passes more arguments than the signature accepts" do
    result = findings(%(Widget.new.pair("a", 2, 3, 4)\n))

    expect(result).to be_empty
  end

  # The other half of the same argument, and the reason the rule is a
  # parameter rather than the method's only behaviour. `rbs_resolves?`'s
  # question is "does anything declare this at all", asked immediately
  # before reporting `unknown-method`; a source declaration nearer than
  # the RBS one means the method exists, so stopping there and answering
  # "no" would report a method the workspace itself wrote.
  #
  # No end-to-end input distinguishes the two today -- the unknown-method
  # check skips a call the resolver already resolved, and a source
  # declaration is what the resolver resolves. Measured over Ruby's
  # standard library plus activerecord and activesupport, 12,859 reports,
  # the two settings produce byte-identical output. It is pinned here, at
  # the level where the difference exists, rather than left to a corpus
  # that cannot see it.
  it "keeps walking past a source declaration when the question is whether anything declares the method" do
    index("class Gadget\n  def inspect\n  end\nend\n", uri: "file:///gadget.rb")
    candidate = Struct.new(:name, :singleton).new("inspect", false)

    resolves = engine.send(:rbs_resolves?, candidate, Ovallsp::Types::Nominal.new(name: "::Gadget"), context)

    expect(resolves).to be(true)
  end

  # `declared_signature_for` stops at the first ancestor that declares the
  # method. It was an `any?` before it had to return the signature rather
  # than a boolean, and turning it into a value lookup lost the
  # short-circuit -- on a diagnostics path that runs per call.
  it "stops asking the signature environment once an ancestor answers" do
    index("class Widget\nend\n", uri: "file:///widget.rb")
    asked = []
    semantic_context = context
    allow(semantic_context.signatures).to receive(:method_signatures).and_wrap_original do |original, symbol_id|
      asked << symbol_id.owner
      original.call(symbol_id)
    end
    candidate = Struct.new(:name, :singleton).new("resize", false)

    engine.send(:declared_signature_for, Ovallsp::Types::Nominal.new(name: "::Widget"),
                candidate, semantic_context)

    expect(asked).to eq(["::Widget"])
  end
end
