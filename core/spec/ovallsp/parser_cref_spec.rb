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
  # every method call goes through.
  #
  # **The first version of this leaked.** It prepended a module to
  # `ParserService::Visitor` in a `before(:all)` and never removed it, and
  # put its array on `Object` as a top-level constant -- so every document
  # parsed by every later spec file in the run appended to it. Measured by
  # a review round at 4,261 entries after three spec files, with
  # production code patched for whatever subset `--order random` puts
  # after this one.
  #
  # A subclass instead: the patch exists only on a class this file makes,
  # and `ParserService` is told to use it for this call. Nothing outside
  # these examples is touched, and there is nothing to remove.
  CAPTURING_VISITOR = Class.new(Ovallsp::ParserService.const_get(:Visitor, false)) do
    attr_reader :captured_crefs

    def initialize(lines)
      super
      @captured_crefs = []
    end

    def record_method_call_candidate(node)
      @captured_crefs << [node.name.to_s, cref] if node.message_loc
      super
    end
  end

  def cref_at(source, call_name)
    result = Prism.parse(source)
    visitor = CAPTURING_VISITOR.new(source.split("\n", -1))
    result.value.accept(visitor)
    visitor.captured_crefs.find { |name, _| name == call_name }&.last
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

    # **This example asserted the opposite when it was written, and was
    # wrong.** Ruby's default definee does not change when a method body
    # opens: a `def` nested inside `class << self; def build` still
    # declares on the singleton. The example encoded my reasoning rather
    # than the interpreter's behaviour, and the code was written to match
    # it -- so a test-first example pinned a regression into place. See
    # the group near the end of this file, which drives the interpreter's
    # answer.
    it "keeps answering singleton inside a method written there, as Ruby does" do
      source = "class Widget\n  class << self\n    def build\n      marker\n    end\n  end\nend\n"

      expect(cref_at(source, "marker").declares_singleton?).to be(true)
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

  # **The regression the first Cref introduced.** `#in_method` reset
  # `singleton_context` to false, on the reasoning that a method body is
  # not a singleton context. But Ruby's *default definee* inside a method
  # written in `class << self` is still the singleton class — verified
  # against the interpreter:
  #
  #   class S; class << self; def build; def helper; :h; end; end; end; end
  #   S.build; S.respond_to?(:helper)      # => true
  #   S.new.respond_to?(:helper)           # => false
  #
  # So a nested `def` was recorded as an instance method and
  # `Sgl.helper` was reported missing — a wrong answer in the unsafe
  # direction, on code that runs, introduced by the value whose whole
  # purpose is that one predicate answers one question.
  #
  # The two questions the reset conflated: "what would an unqualified
  # `def` here declare" (a method body does not change it) and "what
  # surface can a receiverless macro here add to" (a method body is not a
  # class body at all, which `#defines_surface?` already answers).
  describe "a `def` nested inside a method written in `class << self`" do
    it "still declares on the singleton, as Ruby does" do
      source = "class Sgl\n  class << self\n    def build\n      marker\n    end\n  end\nend\n"

      expect(cref_at(source, "marker").declares_singleton?).to be(true)
    end

    # And the surface question still answers separately: a macro written
    # in a method body adds nothing to the class, whatever the definee is.
    it "still adds nothing to the class's surface from inside that method" do
      source = "class Sgl\n  class << self\n    def build\n      marker\n    end\n  end\nend\n"

      expect(cref_at(source, "marker").defines_surface?).to be(false)
    end
  end

  # `class Inner` inside a method body is a Ruby SyntaxError, but Prism is
  # error-tolerant and this is what a buffer looks like mid-refactor. The
  # first Cref reset `in_method_body` on entering a namespace, which the
  # six stacks never did, so reports about that class went silent.
  it "stays inside the method body when a namespace is opened there" do
    source = "class Outer\n  def builder\n    class Inner\n      marker\n    end\n  end\nend\n"

    expect(cref_at(source, "marker").defines_surface?).to be(false)
  end
end

