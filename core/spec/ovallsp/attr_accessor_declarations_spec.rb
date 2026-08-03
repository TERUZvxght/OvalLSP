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

  # `attr_accessor` inside a method body does not run at class level, so
  # it declares nothing. Recording it did worse than nothing: it silenced
  # the report on `w.never_real`, which Ruby raises NoMethodError for.
  it "records nothing inside a method body" do
    declarations = declared("class Widget\n  def setup\n    attr_accessor :never_real\n  end\nend\n")

    expect(declarations).to eq(["setup"])
  end

  # Only a block that builds an *anonymous* class or module takes the
  # attribute somewhere else: `Struct.new do attr_reader :label end`
  # declares `label` on the new Struct, not on the class the block is
  # written inside. Recording it on the enclosing class offered `label` in
  # completion on an object that does not have it.
  %w[Struct.new(:x) Class.new Data.define(:x) Module.new].each do |builder|
    it "records nothing inside a `#{builder}` block" do
      source = "class Outer\n  Built = #{builder} do\n    attr_reader :label\n  end\nend\n"

      expect(declared(source)).to be_empty
    end
  end

  # Every other block runs against the enclosing class, or against
  # whatever includes it, and attributing to the enclosing owner is the
  # answer that resolves. 0.1.15 skipped all of them, which turned real
  # methods into `unknown-method` reports -- `included do attr_accessor
  # :tracked_at end` is how every ActiveSupport::Concern is written.
  {
    "class_eval" => "class_eval do",
    "instance_eval" => "instance_eval do",
    "an ActiveSupport::Concern hook" => "included do",
    "concerning" => "concerning :Extra do",
    "an ordinary iterator" => "[1].each do"
  }.each do |label, opener|
    it "records an attribute written inside #{label}" do
      source = "class Outer\n  #{opener}\n    attr_reader :inside\n  end\nend\n"

      expect(declared(source)).to eq(["inside"])
    end
  end

  # A named class inside any block is its own owner, so nothing about the
  # block reaches it. The builder case is the one that distinguishes:
  # inside `1.times do` the skip is not armed either way, so only a class
  # written inside `Struct.new do` can tell whether entering a namespace
  # clears the flag.
  it "records an attribute in a class body written inside a plain block" do
    source = "1.times do\n  class Later\n    attr_reader :zed\n  end\nend\n"

    expect(declared(source)).to eq(["zed"])
  end

  it "records an attribute in a class body written inside an anonymous-class block" do
    source = "Built = Struct.new(:x) do\n  class Later\n    attr_reader :zed\n  end\nend\n"

    expect(declared(source)).to eq(["zed"])
  end

  it "still records one written directly in the class body" do
    expect(declared("class Outer\n  attr_reader :direct\nend\n")).to eq(["direct"])
  end

  # `private attr_reader :x` is one call taking another as its argument
  # (Ruby 3.0+, and RuboCop's `group_style: inline`). The reader is
  # private; recording it public leaked it into completion and silenced
  # the unknown-method check on an external call.
  it "records the inline `private attr_reader` form as private" do
    source = "class Widget\n  private attr_reader :hidden\n  attr_reader :shown\nend\n"
    visibilities = summarize(source).declarations
                                    .select { |d| d.symbol_id.kind == :instance_method }
                                    .to_h { |d| [d.symbol_id.name, d.visibility] }

    expect(visibilities).to eq("hidden" => :private, "shown" => :public)
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
