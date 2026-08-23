# frozen_string_literal: true

# What `define_method(:x)` declares its method *takes*.
#
# `024.116` taught the parser to record the name a `define_method` writes,
# which is the whole reason hover and go-to-definition answer for one. It
# recorded `parameters: []` with it -- and an empty parameter list is not
# "unknown", it is the assertion that the method takes no arguments. So
# every call to such a method became an `argument-count` report.
#
# Measured over Ruby 3.4.10's standard library, five Rails 8.1.3.1 gems
# and minitest 5.25.4 -- 2,095 files: **109 of the 109** `argument-count`
# findings the engine produced were this one line, and two declarations
# produced all 109. `rubygems/core_ext/kernel_warn.rb` writes
# `module_function define_method(:warn) {|*messages, **kw| ... }` and
# `objspace/trace.rb` writes `define_method(:p) do |*objs|`, so every
# `warn` (94) and every `p` (15) the corpus calls was told it takes 0
# arguments. `024.40` is the entry.
#
# The parameters are the block's, and Ruby enforces them strictly -- a
# block passed to `define_method` is arity-checked like a `def`, not like
# a proc:
#
#   $ ruby -e '
#   class C
#     define_method(:zero)  { :z }
#     define_method(:two)   { |a, b| [a, b] }
#     define_method(:splat) { |*objs| objs }
#     define_method(:opt)   { |a, b = 1| [a, b] }
#   end
#   c = C.new
#   def try(label) = (print "#{label}: "; begin; p yield; rescue ArgumentError => e; puts e.message; end)
#   try("zero(1)")     { c.zero(1) }
#   try("two(1)")      { c.two(1) }
#   try("two(1,2,3)")  { c.two(1, 2, 3) }
#   try("splat(1,2,3)"){ c.splat(1, 2, 3) }
#   try("opt()")       { c.opt }
#   '
#   zero(1): wrong number of arguments (given 1, expected 0)
#   two(1): wrong number of arguments (given 1, expected 2)
#   two(1,2,3): wrong number of arguments (given 3, expected 2)
#   splat(1,2,3): [1, 2, 3]
#   opt(): wrong number of arguments (given 0, expected 1..2)
#   # ruby 3.4.10
#
# So the block's parameter list is a real answer where there is a block
# literal, and where there is not -- `define_method(:x, &blk)`,
# `define_method(:x, instance_method(:y))` -- nothing here states one, and
# the parser says so rather than saying "none".
RSpec.describe "what `define_method` declares it takes (024.40)" do
  def summarize(source)
    Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    )
  end

  def parameter_kinds(body, name)
    summarize("class C\n#{body}end\n").declarations
                                     .find { |d| d.symbol_id.name == name }
                                     .parameters.map(&:kind)
  end

  it "takes what the block takes" do
    expect(parameter_kinds("  define_method(:pair) { |a, b| }\n", "pair")).to eq(%i[required required])
  end

  it "takes an optional parameter as optional" do
    expect(parameter_kinds("  define_method(:opt) { |a, b = 1| }\n", "opt")).to eq(%i[required optional])
  end

  # The shape the corpus is full of, and the one every false report came
  # from. A rest parameter is what the argument-count check already bails
  # out on -- the same answer `def m(...)` and a `delegate` get.
  it "takes a splat as a rest parameter" do
    expect(parameter_kinds("  define_method(:splat) { |*objs| }\n", "splat")).to eq([:rest])
  end

  it "takes nothing when the block takes nothing" do
    expect(parameter_kinds("  define_method(:zero) { 1 }\n", "zero")).to eq([])
  end

  # No block literal, so the parameter list is not written here at all.
  it "states no count when the method body is not a block written here" do
    expect(parameter_kinds("  define_method(:forwarded, &blk)\n", "forwarded")).to eq([:rest])
  end

  # `{ _1 }` and `{ it }` do declare an arity Ruby enforces, but this
  # parser does not read numbered parameters anywhere else and inventing
  # one here would be an assertion nothing checked.
  it "states no count for a numbered parameter" do
    expect(parameter_kinds("  define_method(:numbered) { _1 }\n", "numbered")).to eq([:rest])
  end

  it "does the same for define_singleton_method" do
    expect(parameter_kinds("  define_singleton_method(:pair) { |a, b| }\n", "pair")).to eq(%i[required required])
  end

  # The countermeasure, rather than a third regression test for a third
  # instance of one mistake. `delegate` and `scope` recorded no parameter
  # list in 0.1.15 and `define_method` did in 0.2.13, each by taking
  # `add_generated_method`'s `parameters: []` default while meaning "not
  # stated here" -- and each made the argument-count check judge every
  # call to what it declared. The keyword has no default now, so the
  # question cannot be answered by omission: a recorder states the list,
  # or states UNSTATED_PARAMETERS.
  #
  # Asserted against the method rather than against its text: `:keyreq`
  # is what a required keyword reports and `:key` is what a defaulted one
  # reports, so this fails the moment a default comes back.
  it "leaves no recorder able to declare an empty parameter list by omission" do
    recorder = Ovallsp::ParserService.const_get(:Visitor).instance_method(:add_generated_method)

    expect(recorder.parameters.to_h { |kind, name| [name, kind] }[:parameters]).to eq(:keyreq)
  end

  describe "what the engine reports about a call to one" do
    subject(:engine) { Ovallsp::Diagnostics::Engine.new }

    let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
    let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry) }
    let(:model_registry) { Ovallsp::Models::ModelRegistry.new }

    def context
      Ovallsp::Diagnostics::SemanticContext.new(
        workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
        method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
        model_registry: model_registry, route_registry: Ovallsp::Routes::RouteRegistry.new,
        signatures: stack.signatures, generation: 1
      )
    end

    def argument_counts(source)
      document = Ovallsp::TextDocument.new(uri: "file:///c.rb", text: source, version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      stack.hierarchy_index.replace_file(summary)

      engine.analyze(document: document, semantic_context: context, mode: :standard)
            .select { |finding| finding.code == "argument-count" }
            .map(&:message)
    end

    # `kernel_warn.rb`'s shape, reduced. Two given, and the method takes
    # any number.
    it "reports nothing about a call to a method whose block splats" do
      source = <<~'RUBY'
        class C
          define_method(:warn) { |*messages, **kw| [messages, kw] }

          def report
            warn("a", "b")
          end
        end
      RUBY

      expect(argument_counts(source)).to be_empty
    end

    # The distinguishing half: the fix must not switch the check off for
    # `define_method`, and the *message* differs between the two
    # behaviours -- "takes 0 arguments" is what the empty list said, and
    # "takes 2 arguments" is what the block says.
    it "reports the block's own count when a call cannot fit it" do
      source = <<~'RUBY'
        class C
          define_method(:pair) { |a, b| [a, b] }

          def report
            pair(1)
          end
        end
      RUBY

      expect(argument_counts(source)).to eq(["`pair` takes 2 arguments, but 1 given"])
    end
  end
end
