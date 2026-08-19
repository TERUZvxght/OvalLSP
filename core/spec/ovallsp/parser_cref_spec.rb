# frozen_string_literal: true

# `ParserService::Visitor` decided a declaration's owner, kind and
# visibility from **six independent mutable stacks** -- `@owner_stack`,
# `@singleton_context_stack`, `@self_is_module_stack`, `@visibility_stack`,
# `@in_method_body` and `@block_depth` -- read by twelve recorders, each
# consulting whichever subset its author remembered. 47 read sites.
#
# A recorder was correct only if its author picked the right ones, and
# none of the six is named after a question a recorder actually has. The
# register carries five entries from exactly that: `024.26` (a workspace
# `def Object.foo` reachable from every class), `024.31` (a declaration
# inside a block has no owner), `024.32` (`def Foo.bar` recorded as an
# instance method), `024.33` (`instance_eval` reported where `class_eval`
# is not), `024.34` (`attr_*` inside a `def` inside `class << self`
# kinded singleton) -- and every open-surface defect 0.2.6's rounds found
# one at a time was the same shape.
#
# So: one immutable `Cref` answering the questions, pushed and popped in
# one place, handed to every recorder. There is then no subset to read
# wrongly, because there is no subset. 037's C1.
RSpec.describe "Ovallsp::ParserService and the cref a declaration is recorded against" do
  # The cref as the recorders see it, captured at the one entry point
  # every method call goes through. Prepended once for the whole file
  # rather than per example: `Module#prepend` accumulates, and a second
  # copy would answer from the first example's closure.
  CAPTURED = []

  before(:all) do
    captured = CAPTURED
    Ovallsp::ParserService.const_get(:Visitor, false).prepend(Module.new do
      define_method(:record_method_call_candidate) do |node|
        captured << [node.name.to_s, cref] if node.message_loc
        super(node)
      end
    end)
  end

  def cref_at(source, call_name)
    CAPTURED.clear
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    Ovallsp::ParserService.new.summarize(document)
    CAPTURED.find { |name, _| name == call_name }&.last
  end

  describe "what a `def` written here would declare" do
    it "answers the enclosing class in a class body" do
      cref = cref_at("class Widget\n  marker\nend\n", "marker")

      expect([cref.owner, cref.declares_singleton?]).to eq(["::Widget", false])
    end

    # `024.34`'s shape. Inside `class << self` an unqualified `def`
    # declares a singleton method -- and inside a `def` *within* it, one
    # does not.
    it "answers singleton inside `class << self`" do
      cref = cref_at("class Widget\n  class << self\n    marker\n  end\nend\n", "marker")

      expect([cref.owner, cref.declares_singleton?]).to eq(["::Widget", true])
    end

    it "stops answering singleton inside a method written there" do
      source = "class Widget\n  class << self\n    def build\n      marker\n    end\n  end\nend\n"

      expect(cref_at(source, "marker").declares_singleton?).to be(false)
    end
  end

  # A second, deliberately separate question: `self` is a Class/Module in
  # a class body *and* inside `class << self` *and* inside `def self.x`.
  # Conflating it with the one above made every `private` and
  # `attr_reader` in a class body resolve against the instance chain
  # (`024.23`).
  describe "whether `self` here is a Class or Module" do
    it "is true directly in a class body" do
      expect(cref_at("class Widget\n  marker\nend\n", "marker").self_is_module?).to be(true)
    end

    it "is true inside `def self.x`, where a `def` would not be singleton" do
      cref = cref_at("class Widget\n  def self.build\n    marker\n  end\nend\n", "marker")

      expect([cref.self_is_module?, cref.declares_singleton?]).to eq([true, false])
    end

    it "is false inside an instance method" do
      expect(cref_at("class Widget\n  def go\n    marker\n  end\nend\n", "marker").self_is_module?).to be(false)
    end
  end

  # The question `#record_open_surface` actually has, which it used to
  # assemble from three ivars at its own call site -- and got wrong twice
  # in 0.2.6, once for blocks and once for `extend`.
  describe "whether a receiverless call here can add to the owner's surface" do
    it "can, written directly in a class body" do
      expect(cref_at("class Widget\n  marker\nend\n", "marker").defines_surface?).to be(true)
    end

    it "cannot, inside a method body" do
      expect(cref_at("class Widget\n  def go\n    marker\n  end\nend\n", "marker").defines_surface?).to be(false)
    end

    it "cannot, inside somebody else's block" do
      expect(cref_at("class Widget\n  [1].each { marker }\nend\n", "marker").defines_surface?).to be(false)
    end

    it "cannot at the top level, where there is no owner" do
      expect(cref_at("marker\n", "marker").defines_surface?).to be(false)
    end

    it "names the singleton surface inside `class << self`" do
      cref = cref_at("class Widget\n  class << self\n    marker\n  end\nend\n", "marker")

      expect([cref.defines_surface?, cref.surface_kind]).to eq([true, :singleton])
    end
  end

  it "is immutable, so a recorder cannot be handed one that changes under it" do
    expect(cref_at("class Widget\n  marker\nend\n", "marker")).to be_frozen
  end
end
