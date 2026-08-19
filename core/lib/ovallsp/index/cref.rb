# frozen_string_literal: true

module Ovallsp
  module Index
    # What Ruby would do with a declaration written at the point the
    # parser is currently visiting: which owner it attaches to, which
    # surface, and under what visibility.
    #
    # **Why this is one value and not six stacks.**
    # `ParserService::Visitor` kept `@owner_stack`,
    # `@singleton_context_stack`, `@self_is_module_stack`,
    # `@visibility_stack`, `@in_method_body` and `@block_depth`
    # independently, and twelve recorders each read whichever subset their
    # author remembered -- 47 read sites. A recorder was correct only if
    # the author picked the right ones, and none of the six is named after
    # a question a recorder has.
    #
    # The register carries five entries from precisely that: `024.26`,
    # `024.31`, `024.32`, `024.33`, `024.34`. Every open-surface defect
    # 0.2.6's review rounds found -- one at a time, four releases running
    # -- was the same shape: `extend M` asked about the wrong side, a
    # splat DSL exempt by name, a receiverless call inside a block
    # counting as the class's own.
    #
    # So the recorders no longer consult state. They are handed this, and
    # it answers in their terms. There is no subset to read wrongly
    # because there is no subset. 037's C1.
    #
    # The three axes are deliberately separate, and conflating any two has
    # cost a release:
    #
    # - `#declares_singleton?` -- would an unqualified `def` here declare
    #   a singleton method. True inside `class << self`, **and still true
    #   inside a `def` written there**: Ruby's default definee does not
    #   change when a method body opens, so `class << self; def build; def
    #   helper; end; end; end` declares `helper` on the singleton.
    #   Resetting it here was the first Cref's own regression -- one
    #   predicate answering two questions, which is the thing this value
    #   exists to stop. What a method body *does* change is whether a
    #   receiverless macro can add to the class's surface, and that is
    #   `#defines_surface?`, below.
    # - `#self_is_module?` -- is `self` here a Class or Module object.
    #   Also true directly in a class body and inside `def self.x`.
    #   Conflating it with the above made every `private` and `attr_reader`
    #   in a class body resolve against the instance chain, where they do
    #   not exist (`024.23`).
    # - `#defines_surface?` -- can a receiverless call here add to the
    #   owner's method surface. False in a method body, false inside
    #   somebody else's block (the call that *owns* the block is what
    #   decides), false with no owner at all.
    Cref = Data.define(:owner, :nesting, :singleton_context, :self_is_module, :in_method_body,
                       :block_depth, :visibility) do
      def self.top_level
        new(owner: nil, nesting: [].freeze, singleton_context: false, self_is_module: false,
            in_method_body: false, block_depth: 0, visibility: :public)
      end

      def initialize(**fields)
        super
        freeze
      end

      def declares_singleton? = singleton_context

      def self_is_module? = self_is_module

      def in_method_body? = in_method_body

      # Whether a receiverless call written here can add to `owner`'s
      # method surface. Three conditions that used to be assembled at each
      # call site: there has to be an owner, the call has to run when the
      # body runs rather than when a method is called, and it has to be
      # the class body's own call rather than one inside a block whose
      # owning call is what actually decides.
      def defines_surface? = !owner.nil? && !in_method_body && block_depth.zero?

      # Which surface that call would add to. `attr_atomic :value` in a
      # class body defines `#value`, never `.attr_atomic`; written inside
      # `class << self` the same call defines singleton methods.
      def surface_kind = singleton_context ? :singleton : :instance

      # `#nesting` is real Ruby's `Module.nesting`, innermost first --
      # what an unqualified constant written here is resolved against.
      # `in_method_body` is deliberately untouched. `class Inner` written
      # inside a method body is a Ruby SyntaxError, but Prism is
      # error-tolerant and that is what a buffer looks like mid-refactor;
      # resetting it there made reports about the class go silent, which
      # the six stacks never did.
      def in_namespace(absolute_name)
        with(owner: absolute_name, nesting: [absolute_name, *nesting].freeze, singleton_context: false,
             self_is_module: true, visibility: :public)
      end

      def in_singleton_class = with(singleton_context: true, self_is_module: true, visibility: :public)

      # A `def`. `self` inside `def self.x` is still a Class or Module;
      # inside an instance method it is not. `singleton_context` is
      # deliberately untouched -- see `#declares_singleton?`.
      def in_method(singleton:) = with(self_is_module: singleton, in_method_body: true)

      # A block or lambda body. Visibility is inherited rather than reset:
      # a plain iterator block does not open a new cref, so a `def` inside
      # it really does take the enclosing section's visibility.
      def in_block = with(block_depth: block_depth + 1)

      def with_visibility(level) = with(visibility: level)
    end
  end
end
