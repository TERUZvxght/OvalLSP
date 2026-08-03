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
