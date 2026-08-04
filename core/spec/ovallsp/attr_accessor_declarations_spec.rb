# frozen_string_literal: true

# `attr_reader :name` declares a method as surely as `def name` does, but
# the index recorded only the call, never the declaration. So a class
# whose ancestry is fully known -- exactly the receiver the unknown-method
# check acts on -- had every one of its attribute readers reported as
# missing.
#
# This was masked while class bodies were mis-modelled (024.23): the
# reports it produces need the *instance* side of a closed class, and
# until the class-body self was fixed, some of those calls were being
# resolved against the singleton side instead. Fixing that surfaced it on
# Thor's `attr_accessor :options`, read from inside a `define_method`
# block, which is what made this a defect this release has to close
# rather than one it can record: a fix must not hand a user a new wrong
# report.
RSpec.describe "attr_* declares methods (0.1.14)" do
  let(:parser) { Ovallsp::ParserService.new }

  def summarize(source)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    parser.summarize(document)
  end

  def declared(source, kind: :instance_method)
    summarize(source).declarations
                     .select { |declaration| declaration.symbol_id.kind == kind }
                     .map { |declaration| declaration.symbol_id.name }
  end

  it "declares a reader for `attr_reader`" do
    expect(declared("class Widget\n  attr_reader :name, :size\nend\n")).to eq(%w[name size])
  end

  it "declares a writer for `attr_writer`" do
    expect(declared("class Widget\n  attr_writer :name\nend\n")).to eq(["name="])
  end

  it "declares both for `attr_accessor`" do
    expect(declared("class Widget\n  attr_accessor :name\nend\n")).to eq(["name", "name="])
  end

  # `attr_accessor "name"` is legal Ruby and appears in the wild.
  it "accepts string arguments as well as symbols" do
    expect(declared('class Widget
  attr_accessor "name"
end
')).to eq(["name", "name="])
  end

  # A dynamic argument names nothing statically. Recording a guess here
  # would be worse than recording nothing: it would declare a method that
  # may not exist and silence a real report.
  it "records nothing for a dynamic argument" do
    expect(declared("class Widget\n  attr_reader(*names)\n  attr_reader :ok\nend\n")).to eq(["ok"])
  end

  # Without the `return unless node.arguments` guard, `summarize` raises
  # NoMethodError on any file containing a bare `attr_reader` -- the
  # parser stops, and every feature loses that file. The suite had no such
  # file, so the guard was load-bearing and unpinned.
  it "does not raise on a bare `attr_reader` with no arguments" do
    expect { summarize("class Widget\n  attr_reader\nend\n") }.not_to raise_error
  end

  it "records nothing outside a class or module body" do
    expect(declared("attr_reader :loose\n")).to be_empty
  end

  # Inside `class << self` these declare *singleton* methods, which is a
  # different symbol kind and a different lookup chain.
  it "declares singleton methods inside `class << self`" do
    source = "class Widget\n  class << self\n    attr_reader :registry\n  end\nend\n"

    expect(declared(source, kind: :singleton_method)).to eq(["registry"])
    expect(declared(source)).to be_empty
  end

  # The visibility section a class body has open applies to what these
  # generate, exactly as it does to a `def`.
  it "records the open visibility section" do
    source = "class Widget\n  private\n  attr_reader :hidden\nend\n"
    declaration = summarize(source).declarations.find { |d| d.symbol_id.name == "hidden" }

    expect(declaration.visibility).to eq(:private)
  end

  # `attr_*` is attributed to the lexically enclosing owner wherever it
  # is written, exactly as `def` is. Three narrower rules were tried and
  # each disowned it somewhere `def` is still owned -- and a block holds
  # both, so half-disowning one turns the other into a false report
  # (024.31). `included do attr_accessor :tracked_at end` is how every
  # ActiveSupport::Concern is written, and every one of them broke under
  # the first attempt.
  {
    "class_eval" => "class_eval do",
    "instance_eval" => "instance_eval do",
    "an ActiveSupport::Concern hook" => "included do",
    "concerning" => "concerning :Extra do",
    "an ordinary iterator" => "[1].each do",
    "a Struct builder" => "Struct.new(:x) do",
    "a Class builder" => "Class.new do"
  }.each do |label, opener|
    it "records an attribute written inside #{label}" do
      source = "class Outer\n  #{opener}\n    attr_reader :inside\n  end\nend\n"

      expect(declared(source)).to eq(["inside"])
    end
  end

  # The same shape ActiveRecord builds its habtm association class with:
  # a `def self.` and an `attr_accessor` in one block, inside a method.
  # Whatever owner the block really has, both halves must get the same
  # one, or the `def`'s body reports the `attr_accessor`'s method missing.
  it "gives a def and an attr_accessor in one block the same owner" do
    source = <<~'RUBY'
      class Builder
        def build
          Class.new(Object) do
            class << self
              attr_accessor :left_model
            end

            def self.compute
              left_model.to_s
            end
          end
        end
      end
    RUBY
    owners = summarize(source).declarations
                              .select { |d| d.symbol_id.kind == :singleton_method }
                              .map { |d| d.symbol_id.owner }.uniq

    expect(owners).to eq(["::Builder"])
  end

  it "still records one written directly in the class body" do
    expect(declared("class Outer\n  attr_reader :direct\nend\n")).to eq(["direct"])
  end

  # `private attr_reader :x` is one call taking another as its argument
  # (Ruby 3.0+, and RuboCop's `group_style: inline`). The reader is
  # private; recording it public offered it in completion on an outside
  # receiver. It does not affect diagnostics -- no check reads visibility.
  it "records the inline `private attr_reader` form as private" do
    source = "class Widget\n  private attr_reader :hidden\n  attr_reader :shown\nend\n"
    visibilities = summarize(source).declarations
                                    .select { |d| d.symbol_id.kind == :instance_method }
                                    .to_h { |d| [d.symbol_id.name, d.visibility] }

    expect(visibilities).to eq("hidden" => :private, "shown" => :public)
  end

  # `docs`-level invariant, stated in three places: a `:generated`
  # declaration is always paired with a `GeneratedMethodFact`. 0.1.14
  # recorded attr declarations without one, so those three statements were
  # false. Nothing observable changes today -- both paths answer
  # `Types::UNKNOWN` -- which is why this is asserted directly rather than
  # through a feature: `MethodSummary`'s confidence and status read the
  # fact, and would drift silently.
  it "pairs each generated declaration with a fact naming the macro" do
    summary = summarize("class Widget\n  attr_accessor :name\nend\n")
    facts = summary.generated_method_facts.map { |fact| [fact.name, fact.origin] }

    expect(facts).to eq([["name", :attr_accessor], ["name=", :attr_accessor]])
  end

  # `Unknown`, not `nil` and not a guess: an attribute's type is whatever
  # was last assigned to the ivar, which this parser does not track. The
  # value coincides with what 0.1.14 answered through the no-fact
  # fallback, so nothing downstream changed when the fact appeared -- and
  # nothing failed when the value was wrong, either, which is why it is
  # asserted here.
  it "gives the generated fact an honest return type" do
    fact = summarize("class Widget\n  attr_reader :name\nend\n").generated_method_facts.first

    expect(fact.return_type).to eq(Ovallsp::Types::UNKNOWN)
  end

  it "names the macro that declared it, not a single origin for all of them" do
    origins = summarize("class Widget\n  attr_reader :a\n  attr_writer :b\nend\n")
              .generated_method_facts.map(&:origin)

    expect(origins).to eq(%i[attr_reader attr_writer])
  end

  # The reader takes nothing and the writer takes exactly one argument,
  # which is what the argument-count check reads. Recording no parameters
  # for the writer would make every assignment through it a diagnostic.
  it "gives the writer one parameter and the reader none" do
    declarations = summarize("class Widget\n  attr_accessor :name\nend\n").declarations
                                                                         .select { |d| d.symbol_id.kind == :instance_method }
                                                                         .to_h { |d| [d.symbol_id.name, d.parameters.size] }

    expect(declarations).to eq("name" => 0, "name=" => 1)
  end

end
