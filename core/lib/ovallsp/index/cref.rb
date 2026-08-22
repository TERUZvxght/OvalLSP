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
                       :block_depth, :visibility, :module_function, :module_owner) do
      def self.top_level
        new(owner: nil, nesting: [].freeze, singleton_context: false, self_is_module: false,
            in_method_body: false, block_depth: 0, visibility: :public, module_function: false,
            module_owner: false)
      end

      def initialize(module_function: false, module_owner: false, **fields)
        super(module_function: module_function, module_owner: module_owner, **fields)
        freeze
      end

      # Whether a bare `module_function` is open here. Ruby's answer to a
      # `def` written under one is *two* methods -- a private instance
      # method and a module method:
      #
      #   $ ruby -e '
      #   module MF
      #     module_function
      #     def mf_a; end
      #   end
      #   p [MF.respond_to?(:mf_a), MF.private_instance_methods(false)]
      #   '
      #   # => [true, [:mf_a]]
      #   # ruby 3.4.10
      #
      # It belongs here rather than in a parallel flag beside the visitor
      # for the same reason the visibility section does: it is part of
      # "what does a bare `def` written at this point mean", which is the
      # whole of what this value answers (`024.106`).
      # Only in a module body. Ruby raises
      # `NameError: undefined local variable or method 'module_function'`
      # in a class body, so a class writing it is broken code and must not
      # produce a module method here.
      def module_function? = module_function && module_owner

      def in_module_function = module_owner ? with(module_function: true) : self

      # Whether `owner` is a module rather than a class. Recorded when the
      # namespace is entered, because that is the only place the kind is
      # known -- an owner is a dotted string everywhere downstream.
      def module_owner? = module_owner

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

      # **The same question, asked about a call this parser could not
      # read.** `#defines_surface?` decides where a *definition* lands and
      # rightly refuses inside a block, whose owning call is what actually
      # decides. Opening a surface is a different claim -- "I could not
      # enumerate this owner's members" -- and a block is safe there,
      # because it silences and never invents.
      #
      # `024.117`: without this, `validates :title` silenced the owner and
      # `%i[title body].each { |f| validates f }` did not, so one
      # construct written two ways got opposite answers. The other thing
      # the block frame contains -- a `private` section that must not leak
      # into the enclosing class -- is untouched, and is `024.111`.
      def opens_surface? = defines_surface?

      # Which surface that call would add to. `attr_atomic :value` in a
      # class body defines `#value`, never `.attr_atomic`; written inside
      # `class << self` the same call defines singleton methods.
      def surface_kind = singleton_context ? :singleton : :instance

      # **The question a recorder actually has**, and the one thing they
      # should be asking. `[owner, side]` for a definition written *here*,
      # or nil where there is nothing to attribute it to.
      #
      # `024.34` is why it exists. `#declares_singleton?` answers about
      # the *cref*, which is the right answer to a bare `def`'s question
      # and the wrong one to `attr_accessor`'s: inside a `def` written in
      # `class << self`, self at run time is the class object, so
      # `attr_accessor` defines an *instance* accessor. Ruby:
      #
      #   $ ruby -e '
      #   class S
      #     class << self
      #       def setup
      #         attr_accessor :attr_x
      #       end
      #     end
      #   end
      #   S.setup
      #   p [S.new.respond_to?(:attr_x), S.respond_to?(:attr_x)]
      #   '
      #   # => [true, false]
      #   # ruby 3.4.10
      #
      # 0.2.8 collected six flags into this value and the stocktake found
      # `#defines_surface?` read at one site in the parser and
      # `#declares_singleton?` at seven -- so a recorder could still read
      # one predicate of nine and get the wrong answer, which is exactly
      # what `#record_attribute_methods` did. Collecting the storage was
      # not collecting the question.
      def surface_for
        return nil if owner.nil?

        [owner, in_method_body ? :instance : surface_kind]
      end

      # `#nesting` is real Ruby's `Module.nesting`, innermost first --
      # what an unqualified constant written here is resolved against.
      # `in_method_body` is deliberately untouched. `class Inner` written
      # inside a method body is a Ruby SyntaxError, but Prism is
      # error-tolerant and that is what a buffer looks like mid-refactor;
      # resetting it there made reports about the class go silent, which
      # the six stacks never did.
      # `module_function` is reset here for the same reason `visibility`
      # is: a nested module body opens its own section, and Ruby does not
      # carry the outer one into it.
      def in_namespace(absolute_name, module_owner: false)
        with(owner: absolute_name, nesting: [absolute_name, *nesting].freeze, singleton_context: false,
             self_is_module: true, visibility: :public, module_function: false, module_owner: module_owner)
      end

      # `in_method_body` is reset: `class << self` opens a *definition
      # context* of its own, so a macro written directly inside it lands
      # on that singleton surface whatever the block or method it was
      # reached through. Without the reset, `Class.new { class << self;
      # attr_accessor :left_model; end }` inside a `def` was recorded as
      # an instance accessor on the enclosing class -- and the
      # `def self.` methods beside it, which really do call
      # `left_model`, were then reported.
      def in_singleton_class
        with(singleton_context: true, self_is_module: true, visibility: :public,
             module_function: false, in_method_body: false)
      end

      # A `def`. `self` inside `def self.x` is still a Class or Module;
      # inside an instance method it is not. `singleton_context` is
      # deliberately untouched -- see `#declares_singleton?`.
      #
      # `module_function` *is* reset: it applies to the body it was
      # written in, and a `def` nested inside another `def` defines an
      # ordinary instance method on the enclosing module --
      # `module P; module_function; def a; def b; end; end; end; P.a`
      # leaves `P.respond_to?(:b)` false (ruby 3.4.10).
      def in_method(singleton:) = with(self_is_module: singleton, in_method_body: true, module_function: false)

      # A block or lambda body. Visibility is inherited rather than reset:
      # a plain iterator block does not open a new cref, so a `def` inside
      # it really does take the enclosing section's visibility.
      # **A block that provably keeps self does not open a frame.** Ruby:
      #
      #   $ ruby -e '
      #   module BMF; 1.times { module_function }; def y; end; end
      #   p [BMF.respond_to?(:y), BMF.private_instance_methods(false)]
      #   class BV; [1].each { private }; def x; end; end
      #   p BV.private_instance_methods(false)
      #   class BS; [1].each { attr_accessor :bs_x }; end
      #   p [BS.new.respond_to?(:bs_x), BS.respond_to?(:bs_x)]
      #   '
      #   # => [true, [:y]]
      #   # => [:x]
      #   # => [true, false]
      #   # ruby 3.4.10
      #
      # A visibility section, a `module_function` and an `attr_accessor`
      # written in an ordinary iterator block all reach the enclosing body,
      # and the frame was containing all three (`024.111`, `024.117`).
      #
      # `shares_self` is decided by a *shape*, not a list of names: the
      # owning call's receiver is a literal -- `%w[a b].each`, `[1].each`,
      # `(1..3).map`. Nobody's DSL rebinds self on a core object, and a
      # list could only ever hold the calls somebody has already seen.
      # Everything else still gets a frame, which is what keeps
      # `included do ... end` and `concerning ... do` from leaking a
      # `private` into the class body -- the regression that frame exists
      # for.
      def in_block(shares_self: false)
        shares_self ? self : with(block_depth: block_depth + 1)
      end

      # `K.instance_eval { ... }` / `K.class_eval { ... }`. Self inside is
      # the receiver, so a macro written there is a *call on that
      # constant* -- `K.attr_accessor :x`, which defines an instance
      # accessor on K. Ruby says both spellings do the same:
      #
      #   $ ruby -e '
      #   class K; end
      #   K.instance_eval { attr_accessor :k_x }
      #   p [K.respond_to?(:k_x), K.new.respond_to?(:k_x)]
      #   class L; end
      #   L.class_eval { attr_accessor :l_x }
      #   p [L.respond_to?(:l_x), L.new.respond_to?(:l_x)]
      #   '
      #   # => [false, true]
      #   # => [false, true]
      #   # ruby 3.4.10
      #
      # `024.33`: they were answered differently, because the visitor
      # could say only *whether* self was a module and not *which*. A
      # written constant says which. `owner: nil` for a receiver this
      # parser cannot name, so `#surface_for` answers nil and nothing is
      # recorded -- rather than the enclosing class's name being invented
      # for it, which is `024.31`.
      # Inside a block whose owner this parser cannot name -- a
      # `Class.new { }`, an `other.instance_eval { }`. A *top-level* `def`
      # also has no owner and must still be recorded, which is why the
      # block depth is part of the question rather than the owner alone.
      def nameless_context? = owner.nil? && block_depth.positive?

      def in_eval_block(owner)
        with(owner: owner, nesting: owner ? [owner, *nesting].freeze : nesting,
             singleton_context: false, self_is_module: true, in_method_body: false,
             block_depth: block_depth + 1, visibility: :public, module_function: false)
      end

      # Ruby keeps *one* scope-visibility value, so naming any of
      # `public`/`private`/`protected` replaces a `module_function` that
      # was open. Two independent flags said otherwise, and the engine
      # then invented a module method:
      #
      #   $ ruby -e '
      #   module M; module_function; public; def x; end; end
      #   p [M.respond_to?(:x), M.public_instance_methods(false)]
      #   '
      #   # => [false, [:x]]
      #   # ruby 3.4.10
      def with_visibility(level) = with(visibility: level, module_function: false)
    end
  end
end
