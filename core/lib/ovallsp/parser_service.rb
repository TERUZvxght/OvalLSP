# frozen_string_literal: true

require "digest"
require "set"
require "prism"

require_relative "index/symbol_id"
require_relative "index/cref"
require_relative "index/parameter"
require_relative "index/declaration"
require_relative "index/ancestor_fact"
require_relative "index/alias_fact"
require_relative "index/reference_candidate"
require_relative "index/generated_method_fact"
require_relative "index/file_summary"
require_relative "index/source_location"
require_relative "erb/ruby_region_extractor"
require_relative "types"

module Ovallsp
  # Parses a document with Prism and extracts class/module/method/constant
  # declarations into a FileSummary. Prism is error-tolerant: even when the
  # source has a syntax error, it still produces a best-effort AST, so
  # declarations before the error remain visible (Task 002 acceptance
  # criterion). AST node objects are never retained past this method.
  #
  # `.erb` documents are transparently run through
  # Erb::RubyRegionExtractor before parsing — this is the single point
  # every caller (didOpen/didChange's #summarize call, didChangeWatchedFiles'
  # reindex, Cold Index) goes through, so none of them can diverge on how
  # ERB is handled. Before Task 008.6, only Cold Index applied the
  # extraction itself; every other path fed raw HTML+`<% %>` template
  # source directly to Prism, which parsed it as (mostly invalid) Ruby —
  # opening a .erb file via didOpen never actually indexed its Ruby
  # regions at all
  # (docs/design/tasks/008.6-agent-and-index-hardening.md).
  class ParserService
    DIAGNOSTIC_ERROR_SEVERITY = 1

    def summarize(document)
      raw_source = document.text
      parse_source = erb_document?(document.uri) ? Erb::RubyRegionExtractor.extract_ruby_source(raw_source) : raw_source
      result = Prism.parse(parse_source)
      lines = parse_source.split("\n", -1)

      visitor = walk(result, lines)

      Index::FileSummary.new(
        uri: document.uri,
        # Hashed from the raw (pre-extraction) source: what matters for
        # WorkspaceIndex's no-op-skip check is whether the underlying
        # file actually changed, not whether its *extracted* form did —
        # the two are equivalent in practice (extraction is a pure
        # function of the raw source) but hashing the raw source avoids
        # re-running extraction just to compute a hash when nothing
        # changed.
        content_hash: Digest::SHA256.hexdigest(raw_source),
        document_version: document.version,
        buffer_id: document.buffer_id,
        declarations: visitor.declarations,
        diagnostics: parse_diagnostics(result, lines, erb: erb_document?(document.uri)),
        ancestor_facts: visitor.ancestor_facts,
        alias_facts: visitor.alias_facts,
        reference_candidates: visitor.reference_candidates,
        generated_method_facts: visitor.generated_method_facts,
        open_surface_owners: visitor.open_surface_owners.to_a,
        macro_call_ranges: visitor.macro_call_ranges.to_a,
        pattern_bound_names: visitor.pattern_bound_names.uniq,
        module_function_names: visitor.module_function_names.to_a
      ).then { |summary| withdraw_forward_aliases(summary) }
    end

    private

    # The visitor recurses once per nested node, so a deep enough file
    # exhausts the interpreter stack. `SystemStackError` is an
    # `Exception` rather than a `StandardError`, so it passed through
    # every rescue between here and `Server#run`: opening one such file
    # ended the editor's session with a raw backtrace on stderr, and the
    # cold-index thread died without a log line -- taking the deleted-file
    # sweep, the reference-index bump and the workspace diagnostics pass
    # with it for the rest of the session. `BackgroundTasks#shutdown`,
    # documented "never raises", raised too, because `Thread#join`
    # re-raises what killed the thread.
    #
    # Contained where the recursion is rather than at each caller.
    # `Server#dispatch`, `ColdIndexer` and `scripts/corpus_diagnostics.rb`
    # each had their own rescue and each was individually plausible; that
    # is exactly the arrangement docs/CODE_DISCIPLINE.md's containment rule is about.
    #
    # An empty visitor rather than a partial one: a half-finished walk
    # holds the declarations from the top of the file and none from the
    # bottom, and the undefined-method check would assert absence on the
    # strength of it. "Nothing was read here" is the truthful answer, and
    # it is the one every other unreadable-input path in this file gives.
    #
    # Measured: a `.succ` chain fails at depth 2104, nested hashes at
    # 1147. 0 of 4582 `.rb` files across every installed gem and the Ruby
    # 3.4 stdlib reach any such depth, so this is generated or hostile
    # input -- and a file arrives from anywhere.
    def walk(result, lines)
      visitor = Visitor.new(lines)
      begin
        result.value.accept(visitor)
        visitor
      rescue SystemStackError
        Visitor.new(lines)
      end
    end


    # `alias_method :create, :new` binds `create` to whatever `new` means
    # at the moment the statement runs -- not to a `def new` written five
    # lines below it. ActiveSupport's `TimeZone` is that shape exactly
    # (`alias_method :create, :new` at :212, `def new(name)` at :217), so
    # `TimeZone.create(name, utc_offset, tzinfo)` reaches `Class#new` and
    # takes three arguments. Resolving the alias to the later `def`
    # reported "`create` takes 1 argument, but 3 given" on ActiveSupport's
    # own source, and the same construct in a smaller workspace instead
    # reported "has no method named `create`" -- two checks, two different
    # wrong answers about one alias.
    #
    # Only the case this file can *prove* wrong is withdrawn: a target
    # declared later in this same file. A target declared elsewhere, or
    # earlier, keeps resolving as before -- reopening a class from another
    # file is an ordinary pattern and nothing here can order those.
    #
    # The owner's surface opens in the alias's place, because `create`
    # does exist; what is unknown is which method it names.
    def withdraw_forward_aliases(summary)
      forward = summary.alias_facts.select { |fact| declared_after?(summary, fact) }
      return summary if forward.empty?

      summary.with(
        alias_facts: summary.alias_facts - forward,
        open_surface_owners: (summary.open_surface_owners +
          forward.map { |fact| [Index::SymbolId.bare_name(fact.owner), fact.singleton ? :singleton : :instance] }).uniq
      )
    end

    def declared_after?(summary, fact)
      kind = fact.singleton ? :singleton_method : :instance_method
      summary.declarations.any? do |declaration|
        symbol_id = declaration.symbol_id
        symbol_id.kind == kind && symbol_id.name == fact.old_name &&
          symbol_id.owner == Index::SymbolId.qualify_owner(fact.owner) &&
          starts_after?(declaration.location, fact.location)
      end
    end

    def starts_after?(later, earlier)
      ([later[:start][:line], later[:start][:character]] <=>
        [earlier[:start][:line], earlier[:start][:character]]).positive?
    end


    def erb_document?(uri)
      uri.to_s.end_with?(".erb")
    end

    # An ERB template is compiled into a method body, so `<%= yield %>`
    # in a layout is legal Ruby there -- but the extracted regions are
    # parsed at top level, where Prism rejects it. Reporting it made every
    # Rails layout show a syntax error for its own central line.
    #
    # Keyed on Prism's error type rather than its message, which is
    # wording and can change between versions.
    ERB_LEGAL_AT_TOP_LEVEL = %i[invalid_yield].freeze

    def parse_diagnostics(result, lines, erb:)
      errors = result.errors
      errors = errors.reject { |error| ERB_LEGAL_AT_TOP_LEVEL.include?(error.type) } if erb
      errors.map { |error| to_diagnostic(error, lines) }
    end

    def to_diagnostic(error, lines)
      {
        range: Index::SourceLocation.to_range(error.location, lines),
        severity: DIAGNOSTIC_ERROR_SEVERITY,
        message: error.message,
        source: "ovallsp"
      }
    end

    # Single-pass AST walk (docs/03-semantic-engine.md 4.1: "Prism Dispatcher
    #相当のvisitorを1回だけ通す"). Tracks the lexically enclosing
    # class/module as an owner stack so nested declarations normalize to
    # absolute names, and tracks whether we're inside `class << self` so
    # unqualified `def`s there are recognized as singleton methods.
    class Visitor < Prism::Visitor
      # Task 009: bare `include`/`prepend`/`extend` calls to track. Any
      # other call named the same but with an explicit receiver (e.g.
      # `SomeClass.include(Foo)`, dynamically reopening a *different*
      # class) is out of scope — this only recognizes the ordinary,
      # lexical-body form.
      ANCESTOR_RELATIONS = { include: :include, prepend: :prepend, extend: :extend }.freeze

      attr_reader :declarations, :ancestor_facts, :alias_facts, :reference_candidates, :generated_method_facts,
                  :open_surface_owners, :module_function_names, :pattern_bound_names, :macro_call_ranges

      # Receiverless calls that can be written in a class body without
      # adding anything to that class's method surface. Membership is a
      # *claim*, checked against the corpus: everything not listed here
      # and not recognised elsewhere in this visitor makes the surface
      # open, and the check above it then declines to report absence.
      #
      # Adding a name here is an assertion that it defines no method, and
      # it costs precision when wrong -- not merely noise.
      #
      # **The figures first recorded here were wrong**, and the way they
      # were wrong is the more useful record: they were taken with a
      # prototype that counted only calls written directly in a class
      # body, while the rule that shipped counted calls inside blocks too.
      # So "24 of 257 classes open, and every name among them can define a
      # method" described a rule nobody ran. Re-measured over the same 213
      # files with the shipped code: **52 of 329 class and module names**,
      # triggered by names including `warn`, `respond_to?`, `lambda`, `<`
      # and `private_method_defined?`. A review round found it; the
      # measurement should have.
      #
      # Two corrections followed. The block rule above -- which is the
      # structural half, since most of the excess was `assert_equal`
      # inside somebody's `test` block -- and the second group below,
      # which are calls that read or report and cannot define.
      NON_DEFINING_CLASS_BODY_CALLS = %i[
        private public protected module_function
        private_class_method public_class_method
        private_constant public_constant deprecate_constant
        autoload undef_method remove_method
        require require_relative raise freeze
        warn puts print p pp
        respond_to? method_defined? private_method_defined?
        public_method_defined? protected_method_defined?
        const_defined? instance_methods instance_variable_get
        lambda proc ruby2_keywords singleton_class
      ].to_set.freeze

      # Task 017's priority-ordered DSL list, scoped to the three this
      # task actually implements (enum/scope/delegate) -- attribute/
      # store_accessor/has_one/polymorphic/Concern/helper_method/mailer-
      # job entry points are explicitly deferred (docs/design/tasks/017-rails-dsl-expansion.md).
      GENERATED_METHOD_DSLS = %i[enum scope delegate].freeze

      # The calls this visitor turns into declarations of its own. Exempt
      # from the open-surface rule only when they actually did -- see
      # #record_open_surface.
      RECORDING_CALLS = (GENERATED_METHOD_DSLS + %i[alias_method attr_reader attr_writer attr_accessor]).to_set.freeze

      def initialize(lines)
        super()
        @lines = lines
        @pattern_depth = 0
        @pattern_bound_names = []
        @declarations = []
        @ancestor_facts = []
        @alias_facts = []
        @reference_candidates = []
        @generated_method_facts = []
        @open_surface_owners = Set.new
        # The ranges of receiverless calls this visitor read as a macro
        # and declared something from. A Set of ranges rather than of
        # names: `delegate` in one class body may be the macro and in
        # another an ordinary method the project defines, and a name would
        # silence both.
        @macro_call_ranges = Set.new
        @module_function_names = Set.new
        @included_hook_parameter = nil
        @block_owning_call = nil
        # How many block or lambda bodies enclose the node being visited.
        # A block's meaning belongs to the call that owns it, so
        # #record_open_surface looks at that call and not at what is
        # written inside -- see there.
        # One value, not six stacks. `Index::Cref` answers the questions
        # the recorders actually have -- what a `def` here declares, on
        # which surface, whether `self` is a Module, whether a
        # receiverless call can add to the surface -- and is saved and
        # restored around each nesting rather than pushed onto parallel
        # stacks a recorder has to reassemble. See its own docs, and
        # 037's C1 for the five register entries this arrangement cost.
        @cref = Index::Cref.top_level
        # Task 014: a fresh local-variable scope id per class/module body,
        # `def`, `class << self`, lambda and block — matching real Ruby's
        # own local-scoping boundaries, which Prism has already worked out
        # per scope node and publishes as `#locals`. A frame carries that
        # list, so #binding_scope can pick the frame that *binds* a name
        # rather than the innermost frame that happens to be open. See
        # there for why the difference is the whole point.
        @scope_counter = 0
        # Pushed by #in_scope, from the visit of each scope node —
        # including the ProgramNode, which is why this starts empty rather
        # than with a hand-made root frame that no node backs.
        @scopes = []
      end

      # A local-variable scope: the id references written in it are tagged
      # with, and the names Prism says this scope binds.
      # `owner` is the cref owner at the moment the frame was pushed, and
      # it is here rather than read from `@cref` at the point of use
      # because **a local variable has no owner**. Ruby's locals are
      # lexical, and a block that changes `self` does not change which
      # variable a name is:
      #
      #   $ ruby -e '
      #   module Mod; end
      #   def m
      #     ks = [1]
      #     Mod.module_eval do
      #       ks << 2
      #     end
      #     ks
      #   end
      #   p m
      #   '
      #   # => [1, 2]
      #   # ruby 3.4.10
      #
      # `#visit_block_node` gives an `instance_eval`/`class_eval`/
      # `module_eval`/`*_exec` block the receiver as its cref owner, which
      # is right for the macros those blocks contain and wrong for the
      # locals they close over. Identity is `owner#scope_id`, so the `ks`
      # inside came out `::Mod#2` and the same variable outside `nil#2`:
      # Rename rewrote the outer occurrences and left the inner one, which
      # then names nothing. `024.277`.
      Scope = Data.define(:id, :locals, :owner)

      # The one push site for all six scope-opening visits, so a frame
      # cannot be popped without having been pushed. `#visit_namespace`'s
      # own comment already states that rule -- it moved four pushes into
      # `#within_namespace` precisely so an early `return` above an
      # `ensure` could not unbalance them -- and `#visit_def_node` was
      # where the shape was still written until the guard was split out
      # of the method carrying the `ensure` (`024.258`, `024.265`).
      # The `begin` is the point rather than a habit: a method-level
      # `ensure` here would cover the push as well, so a node that turned
      # out not to answer `#locals` would pop a frame that was never
      # pushed -- which is the shape this method exists to make
      # unwritable, written inside it.
      def in_scope(node)
        @scopes.push(Scope.new(id: next_scope_id, locals: node.locals, owner: current_owner))
        begin
          yield
        ensure
          @scopes.pop
        end
      end

      # The file's own top-level scope. A frame from a node rather than a
      # hand-made one, so every scope in the stack is answered the same
      # way: `rescue => e` written at the top level and a regexp named
      # capture both bind here, and Prism records them on ProgramNode.
      def visit_program_node(node)
        in_scope(node) { super }
      end

      def visit_module_node(node)
        visit_namespace(node, kind: :module)
      end

      def visit_class_node(node)
        visit_namespace(node, kind: :class)
      end

      def visit_singleton_class_node(node)
        previous_cref = @cref
        @cref = @cref.in_singleton_class
        # A `class << self` body has its own visibility section, exactly
        # as a class/module body does (see #visit_namespace, which has
        # always pushed both). Without this, a bare `private` inside the
        # singleton block set the *enclosing class's* visibility frame and
        # never restored it, so every instance method declared after the
        # block was recorded private. That was latent until Rails action
        # detection began filtering on `visibility == :public`, at which
        # point those methods stopped being actions and their ivars
        # silently vanished from the corresponding views.
        in_scope(node) { super }
      ensure
        @cref = previous_cref
      end

      # A `def` inside a block whose owner nothing can name belongs to
      # that owner, not to the top level and not to the lexically
      # enclosing class. Recording it under `nil` put it in the same
      # bucket as every genuine top-level `def`, which is `024.80`'s
      # collision arriving from the other side. Its body is still walked;
      # only the declaration is withheld (`024.31`).
      #
      # **The guard is here because this method has no `ensure`.** It used
      # to sit above one, and a method-level `ensure` runs for an early
      # `return` as readily as for a fall-through -- so it undid three
      # saves the `return` had skipped. One of them was found and repaired
      # by hoisting that save above the guard (`@cref`, `024.122`); the
      # other two were still live, and both changed an answer:
      #
      # - the scope-frame stack was popped for a push that never
      #   happened, so the frame the *enclosing* construct opened was
      #   thrown away and every
      #   local after it was attributed one scope further out. Two
      #   unrelated locals then shared one `owner#scope_id`, which is the
      #   key `Rename::Planner` selects edits by -- renaming a class-body
      #   local rewrote a method-body local of the same name.
      # - `@included_hook_parameter` was restored from a local the
      #   `return` never assigned, so it was cleared to nil and the rest
      #   of an old-style concern's `self.included` stopped recognising
      #   `base.extend(...)` as the hook (`024.115`).
      #
      # Hoisting each save above the guard would have been the third
      # instance of one repair. Splitting instead pairs every save with
      # its restore structurally: the method that saves is the method that
      # returns, so no `return` can get between them, and a fourth save
      # added later cannot reintroduce the shape.
      def visit_def_node(node)
        return walk_nameless_def(node) if @cref.nameless_context?

        record_and_walk_def(node)
      end

      # The declaration is withheld and the body is still walked -- so it
      # is still a local-variable scope, and it still has to be its own
      # one. Ruby's scoping does not care that nobody can name the class:
      #
      #   $ ruby -e '
      #   Anon = Class.new do
      #     n = 5
      #     def a
      #       defined?(n)
      #     end
      #   end
      #   p Anon.new.a
      #   '
      #   # => nil
      #   # ruby 3.4.10
      #
      # A bare `return super` here reads as free and is not: without a
      # frame, two `def`s in one `Class.new do … end` share the block's
      # frame and their same-named locals are one variable.
      def walk_nameless_def(node)
        in_scope(node) { node.each_child_node { |child| child.accept(self) } }
      end

      # Every save this method's `ensure` restores is made here, above any
      # line that could exit -- `#within_namespace`'s discipline, applied
      # inside the method that carries the `ensure` rather than around it.
      # Nothing between the old position and this one reads
      # `@included_hook_parameter`, so hoisting it changes no answer; what
      # it removes is an invariant a reader had to check by eye. The scope
      # frame is not on this list at all any more -- `#in_scope` pairs its
      # own push and pop, so there is nothing for an `ensure` here to undo.
      def record_and_walk_def(node)
        previous_cref = @cref
        previous_hook_parameter = @included_hook_parameter

        owner_receiver = node.receiver
        # **A written receiver is a singleton definition, whatever it
        # names.** `def Foo.bar` defines a singleton method on `Foo`, and
        # this recorded an *instance* method -- so both answers inverted:
        # the call Ruby runs was reported and the call Ruby raises on was
        # accepted. Ten of the fourteen wrong-argument-count reports over
        # the 0.2.1 corpus were this shape, `net/http.rb`'s `HTTP.start`
        # among them (`024.32`).
        singleton = !owner_receiver.nil? || (@cref.declares_singleton? && owner_receiver.nil?)
        written_receiver = owner_receiver && !owner_receiver.is_a?(Prism::SelfNode)
        # **A receiver this parser cannot name is not the enclosing
        # class.** `#receiver_owner_name` answers nil for `def
        # <local>.name`, and the `|| current_owner` that stood behind it
        # turned "I cannot say" into that class -- inventing a singleton
        # method Ruby attaches to the singleton class of whatever the
        # local holds, and attributing every receiverless call in the
        # body to a class that is not `self` there.
        # `Index::Cref#in_unnameable_method` carries the Ruby session,
        # and nothing is recorded, which is the answer a block whose
        # owner cannot be named already gets (`024.31`, `024.251`).
        owner = written_receiver ? receiver_owner_name(owner_receiver) : current_owner
        unnameable_receiver = written_receiver && owner.nil?
        # **A top-level `def` belongs to `Object`, privately.** Recorded
        # with no owner at all, so neither an `Object` nor a `Kernel`
        # receiver reached it and a call to one got nothing from hover,
        # completion, signature help or go to definition (`024.230`).
        #
        #   $ ruby -e '
        #   def helper(a); end
        #   p [Object.private_instance_methods(false).include?(:helper), self.class]
        #   '
        #   # => [true, Object]
        #   # ruby 3.4.10
        #
        # Only the instance side. A top-level `def self.x` lands on
        # `main`'s singleton class rather than on `Object`'s, so it is
        # left exactly as it was:
        #
        #   $ ruby -e '
        #   def self.top_singleton; end
        #   p [Object.singleton_methods(false).include?(:top_singleton),
        #      self.singleton_class.instance_methods(false).include?(:top_singleton)]
        #   '
        #   # => [false, true]
        #   # ruby 3.4.10
        #
        # `@cref.top_level?` rather than `owner.nil?`: a `def` whose
        # receiver this parser cannot name also has no owner, and that one
        # is declined below rather than attributed to anything.
        top_level_object_method = owner.nil? && !singleton && !written_receiver && @cref.top_level?
        owner = "Object" if top_level_object_method

        unless unnameable_receiver
          symbol_id = Index::SymbolId.new(
            kind: singleton ? :singleton_method : :instance_method,
            owner: owner,
            name: node.name.to_s,
            discriminator: nil
          )

          # A pending entry means this def is the argument of a
          # `private def …`/`protected def …`, which names it explicitly and
          # so outranks whatever section is currently open.
          inline_visibility = @pending_visibility_names&.delete([owner, node.name.to_s])

          @declarations << Index::Declaration.new(
            symbol_id: symbol_id,
            location: Index::SourceLocation.to_range(node.location, @lines),
            # A singleton method carried no visibility at all until 0.2.9,
            # so `private` inside `class << self` and `private_class_method`
            # had nothing downstream to filter on and both were offered by
            # completion and accepted by the check (`024.105`; the booted
            # app raises `private method 'x' called for class`).
            #
            # The distinction is *why* it is singleton. Inside `class <<
            # self` the surrounding body's section applies, exactly as a
            # class body's does to a `def`. Written `def self.x` in a class
            # body it does not -- Ruby leaves that public however many
            # `private`s precede it, and 0.2.8's round confirmed this engine
            # already had that right.
            # A top-level `def` is *private* on Object -- see the Ruby
            # session above. Recorded public, `"str".helper` would be
            # offered and accepted, which Ruby refuses, so the owner and
            # the visibility travel together. `024.230`.
            visibility: top_level_object_method ? :private : visibility_for_definition(node, singleton,
                                                                                       inline_visibility),
            parameters: extract_parameters(node.parameters),
            origin: :source,
            body_source: node.body&.slice,
            name_location: Index::SourceLocation.to_range(node.name_loc, @lines)
          )
        end
        record_module_function_twin(node, owner) if @cref.module_function? && !singleton

        # The parameter `def self.included(base)` binds, so a
        # `base.extend(…)` in its body is recognisable as the concern
        # hook rather than as an ordinary `extend` on some object. Saved
        # at the top of this method with the other two.
        @included_hook_parameter =
          if singleton && %i[included prepended].include?(node.name)
            node.parameters&.requireds&.first&.name
          end

        record_unmodelled_hook_surface(node) if singleton && %i[included prepended].include?(node.name)

        # Tracks "we are inside a method body", so a `private :target`
        # written there -- which never runs at class level in Ruby -- does
        # not retroactively rewrite a declaration. Restored rather than
        # cleared, since `private def foo; ...; end` nests a def inside a
        # call inside a def in the argument-form case.
        # Inside `def self.x` self is still the class, so a `private`
        # written there is Module's, exactly as in the body around it.

        # Same frame discipline as blocks and `class << self`: a bare
        # `private` written inside a method body must not rewrite the
        # class's open section. `@in_method_body` already stopped the
        # `private :x` argument form from doing this; the argumentless
        # form went straight to `update_visibility` and was unguarded, so
        # `def wrapper; private; end` privatised every method declared
        # after it. Guarding one call site was the symptom fix -- the
        # frame is the cause.
        #
        # A receiver this parser could not name gets a frame of its own:
        # `self` in that body is the object the expression evaluated to,
        # so a receiverless call written there is not a call on the
        # enclosing class and must not be reported against it, and a
        # `def` written there has nowhere to go either.
        # **Ruby evaluates the receiver of `def <expr>.name` in the
        # enclosing scope**, and the local is not visible inside the
        # singleton body at all:
        #
        #   $ ruby -e '
        #   class Runner
        #     def go
        #       ty = Object.new
        #       def ty.reads_outer
        #         defined?(ty)
        #       end
        #       [ty.reads_outer, binding.local_variable_defined?(:ty)]
        #     end
        #   end
        #   p Runner.new.go
        #   '
        #   # => [nil, true]
        #   # ruby 3.4.10
        #
        # So it is visited here -- above the `@cref` switch and outside
        # the frame `#in_scope` pushes -- rather than as one of the
        # children below. Walked below, it took this method's cref, and a
        # receiver this parser cannot name has *no owner*: `def ty.outer`
        # recorded `ty` as `nil#3` while the `ty =` that created it was
        # `::Runner#3`. One variable, two identities, and Rename rewrote
        # every mention except the one on the `def` line -- `024.28`'s
        # failure, a WorkspaceEdit that leaves the file not running.
        # `024.271`.
        #
        # Visited before the push rather than with the frame temporarily
        # lifted: there is no frame to take off and put back, so nothing
        # here needs an `ensure` of its own -- which is the shape
        # `024.258` and `024.259` exist to keep out of this method.
        owner_receiver&.accept(self)

        @cref = unnameable_receiver ? @cref.in_unnameable_method : @cref.in_method(singleton: singleton)
        # What `super` did while this was `#visit_def_node` itself:
        # `Prism::Visitor#visit_def_node` *is* this line. `#visit_namespace`
        # already spells it out, and for the same reason -- the body has to
        # be walked from a method that is not the overridden visit.
        in_scope(node) do
          node.each_child_node { |child| child.accept(self) unless child.equal?(owner_receiver) }
        end
      ensure
        @cref = previous_cref
        @included_hook_parameter = previous_hook_parameter
      end

      # A block whose body becomes an *instance* method: `self` inside it
      # is an instance, whatever self is where the call is written.
      # `def self.extension` in Ruby 3.4.7's own `rdoc/markdown.rb` is the
      # shape -- it wraps `define_method` blocks that call the class's
      # *instance* `extension?`. Reading those bodies with the enclosing
      # `def self.`'s own self reported `extension?` as unknown and
      # `extension` as taking one argument too few.
      #
      # `define_singleton_method` is deliberately absent: its body really
      # does run with the class as self, so it inherits correctly.
      INSTANCE_SELF_BLOCK_CALLS = %i[define_method].freeze

      # `instance_eval`/`instance_exec` set self to their *receiver*, so
      # neither "always instance" nor "always inherit" is Ruby's rule.
      # Receiverless -- or on a constant -- the receiver is the class, and
      # 0.1.14's blanket entry reported `instance_eval { attr_accessor :x }`
      # for a macro as legal as the line above it. On an expression the
      # receiver is an object, and inheriting the enclosing class-level
      # self reports the instance methods its body calls.
      RECEIVER_SELF_BLOCK_CALLS = %i[instance_eval instance_exec].freeze

      def block_self_is_module(node)
        # A `define_method` block defines a *singleton* method only when
        # the call is written directly in a `class << self` body. Called
        # from inside a `def` -- including a `def` in that body -- self at
        # that moment is the class object, so it defines an ordinary
        # instance method and the block's self is an instance; an explicit
        # receiver says the same. `@singleton_context_stack` answers only
        # "would an unqualified `def` here be a singleton method", and
        # `visit_def_node` never pushes it, so reading it alone reported
        # the bodies of Thor's, minitest's and `rails/engine.rb`'s
        # generated methods.
        if INSTANCE_SELF_BLOCK_CALLS.include?(node.name)
          return node.receiver.nil? && !@cref.in_method_body? && @cref.declares_singleton?
        end

        return nil unless RECEIVER_SELF_BLOCK_CALLS.include?(node.name)

        # Receiverless, the receiver is the enclosing self, so inherit it
        # -- `nil`, not `true`. Answering "a module" said the class even
        # inside an instance method, where Ruby's answer is the instance,
        # and reported every instance method such a block calls. In a
        # class body the inherited value is already `true`, which is why
        # no fixture there could tell the two apart.
        #
        # With any receiver written out, the body's self is *that object*,
        # which this visitor cannot name -- it tracks whether self is a
        # module, never which one. Reading it as an instance is the
        # direction that resolves the helper methods such a block calls;
        # inheriting class-level self reported them instead.
        #
        # **The explicit-receiver term was removed in 0.2.13.** It read
        # `node.receiver.nil? ? nil : false`, and `024.33`'s fix took over
        # every case it decided: an eval-family call with a receiver now
        # gets `Cref#in_eval_block`, which carries the constant when there
        # is one and `nil` when there is not. Removing the term left the
        # whole suite green except the mutation manifest, which is how it
        # was found -- an unpinned behavioural line is a defect in its own
        # right, and this one had stopped being reachable rather than
        # stopped being pinned.
        nil
      end

      # `private attr_reader :x` reaches the attr recorder as a *nested*
      # call, visited while `private`'s arguments are. Its own
      # `@visibility_stack` frame still says :public, because the section
      # was never opened -- so the visibility has to travel with the
      # nesting, the way `@pending_visibility_names` carries `private def`.
      def visit_call_node(node)
        read_as_a_macro = false
        # The call a block belongs to, so `#visit_block_node` can ask what
        # its receiver is: Prism hands the visitor a `BlockNode` with no
        # way back to the call that owns it. Set here and restored on the
        # way out, so a nested call inside a block sees its own.
        #
        # `ensure` on the method body rather than a wrapper, because every
        # `return super` below has to keep resolving to `Prism::Visitor`'s
        # own `#visit_call_node`.
        previous_block_owning_call = @block_owning_call
        @block_owning_call = node

        if node.receiver.nil?
          if node.arguments.nil?
            update_visibility(node)
          else
            apply_visibility_arguments(node)
          end
          apply_class_visibility_arguments(node) if CLASS_VISIBILITY_MODIFIERS.key?(node.name)
          if node.name == :module_function && node.arguments && @cref.module_owner? && !@cref.declares_singleton?
            apply_module_function_arguments(node)
          end
          record_ancestor_call(node) if ANCESTOR_RELATIONS.key?(node.name)
          record_alias_method_call(node) if node.name == :alias_method
          declared_before = @declarations.size
          record_generated_methods(node) if current_owner && GENERATED_METHOD_DSLS.include?(node.name)
          record_attribute_methods(node) if current_owner && ATTRIBUTE_DSLS.key?(node.name)
          # A recognised DSL that recorded nothing is not a recognised
          # call. `attr_reader(*NAMES)` and `delegate(*NAMES, to: :inner)`
          # produce no declarations -- their recorders need literal
          # arguments -- and the surface stayed closed anyway because the
          # *name* was on the exempt list, so `Bag#a` was reported missing.
          # What matters is whether anything was actually recorded.
          read_as_a_macro = @declarations.size > declared_before
          wrapped_visibility = inline_attribute_visibility_for(node)
        end
        # Before `#record_open_surface`, not after: a `class_methods do`
        # block *is* read -- its methods are recorded as the
        # `ClassMethods` module it is sugar for -- so marking the
        # concern's surface open said the opposite. It did, and the cost
        # was every class including that concern losing instance-side
        # checking entirely: the spelled-out form reported
        # `Post.new.total_garbage` and the block form reported nothing.
        return visit_concern_class_methods(node) if concern_class_methods?(node)

        record_concern_hook(node)

        # Outside the receiverless branch: `singleton_class.send` and
        # `self.class_eval` metaprogram this owner too (see there).
        record_open_surface(node, read_as_a_macro)
        # **The candidate is recorded, and the report is what stops**
        # (`024.327`). A recognised DSL that recorded something leaves the
        # surface *closed*, correctly -- and that is exactly what exposed
        # the macro's own call to the undefined-method check, which
        # reported `W has no method named 'delegate'` on a class whose
        # `size` it had declared from that very call. Either the call is a
        # macro this engine understands, in which case reporting it is
        # wrong, or it is not, in which case declaring from it was.
        #
        # **The first fix dropped the candidate, and that was too much.**
        # The candidate is what hover, go to definition, references and
        # highlight all read, and `#record_attribute_methods` bumps the
        # same counter -- so `attr_reader` lost its RBS documentation and
        # its definition at `module.rbs:320`, and a project that defines
        # its own `scope` or `delegate` lost all four answers on the call.
        # None of that was the defect. Marking the range leaves every
        # other feature exactly as it was and stops only the report, which
        # is the whole of what was wrong. Found by cold review.
        #
        # An unrecognised class-body call is silent for a different
        # reason and stays that way: it opens the surface.
        record_method_call_candidate(node)
        record_macro_call_range(node) if read_as_a_macro

        # `module_function def a; end`. The argument is a definition, not a
        # name, so `#apply_module_function_arguments` cannot see it -- and
        # it runs before the `def` is visited in any case. Visiting the
        # arguments under an open `module_function` makes the same two
        # recorders that handle the section form handle this one, rather
        # than a third path that can disagree with them. Rails writes it:
        # `action_cable.rb:77` is `module_function def server`, and
        # `ActionCable.server` was reported as missing.
        if inline_module_function?(node)
          previous_cref = @cref
          @cref = @cref.in_module_function
          begin
            return super
          ensure
            @cref = previous_cref
          end
        end

        if wrapped_visibility
          previous = @inline_attribute_visibility
          @inline_attribute_visibility = wrapped_visibility
          begin
            return super
          ensure
            @inline_attribute_visibility = previous
          end
        end
        # Pushed around the children, not the candidate above: the call
        # itself is written where it is written. `nil` means the block
        # does not change self -- see #block_self_is_module for which
        # calls do.
        #
        # "Children" is the whole call, arguments included, not just the
        # block body: `define_method(:x, &maker)` and
        # `Other.instance_exec(helper) { }` resolve their arguments under
        # the pushed frame too, and report them. Identical on 0.1.14, and
        # narrowing it to the block node is its own change.
        block_self = node.block && block_self_is_module(node)
        return super if block_self.nil?

        previous_cref = @cref
        @cref = @cref.with(self_is_module: block_self)
        begin
          super
        ensure
          @cref = previous_cref
        end
      ensure
        @block_owning_call = previous_block_owning_call
      end

      # `ActiveSupport::Concern`'s `class_methods do ... end` is sugar for
      # `module ClassMethods ... end`, and the gem itself says so:
      #
      #   $ ruby -e '
      #   gem "activesupport"; require "active_support"
      #   require "active_support/concern"
      #   module Taggable
      #     extend ActiveSupport::Concern
      #     class_methods do
      #       def cm_public; :cm; end
      #     end
      #   end
      #   p Taggable.const_defined?(:ClassMethods)          # => true
      #   p Taggable::ClassMethods.instance_methods(false)  # => [:cm_public]
      #   '
      #   # ruby 3.4.10, activesupport 8.1.3.1
      #
      # Recorded as that module rather than given a rule of its own, so
      # the two spellings of one thing cannot disagree -- and they did:
      # the block's methods landed on the concern's *instance* side, so
      # `include Taggable` offered `cm_public` on every instance while
      # the spelled-out form was handled correctly (`024.104`). Four
      # features answered from the same wrong record.
      # `@cref.module_owner?` for the same reason `#extend_self?` has it:
      # `ActiveSupport::Concern` is a module thing, and a *class* writing
      # `class_methods do` raises `NoMethodError`. Declaring a
      # `ClassMethods` module Ruby never creates also silenced a report
      # this engine used to make about the `class_methods` call itself.
      def concern_class_methods?(node)
        node.name == :class_methods && node.receiver.nil? && node.block.is_a?(Prism::BlockNode) &&
          current_owner && !@cref.in_method_body? && @cref.module_owner?
      end

      def visit_concern_class_methods(node)
        absolute_name = qualify("ClassMethods")

        # A concern may open the block more than once -- `ActionText::
        # Serialization` does, the second only to `alias_method` -- and
        # each emitted its own `module` declaration with the same
        # `SymbolId`, so the outline showed two identical `ClassMethods`
        # nodes each listing every method. One declaration per module,
        # which is what the spelled-out form produces.
        already_declared = @declarations.any? do |declaration|
          declaration.symbol_id.kind == :module && declaration.symbol_id.name == absolute_name
        end
        return visit_concern_class_methods_body(node, absolute_name) if already_declared

        @declarations << Index::Declaration.new(
          symbol_id: Index::SymbolId.new(kind: :module, owner: current_owner, name: absolute_name,
                                         discriminator: nil),
          location: Index::SourceLocation.to_range(node.location, @lines),
          visibility: nil, parameters: [], origin: :source,
          name_location: Index::SourceLocation.to_range(node.message_loc || node.location, @lines)
        )

        visit_concern_class_methods_body(node, absolute_name)
      end

      # The block body is the module body, so it opens a namespace and
      # *not* a block frame: a `def` in `module ClassMethods` is written
      # at depth zero, and `#defines_surface?` reads that depth.
      #
      # The children are walked here rather than dispatched through
      # `#visit_block_node` with a flag telling it not to do its job.
      # `Prism::Visitor#visit_block_node` *is* this line, so the two are
      # identical in effect, and `#visit_namespace` already uses this
      # construction. What goes away is a mutable one-shot flag set here
      # and read-and-cleared eighty lines below, plus the convention that
      # both ends agree it is cleared exactly once.
      def visit_concern_class_methods_body(node, absolute_name)
        within_namespace(absolute_name, node.block, module_owner: true) do
          node.block.each_child_node { |child| child.accept(self) }
        end
      end

      # Whether this block's owning call iterates a *literal* -- and so
      # provably keeps self, whatever the method is called. `%w[a b].each`,
      # `[1].each`, `(1..3).map`. A shape rather than a list of method
      # names, for the reason `#record_open_surface` gives about setters:
      # a list can only ever hold the calls somebody has already seen.
      LITERAL_RECEIVER_NODES = [
        Prism::ArrayNode, Prism::RangeNode, Prism::IntegerNode,
        Prism::HashNode, Prism::StringNode, Prism::SymbolNode
      ].freeze

      # `instance_eval`/`class_eval`/`module_eval` and their `_exec`
      # spellings all set self to their receiver, so a macro inside is a
      # call on *that*. Returns the owner name, `:unnameable` for a
      # receiver this parser cannot name, or nil when the call is not one
      # of these.
      EVAL_BLOCK_CALLS = %i[instance_eval instance_exec class_eval class_exec module_eval module_exec].freeze

      # A block that *creates* a class or module: its body defines on the
      # new one, which has no name until the assignment completes and may
      # never get one. Ruby:
      #
      #   $ ruby -e '
      #   class Outer
      #     Seed = Struct.new(:x) do
      #       attr_reader :label
      #     end
      #   end
      #   p [Outer.new.respond_to?(:label), Outer::Seed.new(1).respond_to?(:label)]
      #   '
      #   # => [false, true]
      #   # ruby 3.4.10
      #
      # The accessor belongs to the Struct, and it was being recorded on
      # `Outer` -- the direction that *invents* a member, which this
      # engine refuses everywhere else (`024.31`).
      CLASS_CREATING_BLOCK_RECEIVERS = {
        "Class" => :new, "Module" => :new, "Struct" => :new, "Data" => :define
      }.freeze

      def creates_a_class?
        call = @block_owning_call
        return false unless call

        name = call.receiver && raw_constant_name(call.receiver)
        CLASS_CREATING_BLOCK_RECEIVERS[Index::SymbolId.bare_name(name.to_s)] == call.name
      end

      def eval_block_owner
        call = @block_owning_call
        return nil unless call && EVAL_BLOCK_CALLS.include?(call.name)

        receiver = call.receiver
        # Receiverless, the receiver is the enclosing self and the cref is
        # already right -- `instance_eval { attr_accessor :x }` in a class
        # body is as legal as the line above it.
        return nil if receiver.nil? || receiver.is_a?(Prism::SelfNode)

        raw_constant_name(receiver) ? receiver_owner_name(receiver) : :unnameable
      end

      def iterates_a_literal?(_node)
        receiver = @block_owning_call&.receiver
        return false if receiver.nil?

        LITERAL_RECEIVER_NODES.any? { |klass| receiver.is_a?(klass) }
      end

      def visit_block_node(node)
        # A visibility section opened inside a block belongs to that
        # block. `concerning :Auth do private; def authenticate; end end`
        # and `included do ... end` and `class_eval do ... end` all run
        # their `private` against a different module than the enclosing
        # class, so it cannot reach the class body -- yet without a frame
        # here it set the enclosing frame and never restored it, and every
        # method written after the block was recorded private. With
        # actions now filtered on `visibility == :public`, that silently
        # dropped real controller actions and their ivars vanished from
        # the corresponding views.
        #
        # The frame *inherits* rather than resetting to :public: a plain
        # iterator block does not open a new cref, so a `def` inside it
        # really does take the enclosing section's visibility. Inheriting
        # keeps that case right while still containing the leak.
        block_cref =
          if creates_a_class?
            @cref.in_eval_block(nil)
          elsif (owner = eval_block_owner)
            @cref.in_eval_block(owner == :unnameable ? nil : owner)
          else
            @cref.in_block(shares_self: iterates_a_literal?(node))
          end
        # Whether a frame was opened is asked of the cref rather than
        # re-derived here: `#in_block(shares_self: true)` returns the
        # *same* cref, because a block that provably keeps self does not
        # open one. Restoring unconditionally threw that away -- `Cref`
        # is an immutable value, so the section a `private` inside such a
        # block opens lives only in `@cref`, and the `ensure` overwrote
        # it. `[1].each { private }; def x; end` recorded `x` public
        # where Ruby makes it private (`024.111`).
        #
        # Both locals are set *after* the cref is built and before it is
        # installed, so an `ensure` reached from a raise part-way through
        # building it finds `opened_a_frame` false and leaves the
        # untouched `@cref` alone -- rather than needing a guard here
        # that no example could ever reach.
        opened_a_frame = !block_cref.equal?(@cref)
        previous_cref = @cref
        @cref = block_cref
        in_scope(node) { super }
      ensure
        @cref = previous_cref if opened_a_frame
      end

      # A lambda body is a block that Prism models separately, and it is
      # the shape that made the block rule matter: `DEFAULT = -> {
      # helper_thing }` in a class body silenced every report about that
      # class.
      def visit_lambda_node(node)
        previous_cref = @cref
        @cref = @cref.in_block
        # `->(v) {}` binds `v`, exactly as `lambda { |v| }` does, and this
        # was the one scope node with no frame. The two spellings of one
        # construct therefore answered differently about their own
        # parameter: the arrow form shared the enclosing method's frame,
        # so Find References offered the lambda's `v` among the method's
        # `v`s and Rename rewrote it (`024.261`, `024.263`).
        in_scope(node) { super }
      ensure
        @cref = previous_cref
      end

      def visit_constant_read_node(node)
        record_reference(:constant, node.name.to_s, node.location)
        super
      end

      def visit_constant_path_node(node)
        target = raw_constant_name(node)
        # `node.name_loc` is just the last segment ("Bar" in `Foo::Bar`),
        # not the whole compound path -- using the whole path here (the
        # previous behavior) meant a rename of `Bar` to `Container` would
        # rewrite every `Foo::Bar.something` reference to bare
        # `Container.something`, silently stripping the `Foo::` prefix
        # instead of touching only the identifier being renamed (found by
        # the Task 014-018 independent review; see also #visit_namespace's
        # matching fix for the declaration side of the same class of bug).
        record_reference(:constant, target, node.name_loc) if target
        super
      end

      def visit_local_variable_read_node(node)
        record_local_variable(node.name, node.location)
        super
      end

      # Ruby's shorthand -- `{ name: }`, `take(name:)` -- which Prism
      # models as an `ImplicitNode` wrapping the read it stands for. The
      # read it wraps carries the *whole* `name:` token as its location,
      # colon included, because that is all there is: one token is both
      # the key and the value.
      #
      #   $ ruby -rprism -e '
      #   n = Prism.parse(%q(name = 1; { name: })).value.statements.body.last.elements.first
      #   p [n.key.slice, n.value.class, n.value.value.class, n.value.value.slice]
      #   '
      #   # => ["name:", Prism::ImplicitNode, Prism::LocalVariableReadNode, "name:"]
      #   # ruby 3.4.10
      #
      # Recorded unchanged, with the flag saying so, rather than trimmed
      # to the identifier: trimming makes a substitution rewrite the
      # *key*, which for a hash silently changes the data and for a
      # keyword argument names a parameter the callee does not have.
      # `Rename::Planner` is the one reader that has to care, and it
      # expands. Recorded here rather than in
      # `#visit_local_variable_read_node`, which cannot see its parent.
      #
      # Only the local-variable value is taken over; a shorthand standing
      # for a *method* call goes to `super` and is recorded by
      # `#visit_call_node` from its `message_loc`, which is the
      # identifier alone. That is a narrower range than this one and it
      # has the same expansion problem when the method is renamed; it is
      # left as it was and recorded, because changing it changes an
      # answer this entry did not measure.
      def visit_local_variable_write_node(node)
        record_local_variable(node.name, node.name_loc, write: true)
        super
      end

      # Prism spells one variable's bindings with six node kinds and only
      # the two above were recorded, so Find References answered with a
      # subset and Rename rewrote that subset -- leaving `n += 1` behind
      # after renaming `n`, which is a file that no longer runs
      # (`024.260`, `024.266`). `semantic_tokens.rb` already enumerates
      # the same six.
      def visit_local_variable_operator_write_node(node)
        record_local_variable(node.name, node.name_loc, write: true)
        super
      end

      def visit_local_variable_or_write_node(node)
        record_local_variable(node.name, node.name_loc, write: true)
        super
      end

      def visit_local_variable_and_write_node(node)
        record_local_variable(node.name, node.name_loc, write: true)
        super
      end

      # **A parameter binds a local, and its own name was not an
      # occurrence of it.** Each scope frame is seeded from Prism's
      # `#locals`, which lists the parameter names, so a *use* of `arg`
      # resolved to the right frame from the start -- and nothing ever
      # recorded the `arg` written in the signature. Every reader of
      # those occurrences was therefore one short: documentHighlight
      # answered with the body alone, and Rename rewrote the body alone,
      # handing back
      #
      #   def g(arg)
      #     renamed + 1
      #   end
      #
      # which parses and raises `NameError`. That is the defect 0.2.17
      # shipped a fix for, reached through a binding form that had never
      # been recorded -- and Rename could not have refused instead,
      # because an occurrence nothing records is one nothing can miss.
      #
      # Recorded as a write: the binding site is where the value arrives.
      #
      # The keyword forms need `#chop`, because Prism's `name_loc` for
      # them spans the colon as well:
      #
      #   $ ruby -rprism -e '
      #   n = Prism.parse("def f(key:); end").value.statements.body.first
      #   p n.parameters.keywords.first.name_loc.slice
      #   '
      #   # => "key:"
      #   # ruby 3.4.10
      #
      # `#record_local_variable` compares the range against the name and
      # declines when they differ, so an unchopped keyword would have been
      # dropped silently rather than recorded wrong -- the safe half of a
      # guard doing the work a visitor should.
      def visit_required_parameter_node(node)
        record_parameter_binding(node)
        super
      end

      def visit_optional_parameter_node(node)
        record_parameter_binding(node)
        super
      end

      def visit_rest_parameter_node(node)
        record_parameter_binding(node)
        super
      end

      def visit_keyword_rest_parameter_node(node)
        record_parameter_binding(node)
        super
      end

      def visit_block_parameter_node(node)
        record_parameter_binding(node)
        super
      end

      # A bare `*`, `**` or `&` binds nothing nameable, and Prism gives
      # those a nil name.
      #
      # **Which location holds the name is not uniform.** A
      # `RequiredParameterNode` has no `name_loc` at all -- its own
      # `location` is the name -- while the other kinds have one:
      #
      #   $ ruby -rprism -e 'ps = Prism.parse("def f(a, b = 1); end").value.statements.body.first.parameters
      #                      p ps.requireds.first.respond_to?(:name_loc)
      #                      p ps.optionals.first.name_loc.slice'
      #   # => false
      #   # => "b"
      #   # ruby 3.4.10
      #
      # Reaching for `name_loc` on all of them raised `NoMethodError`
      # inside the walk, which took hover, signature help, the arity check
      # and both inlay hints down with it: thirteen examples, one cause.
      # `#record_local_variable` compares the range against the name and
      # declines when they differ, so a location picked wrongly here is
      # dropped rather than recorded wrong.
      #
      # **The two keyword nodes are not here, deliberately.** `def m(by:)`
      # spells the method's interface: rewriting that `by` renames the
      # keyword every caller passes, not the local. `024.273` names the
      # direction and names the exception, and `024.272` is the reason.
      def record_parameter_binding(node)
        return unless node.name

        location = node.respond_to?(:name_loc) && node.name_loc ? node.name_loc : node.location
        record_local_variable(node.name, location, write: true)
      end

      # `a, b = 1, 2`, a `for` variable, `rescue => e`, a pattern capture
      # and a regexp named capture all arrive here. This node has no
      # `#name_loc`, so its own location is the name -- except where it
      # is not, which is what #record_local_variable checks.
      #
      # **The underscore is a rule no question asked at one range could
      # answer.** A pattern may bind the same name twice only when the
      # name begins with an underscore, so two edits that are each
      # exactly the name combine into a file that does not parse:
      #
      #   $ ruby -e '
      #   ["case [1, 2]; in [_a, _a] then :ok; end",
      #    "case [1, 2]; in [zz, zz] then :ok; end"].each { |src|
      #     begin
      #       p eval(src)
      #     rescue SyntaxError => e
      #       p e.message.include?("duplicated variable name")
      #     end
      #   }
      #   '
      #   # => :ok
      #   # => true
      #   # ruby 3.4.10
      #
      # `Rename::Planner` builds one `newText` per range and cannot see
      # that two of its ranges share a pattern, so the decline is here,
      # and it is written about the name rather than about patterns
      # because that is the whole of what Ruby's own rule keys on.
      # Declining an underscore-prefixed *target* costs nothing anybody
      # had: until this release no target spelling was recorded at all.
      # A plain `_a = 1` write is unaffected -- that is a write node, and
      # writes may repeat freely.
      # **A target assigns.** Every binding form that is not a plain
      # write node arrives here -- a multiple assignment's left-hand
      # side, a `for` variable, every pattern binding, `x => bound`,
      # `rescue => e` -- and 0.3.0's `write` flag was set only by the
      # four write-node visitors, so `a, b = 1, 2` recorded `a` as a
      # read: no inlay hint, and `Read` where documentHighlight should
      # say `Write`.
      def visit_local_variable_target_node(node)
        record_local_variable(node.name, node.location, write: true) unless declined_underscore?(node.name)
        super
      end

      # **Only inside a pattern.** A pattern may bind one name twice when it
      # begins with an underscore, and each of those two ranges really is
      # the name -- so nothing asked *at a range* can see that it is the
      # pair that would be illegal, and `Rename::Planner` builds one
      # `newText` per range. Ruby:
      #
      #   $ ruby -e '
      #   ["_a, _a = 1, 2; [_a]",
      #    "case [1, 2]; in [_a, _a] then :ok; end",
      #    "case [1, 2]; in [zz, zz] then :ok; end"].each do |src|
      #     begin
      #       eval(src)
      #       puts "legal"
      #     rescue SyntaxError
      #       puts "SyntaxError"
      #     rescue StandardError
      #       puts "legal"
      #     end
      #   end
      #   '
      #   # => legal
      #   # => legal
      #   # => SyntaxError
      #   # ruby 3.4.10
      #
      # A multiple assignment, a `for` variable and a `rescue => _e` cannot
      # produce that pair, and 0.2.17 declined all of them alike -- which
      # cost documentHighlight and Find References an occurrence apiece for
      # a rule that does not reach them. `024.274`.
      # **Declining to record it is not the same as forgetting it.** The
      # occurrence is left out on purpose; the *name* is kept, because
      # `Rename` has to refuse a rename it cannot carry out. `024.296`.
      def declined_underscore?(name)
        declined = @pattern_depth.positive? && name.to_s.start_with?("_")
        @pattern_bound_names << name.to_s if declined
        declined
      end

      # `MatchRequiredNode` (`h => [a]`) and `MatchPredicateNode`
      # (`h in [a]`) are a pattern and nothing else, so the whole node
      # can carry the depth.
      %i[match_required_node match_predicate_node].each do |suffix|
        define_method(:"visit_#{suffix}") do |node|
          @pattern_depth += 1
          super(node)
        ensure
          @pattern_depth -= 1
        end
      end

      # **An `in` clause's body is not a pattern.** Raising the depth
      # around the whole clause was argued as taking nothing away --
      # every underscore binding "in here" was declined before -- and
      # that reading of "in here" was wrong: the clause's *body* holds
      # ordinary statements, so `_p, _q = 1, 2` written inside a branch
      # was declined as a pattern target. Renaming from a read then
      # rewrote the reads and left the assignment, which changes what
      # the method returns.
      #
      # A guard is inside `node.pattern` -- Prism wraps the pattern in an
      # `IfNode` whose predicate is the guard -- so raising the depth
      # around the pattern alone still covers every child a guard can
      # hide behind, which is what the previous comment was worried
      # about.
      def visit_in_node(node)
        @pattern_depth += 1
        begin
          visit(node.pattern)
        ensure
          @pattern_depth -= 1
        end
        visit(node.statements)
      end

      # **A regexp named capture binds a local, and Prism points at the
      # whole literal.**
      #
      #   $ ruby -e '
      #   /(?<where>\d+)/ =~ "a12"
      #   p [where, defined?(where)]
      #   '
      #   # => ["12", "local-variable"]
      #   # ruby 3.4.10
      #
      # The `LocalVariableTargetNode`s a `MatchWriteNode` carries all have
      # the regexp's own range, so `#record_local_variable`'s "the range
      # really is the name" guard declined every one (`024.260`) --
      # rightly, because rewriting that range destroys the pattern. What
      # that left is the shape `024.280` records: the *uses* recorded and
      # the *binding* not, so a rename rewrote the uses and left the
      # capture, and the renamed name became a defined-but-nil local
      # rather than an error.
      #
      # The name is written literally inside the pattern, so its own range
      # is computable, and rewriting *that* is what Ruby needs. Ruby
      # spells a named group two ways and both are handled; anything else
      # -- an interpolated pattern, a name the scan cannot find -- is left
      # declined, which is where this started.
      def visit_match_write_node(node)
        pattern = node.call.receiver
        if pattern.respond_to?(:content_loc)
          node.targets.each do |target|
            # Prism does not always hand back the literal. `/(?<n>x)/o
            # =~ s` -- with a flag -- gives the target the *name's* own
            # range, and `#visit_local_variable_target_node` has already
            # recorded it; recording it again here is a duplicate, which
            # is two identical edits in one WorkspaceEdit and one
            # occurrence counted twice by Find References.
            next if target.location.slice == target.name.to_s

            location = capture_name_location(pattern, target.name.to_s)
            record_local_variable(target.name, location, write: true) if location
          end
        end
        super
      end

      # The range of `name` inside the regexp's own source, or nil.
      #
      # Only the first spelling of a given name: Ruby refuses a pattern
      # that binds one twice unless it begins with an underscore, and
      # those are declined a layer up (`024.274`).
      def capture_name_location(pattern, name)
        content = pattern.content_loc
        text = content.slice
        offset = nil
        ["(?<#{name}>", "(?'#{name}'"].each do |opening|
          found = text.index(opening)
          next unless found

          offset = found + opening.bytesize - name.bytesize - 1
          break
        end
        return nil unless offset

        Prism::Location.new(pattern.send(:source), content.start_offset + offset, name.bytesize)
      end

      # **A value nobody wrote.** `{a:}`, `helper(limit:)` and `in {a:}`
      # are all one construct -- a hash entry whose value is omitted --
      # and Prism says so by wrapping the value it supplied in an
      # `ImplicitNode`. The range that node carries is the *key's*, so
      # rewriting it is not renaming the local:
      #
      #   $ ruby -e '
      #   require "prism"
      #   { "in {a:}" => "case h\nin {a:}\nend\n",
      #     "h = {a:}" => "a = 1\nh = {a:}\n",
      #     "helper(limit:)" => "limit = 1\nhelper(limit:)\n" }.each { |label, src|
      #     Prism.parse(src).value.breadth_first_search { |node|
      #       next false unless node.is_a?(Prism::ImplicitNode)
      #       p [label, node.value.class.name.split("::").last, node.value.location.slice]
      #       false
      #     }
      #   }
      #   '
      #   # => ["in {a:}", "LocalVariableTargetNode", "a"]
      #   # => ["h = {a:}", "LocalVariableReadNode", "a:"]
      #   # => ["helper(limit:)", "LocalVariableReadNode", "limit:"]
      #   # ruby 3.4.10
      #
      # **Only the target, and the session above is the argument for
      # that.** Two of those three ranges carry the colon, so
      # #record_local_variable's "is this range the name?" comparison
      # already answers *no* for them -- correctly, not by luck: a range
      # holding `limit:` is not the name, and that is the whole of what
      # the comparison asks. The pattern is the shape where the range
      # **is** the bare name, so the comparison answers yes and hands
      # Rename a key to rewrite; a `case` with an `else` then takes the
      # other branch with nothing raised. That one needs a question the
      # text cannot answer, and Prism has already answered it one node
      # up.
      #
      # Declining the read spellings here as well would be a line no
      # example could fail on, which this project treats as a defect of
      # its own -- and the property it would be insuring against, that
      # both read ranges carry the colon, is not left to memory: the
      # session above is re-run by `scripts/check_interpreter_sessions.rb`
      # on every suite run, so a Prism that stopped including the colon
      # fails a check rather than quietly widening a rename.
      #
      # Only the local-variable target is skipped. `{a:}` where `a` is a
      # method still walks its `CallNode`, so the call is still a
      # reference.
      # **Two spellings arrive here and they want opposite answers**, which
      # is why one method makes both decisions rather than two methods
      # each making one. Two clusters of this release wrote a
      # `#visit_implicit_node` independently and the second silently
      # replaced the first, so the expansion below was dead code until the
      # suite said so.
      #
      # A *target* binds FROM the key: `in {a:}` matches the key `a` and
      # binds a local of that name. Expanding it would rewrite the key and
      # change which key is matched, so the site is not recorded at all
      # and `024.272` publishes what that costs.
      #
      # A *read* is the value half: `{a:}` is `{a: a}` and `f(a:)` is
      # `f(a: a)`. Here the whole `a:` is the site and the edit *expands*
      # it, which is the one shape where replacing the recorded range with
      # a longer string is right rather than lossy.
      def visit_implicit_node(node)
        value = node.value
        return if value.is_a?(Prism::LocalVariableTargetNode)

        unless value.is_a?(Prism::LocalVariableReadNode)
          super
          return
        end

        # Through `binding_scope`, like every other local reference: the
        # frame that *binds* the name, not the innermost one that is open.
        # This read was written against `current_scope_id`, which the
        # scope-frame change replaced, and the two arrived in one release.
        frame = binding_scope(value.name)
        return unless frame

        record_reference(:local_variable, value.name.to_s, node.location,
                         scope_id: frame.id, owner: frame.owner, implicit_hash_value: true,
                         # A read: `{ name: }` passes the local's value.
                         # This reached `record_reference` directly and
                         # took the `nil` default, which downstream reads
                         # as "not a local" -- so one occurrence of a
                         # local answered `Text` and the next `Read`.
                         write: false)
        # `super` is deliberately not called, and deliberately not
        # *guarded against* either: measured, descending adds no second
        # candidate for the same name, because the read inside an
        # `ImplicitNode` is not visited as an ordinary read. A comment
        # claiming it would double-record was carried here from the
        # cluster that wrote the first version of this method, and it is
        # a claim no example could fail on -- which this project treats
        # as a defect of its own. Stated as what it is: nothing depends
        # on the omission.
      end

      # An ivar carries the same `write` flag a local does, and for the
      # same two readers: inlay hints label assignments, and
      # documentHighlight answers `Read`/`Write`. Without it both
      # answered `Text` -- the flag's `nil` default, which downstream
      # reads as "not known to be either".
      def visit_instance_variable_read_node(node)
        record_reference(:ivar, node.name.to_s, node.location, write: false)
        super
      end

      def visit_instance_variable_write_node(node)
        record_reference(:ivar, node.name.to_s, node.name_loc, write: true)
        super
      end

      # The operator forms and the multiple-assignment target were not
      # recorded *at all* until 0.3.0's review -- not as reads, not as
      # writes -- because only the two nodes above had visitors. That is
      # not a missing flag: documentHighlight showed two of the four
      # occurrences of a memoised ivar, and rename rewrote the same two,
      # handing back a file that still parses and memoises into an ivar
      # nothing reads. The same six kinds a local already has.
      def visit_instance_variable_operator_write_node(node)
        record_reference(:ivar, node.name.to_s, node.name_loc, write: true)
        super
      end

      def visit_instance_variable_or_write_node(node)
        record_reference(:ivar, node.name.to_s, node.name_loc, write: true)
        super
      end

      def visit_instance_variable_and_write_node(node)
        record_reference(:ivar, node.name.to_s, node.name_loc, write: true)
        super
      end

      def visit_instance_variable_target_node(node)
        record_reference(:ivar, node.name.to_s, node.location, write: true)
        super
      end

      # Class variables take the flag for the same reason ivars do:
      # without it `@@x = 1` answered `Text` where `@x = 1` answers
      # `Write`, two spellings of one construct highlighted oppositely.
      def visit_class_variable_read_node(node)
        record_reference(:cvar, node.name.to_s, node.location, write: false)
        super
      end

      def visit_class_variable_write_node(node)
        record_reference(:cvar, node.name.to_s, node.name_loc, write: true)
        super
      end

      def visit_class_variable_operator_write_node(node)
        record_reference(:cvar, node.name.to_s, node.name_loc, write: true)
        super
      end

      def visit_class_variable_or_write_node(node)
        record_reference(:cvar, node.name.to_s, node.name_loc, write: true)
        super
      end

      def visit_class_variable_and_write_node(node)
        record_reference(:cvar, node.name.to_s, node.name_loc, write: true)
        super
      end

      def visit_class_variable_target_node(node)
        record_reference(:cvar, node.name.to_s, node.location, write: true)
        super
      end

      # `alias new old` (the keyword form, not a method call) —
      # `alias_method :new, :old` is handled in #visit_call_node instead.
      # `alias $new $old` (global variable aliasing) uses
      # GlobalVariableNode for both instead of a bareword/SymbolNode; not
      # a method alias, so it's simply skipped rather than misrecorded.
      def visit_alias_method_node(node)
        new_name = symbol_name(node.new_name)
        old_name = symbol_name(node.old_name)

        if new_name && old_name
          @alias_facts << Index::AliasFact.new(
            owner: current_owner,
            new_name: new_name,
            old_name: old_name,
            singleton: @cref.declares_singleton?,
            location: Index::SourceLocation.to_range(node.location, @lines)
          )
        end

        super
      end

      def visit_constant_write_node(node)
        # `024.82`. `Foo = Class.new(Bar)` creates a class as surely as
        # `class Foo < Bar` does -- Ruby even gives it the name:
        #
        #     $ ruby -e 'class B; end; A = Class.new(B); p [A.class, A.superclass, A.name]'
        #     [Class, B, "A"]
        #
        # Recorded as a `:constant`, nothing that looks for a class saw
        # it, so the undefined-method check declined on every receiver
        # typed as one. Measured against the keyword form as a control:
        # `Keyworded.new.definitely_absent` was reported and
        # `Assigned.new.definitely_absent` was not. Common in real code --
        # `concurrent/errors.rb` is written this way throughout.
        kind = class_creating_call?(node.value) ? :class : :constant
        # A class's name is its **qualified** name, the way
        # `#visit_class_node` records one -- `::M::L::HeredocData`, not
        # `::HeredocData`. Written unqualified first, and a top-level
        # fixture could not tell: with no enclosing namespace the two are
        # the same string. The corpus could, and did.
        name = kind == :class ? assigned_class_name(node) : node.name.to_s
        @declarations << Index::Declaration.new(
          symbol_id: Index::SymbolId.new(kind: kind, owner: current_owner, name: name, discriminator: nil),
          location: Index::SourceLocation.to_range(node.location, @lines),
          visibility: nil,
          parameters: [],
          origin: :source,
          # **What the constant was assigned**, which nothing recorded
          # until 0.2.18. Every constant read as a class object named
          # after itself -- `MAX_RETRIES = 3` hovered
          # `ClassOf[MAX_RETRIES]` -- because the only thing downstream
          # had was the name (`024.84`). A method declaration has carried
          # its `body_source` since 0.1.x for the same kind of reason;
          # this is the same field, filled for the same purpose.
          #
          # The source text rather than an inferred type: inference needs
          # the workspace, and this runs while the file is being parsed,
          # with no workspace to ask.
          body_source: kind == :constant ? node.value&.slice : nil,
          name_location: Index::SourceLocation.to_range(node.name_loc, @lines)
        )
        if kind == :class
          record_assigned_superclass(node)
          record_assigned_class_open_surface(node)
          record_assigned_struct_members(node)
        end

        super
      end

      private

      # A namespace whose constant path is not statically resolvable is
      # skipped -- the node itself and its whole subtree -- rather than
      # guessed at or allowed to raise (round 29).
      #
      # `Prism::ConstantPathNode#full_name` does not merely return something
      # unhelpful for a path with a non-constant segment: it *raises*
      # `DynamicPartsInConstantPathError`. Read bare, that propagated out of
      # #summarize, and the failure was never one namespace's name -- it was
      # the loss of the *whole file*: no FileSummary at all, every
      # declaration in it gone from the index, hover/definition/completion/
      # diagnostics dark for it. Exactly the collateral round 28 found one
      # method below, in #extract_parameters, reached through the same
      # "assume the Prism node answers" habit.
      #
      # Two reachable shapes, measured end to end through ParserService:
      # `class self::Beta` -- legal, ordinary Ruby -- and any *mistyped*
      # path (`class foo::Beta`), which matters because Prism is
      # deliberately error-tolerant here: this class's whole premise is that
      # "even when the source has a syntax error, declarations before the
      # error remain visible" (Task 002 acceptance criterion), and a file
      # being typed in the editor is reparsed on every keystroke. So a
      # transient lowercase segment took the file's entire index down
      # mid-edit.
      #
      # #raw_constant_name is the guard this file already uses for exactly
      # this question everywhere else (#record_superclass,
      # #record_ancestor_call, #record_method_call_candidate,
      # #constant_full_name) -- "動的な名前は推測せず対象外", never guess at
      # dynamic input. This path was the one caller that asked Prism
      # directly instead.
      #
      # The four stack pushes moved into #within_namespace so the `ensure`
      # that pops them can only ever run when they actually ran. Guarding
      # with a bare early `return` above an `ensure` in this same method
      # would have popped four stacks that were never pushed -- emptying
      # @visibility_stack and unbalancing @owner_stack, so every *later*
      # declaration in the file gets the wrong owner. Pairing them
      # structurally makes that class of bug unwritable here rather than
      # merely absent today.
      def visit_namespace(node, kind:)
        local_path = raw_constant_name(node.constant_path)
        return unless local_path

        absolute_name = qualify(local_path)

        @declarations << Index::Declaration.new(
          symbol_id: Index::SymbolId.new(kind: kind, owner: current_owner, name: absolute_name, discriminator: nil),
          location: Index::SourceLocation.to_range(node.location, @lines),
          visibility: nil,
          parameters: [],
          origin: :source,
          name_location: Index::SourceLocation.to_range(namespace_name_location(node.constant_path), @lines)
        )

        record_superclass(node, absolute_name) if node.is_a?(Prism::ClassNode)

        within_namespace(absolute_name, node, module_owner: kind == :module) do
          node.each_child_node { |child| child.accept(self) }
        end
      end

      # `scope_node` is the node whose `#locals` the frame carries, which
      # is not always the node naming the namespace: `class_methods do …
      # end` opens a module body written as a block, and the block is what
      # binds.
      def within_namespace(absolute_name, scope_node, module_owner: false)
        previous_cref = @cref
        @cref = @cref.in_namespace(absolute_name, module_owner: module_owner)
        in_scope(scope_node) { yield }
      ensure
        @cref = previous_cref
      end

      # For `class Foo::Bar`, `node.constant_path` is a Prism::ConstantPathNode
      # whose own #location spans the whole "Foo::Bar" -- using that
      # directly as the narrow, in-place-editable name_location (the
      # previous behavior) meant Rename::Planner's edit for renaming just
      # `Bar` replaced "Foo::Bar" wholesale, silently dropping the class
      # out of its namespace. ConstantPathNode#name_loc is the last
      # segment alone ("Bar"); a bare `class Foo` has a ConstantReadNode
      # instead, which has no #name_loc because its own #location is
      # already exactly that narrow (there's only one segment). Found by
      # the Task 014-018 independent review.
      def namespace_name_location(constant_path_node)
        constant_path_node.respond_to?(:name_loc) ? constant_path_node.name_loc : constant_path_node.location
      end

      # The owner `def Const.name` names, resolved the way Ruby resolves a
      # constant: through the nesting, innermost first, before falling
      # back to qualifying under the current owner.
      #
      # `#qualify` alone gave `::Fetcher::Fetcher` for `def Fetcher.start`
      # written inside `class Fetcher` -- a class that does not exist, and
      # one every later lookup then failed against. Ruby finds the
      # enclosing `Fetcher`, because `Fetcher::Fetcher` is not declared.
      #
      # Only the frames *this parser has seen declared* are matched, which
      # is the honest limit of doing it here: a nesting frame is a name
      # this file wrote, and a constant declared elsewhere still falls
      # back. `024.32`.
      def receiver_owner_name(receiver)
        written = raw_constant_name(receiver)
        return constant_full_name(receiver) if written.nil? || written.start_with?("::")

        head = written.split("::").first
        frame = @cref.nesting.find { |f| Index::SymbolId.bare_name(f).split("::").last == head }
        return Index::SymbolId.qualify_owner(frame) if frame && written == head

        constant_full_name(receiver)
      end

      def qualify(local_path)
        Index::SymbolId.qualify_within(current_owner, local_path)
      end

      # Deliberately NOT qualified via #qualify — a superclass/included
      # module is resolved through Ruby's normal (lexical-scope) constant
      # lookup, not automatically nested under whatever class references
      # it. Recorded as written in source; Semantic::HierarchyIndex
      # resolves it against the workspace's declared types when
      # aggregating ancestor chains.
      # A superclass that is not a plain constant path -- `class Foo <
      # ActiveRecord::Migration[8.1]`, `class Bar < base_class_for(x)` --
      # still has to be recorded, with a nil target meaning "this class
      # inherits from something we cannot name".
      #
      # Dropping it silently was worse than recording nothing: the class
      # then looked like a plain `class Foo` with no parent, so the
      # hierarchy gave it Object/Kernel/BasicObject and the unknown-method
      # check treated it as fully known. Every Rails migration was in that
      # state, and every call in one -- `create_table`, `add_column` --
      # was reported as undefined.
      # `Class.new`, `Struct.new`, `Data.define` and `Module.new` -- the
      # same four `CLASS_CREATING_BLOCK_RECEIVERS` already names for the
      # block form, read here for the assignment form so the two cannot
      # disagree about what creates a class.
      def class_creating_call?(value)
        return false unless value.is_a?(Prism::CallNode)

        name = value.receiver && raw_constant_name(value.receiver)
        return false unless name

        CLASS_CREATING_BLOCK_RECEIVERS[Index::SymbolId.bare_name(name.to_s)] == value.name
      end

      # **Some of these forms generate members this parser never sees.**
      # Asked of Ruby rather than assumed:
      #
      #     Class.new(B).instance_methods(false)          # => []
      #     Module.new.instance_methods(false)            # => []
      #     Struct.new(:a, :b).instance_methods(false)    # => [:a, :a=, :b, :b=]
      #     Data.define(:x).instance_methods(false)       # => [:x]
      #     Class.new(B) { def own_m; end }               # => [:own_m]
      #
      # So `Struct.new` and `Data.define` open the surface, and so does
      # **any** of them given a block — the block's body is read by
      # `024.31`'s machinery, not attributed here, so from this node's
      # point of view its members are unknown.
      #
      # `Class.new(Base)` with no block generates nothing, and stays
      # enumerable. That is the half worth keeping: the undefined-method
      # check goes on working on a plain aliasing assignment.
      #
      # **Measured, and this is why the distinction exists.** Over 269
      # files of real gem source, naming these classes removed six
      # `unresolved-constant` reports — and, before the surface opened,
      # added one wrong `unknown-method`:
      # ``HeredocData has no method named `common_whitespace=` ``, on a
      # `Struct.new` accessor that plainly exists. `024.110`'s rule
      # applied one level out: an enumeration carries its own
      # completeness, and a generated one cannot.
      GENERATES_MEMBERS = { "Struct" => :new, "Data" => :define }.freeze

      def generates_unreadable_members?(value)
        return true unless value.block.nil?

        name = value.receiver && raw_constant_name(value.receiver)
        GENERATES_MEMBERS[Index::SymbolId.bare_name(name.to_s)] == value.name
      end

      def record_assigned_class_open_surface(node)
        return unless generates_unreadable_members?(node.value)

        owner = Index::SymbolId.bare_name(assigned_class_name(node))
        @open_surface_owners << [owner, :instance]
        @open_surface_owners << [owner, :singleton]
      end

      # **A `Struct` or `Data` constant names its members in the call**, and
      # they were recorded nowhere -- so `Seed.new.` offered 51 items and
      # not `seed`, and hover and definition had nothing either. Asked of
      # Ruby, including the arguments that are not members:
      #
      #     Struct.new(:a, :b).instance_methods(false)          # => [:a, :a=, :b, :b=]
      #     Struct.new(:a, keyword_init: true)…(false)          # => [:a, :a=]
      #     Struct.new("Named", :c).instance_methods(false)     # => [:c, :c=]
      #     Data.define(:x, :y).instance_methods(false)         # => [:x, :y]
      #     Data.define.instance_methods(false)                 # => []
      #
      # Symbols only, and a writer for `Struct` where `Data` has none.
      #
      # **The surface stays open**, which is the whole of why this is safe
      # to add. `024.110`'s rule is that an enumeration carries its own
      # completeness and a generated one cannot; naming the class without
      # opening it produced ``HeredocData has no method named
      # `common_whitespace=` `` over real gem source. This adds what the
      # class *has* and asserts nothing about what it lacks. `024.237`.
      def record_assigned_struct_members(node)
        value = node.value
        return unless value.is_a?(Prism::CallNode)

        receiver = value.receiver && raw_constant_name(value.receiver)
        return unless receiver

        bare = Index::SymbolId.bare_name(receiver.to_s)
        return unless GENERATES_MEMBERS[bare] == value.name

        # `SymbolNode` only. `Struct.new("Named", :c)` names the struct
        # with that String and takes `:c` as its one member, and
        # `#symbol_name` reads a String literal too -- which recorded
        # `Named` and `Named=` as members of it.
        names = Array(value.arguments&.arguments)
                .select { |argument| argument.is_a?(Prism::SymbolNode) }
                .filter_map { |argument| symbol_name(argument) }
        return if names.empty?

        saved = @cref
        @cref = @cref.with(owner: assigned_class_name(node))
        names.each do |name|
          add_generated_method(node: value, name: name, name_node: value, kind: :instance_method,
                               return_type: nil, origin: :generated, parameters: [])
          next unless bare == "Struct"

          add_generated_method(node: value, name: "#{name}=", name_node: value, kind: :instance_method,
                               return_type: nil, origin: :generated,
                               parameters: [Index::Parameter.new(name: "value", kind: :required, default_source: nil)])
        end
      ensure
        @cref = saved if saved
      end

      # `Class.new(Bar)`'s first argument is the superclass. Only a
      # statically nameable one is recorded: `Class.new(something_dynamic)`
      # names an ancestor this parser cannot vouch for, and inventing one
      # is worse than recording none -- the class is still a class, and
      # the chain is simply short.
      def assigned_class_name(node)
        Index::SymbolId.qualify_owner([current_owner, node.name.to_s].compact.join("::"))
      end

      def record_assigned_superclass(node)
        argument = node.value.arguments&.arguments&.first
        return unless argument

        target = raw_constant_name(argument)
        return unless target

        owner = assigned_class_name(node)
        @ancestor_facts << Index::AncestorFact.new(
          owner: owner, relation: :superclass, target: target,
          location: Index::SourceLocation.to_range(argument.location, @lines), nesting: current_nesting
        )
      end

      def record_superclass(node, owner)
        return unless node.superclass

        @ancestor_facts << Index::AncestorFact.new(
          owner: owner, relation: :superclass, target: raw_constant_name(node.superclass),
          location: Index::SourceLocation.to_range(node.superclass.location, @lines), nesting: current_nesting)
      end

      # `module_function` makes each method reachable on the module *as
      # well as* leaving a private instance copy -- two methods, which is
      # why this records a second declaration rather than moving the
      # first. `#visibility_for_definition` makes the instance copy
      # private. See `Index::Cref#module_function?` for the interpreter
      # session both halves come from (`024.106`).
      def record_module_function_twin(node, owner)
        instance_declaration = @declarations.last

        @declarations << instance_declaration.with(
          symbol_id: Index::SymbolId.new(kind: :singleton_method, owner: owner, name: node.name.to_s,
                                         discriminator: nil),
          visibility: :public
        )
      end

      # `module_function :mf_c` names methods already declared above it,
      # so there is nothing pending to remember -- the declarations are
      # rewritten in place and given their singleton twins. Only the names
      # written: a sibling `mf_d` stays a public instance method and off
      # the module entirely, which is the half that distinguishes this
      # form from the bare one.
      def apply_module_function_arguments(node)
        names = node.arguments.arguments.filter_map { |argument| symbol_name(argument) }
        return if names.empty?

        # Recorded as a fact as well as applied here. The names may belong
        # to a `def` in another file -- which is what this form is for --
        # and the rewrite below can only see what this file declared
        # (`024.114`). `WorkspaceIndex` applies the fact once every file
        # is in; this stays because it also carries the *visibility*
        # change, which is per-declaration.
        names.each { |name| @module_function_names << [Index::SymbolId.bare_name(current_owner), name] }

        twins = @declarations.select do |declaration|
          declaration.symbol_id.kind == :instance_method &&
            declaration.symbol_id.owner == current_owner &&
            names.include?(declaration.symbol_id.name)
        end
        rewrite_recorded_visibility(names, :private)
        twins.each do |declaration|
          @declarations << declaration.with(
            symbol_id: Index::SymbolId.new(kind: :singleton_method, owner: declaration.symbol_id.owner,
                                           name: declaration.symbol_id.name, discriminator: nil),
            visibility: :public
          )
        end
      end

      def inline_module_function?(node)
        node.name == :module_function && node.receiver.nil? && @cref.module_owner? &&
          node.arguments&.arguments&.any? { |argument| argument.is_a?(Prism::DefNode) }
      end

      # The pre-`ActiveSupport::Concern` spelling of a concern:
      #
      #   module OldStyle
      #     def self.included(base) = base.extend(ClassMethods)
      #     module ClassMethods; def old_cm; end; end
      #   end
      #
      # Recorded as its own relation rather than as an `extend`, because
      # it is not one: `OldStyle` does not extend `ClassMethods`, it
      # arranges for whoever *includes* it to. `HierarchyIndex` reads it
      # as the marker that makes `include OldStyle` reach
      # `OldStyle::ClassMethods` (`024.115`).
      #
      # 0.2.11 narrowed the concern rule on the stated ground that this
      # shape "is an ordinary `extend` this index has always followed".
      # It is not -- the receiver is a method parameter -- and that claim
      # was written from a summary rather than checked, which turned a
      # generation of real concerns into false reports for one round.
      # **A hook that does anything else to `base` opens the including
      # class's surface.** `#record_concern_hook` above reads exactly one
      # statement -- `base.extend(Const)` -- and everything else a hook
      # can do to the class it is passed was read as nothing at all, so
      # the class looked fully enumerated and its new methods were
      # reported missing. Ruby, 3.4.10, on the three measured shapes:
      #
      #   module H2; def self.included(base) = base.include(Helpers); end
      #   class W2; include H2; end
      #   W2.new.respond_to?(:from_helpers)          # => true, reported
      #
      #   module H4
      #     def self.included(base) = base.class_eval { def from_ce; end }
      #   end
      #   W4.new.respond_to?(:from_ce)               # => true, reported
      #
      # The surface opens on the *module*, not on the class: the class is
      # in another file this visitor never sees, and the module is on its
      # ancestor chain, which is where `MethodResolver#open_surface?` asks.
      #
      # **Any mention of the parameter counts, not only a call on it.**
      # `Registry.install(base)` hands the class to code this parser
      # cannot follow, and reading only receivers would call that hook
      # fully modelled. So: every read of the parameter in the body, minus
      # the ones `#record_concern_hook` accounts for, and a remainder
      # opens the surface.
      def record_unmodelled_hook_surface(node)
        return unless current_owner && @cref.module_owner?

        parameter = node.parameters&.requireds&.first&.name
        return unless parameter && node.body

        reads = hook_parameter_reads(node.body, parameter)
        return if reads.zero?

        modelled = modelled_hook_calls(node.body, parameter)
        return if reads == modelled

        @open_surface_owners << [Index::SymbolId.bare_name(current_owner), :instance]
      end

      def hook_parameter_reads(root, parameter)
        walk_nodes(root).count do |candidate|
          candidate.is_a?(Prism::LocalVariableReadNode) && candidate.name == parameter
        end
      end

      # The reads `#record_concern_hook` turns into a fact: the receiver
      # of a `base.extend(Const)`. Counted the same way they are recorded,
      # so a shape that stops being modelled there stops being counted
      # here rather than quietly staying exempt.
      def modelled_hook_calls(root, parameter)
        walk_nodes(root).count do |candidate|
          next false unless candidate.is_a?(Prism::CallNode) && candidate.name == :extend
          next false unless candidate.receiver.is_a?(Prism::LocalVariableReadNode)
          next false unless candidate.receiver.name == parameter

          target = candidate.arguments&.arguments&.first
          !!(target && raw_constant_name(target))
        end
      end

      def walk_nodes(root)
        return enum_for(:walk_nodes, root) unless block_given?

        yield root
        root.compact_child_nodes.each { |child| walk_nodes(child) { |n| yield n } }
      end

      def record_concern_hook(node)
        return unless node.name == :extend && @cref.module_owner?
        return unless node.receiver.is_a?(Prism::LocalVariableReadNode)
        return unless node.receiver.name == @included_hook_parameter

        target = node.arguments&.arguments&.first
        name = target && raw_constant_name(target)
        return unless name

        @ancestor_facts << Index::AncestorFact.new(
          owner: current_owner, relation: :concern_class_methods, target: name,
          location: Index::SourceLocation.to_range(target.location, @lines), nesting: current_nesting)
      end

      def record_ancestor_call(node)
        # `extend self` in a module body: no argument names a constant, so
        # this dropped it and `MF.` completed nothing the module declared.
        # Ruby adds no methods here -- it puts the module in its own
        # singleton chain -- so that is what is recorded, and the methods
        # stay exactly where they are written.
        return record_extend_self(node) if extend_self?(node)
        return unless node.arguments

        relation = ANCESTOR_RELATIONS.fetch(node.name)
        node.arguments.arguments.each do |arg|
          target = raw_constant_name(arg)
          # An argument with no statically-known name used to be dropped
          # here, which made "extends a module I cannot name" and
          # "extends nothing" the same fact downstream -- the chain then
          # looked complete and the module's methods were reported
          # missing. `Rack::Reloader`'s `extend backend`, a constructor
          # parameter, is the measured case.
          next record_dynamic_ancestor(relation) unless target

          @ancestor_facts << Index::AncestorFact.new(
            owner: current_owner, relation: relation, target: target,
            location: Index::SourceLocation.to_range(arg.location, @lines), nesting: current_nesting)
        end
      end

      # `@cref.module_owner?` rather than `self_is_module?`: the latter is
      # true in a class body too, and Ruby has no `extend self` there --
      # `class ESC; extend self; end` raises
      # `TypeError: wrong argument type Class (expected Module)`
      # (ruby 3.4.10). Recording an edge Ruby refuses to make puts a
      # class's instance methods on its own singleton chain, and every
      # answer about it is then wrong in the direction that invents
      # methods.
      def extend_self?(node)
        node.name == :extend && current_owner && !@cref.in_method_body? && @cref.module_owner? &&
          node.arguments&.arguments&.length == 1 &&
          node.arguments.arguments.first.is_a?(Prism::SelfNode)
      end

      def record_extend_self(node)
        @ancestor_facts << Index::AncestorFact.new(
          owner: current_owner, relation: :extend, target: current_owner,
          location: Index::SourceLocation.to_range(node.arguments.arguments.first.location, @lines), nesting: current_nesting)
      end

      # An ancestor decided at runtime leaves a surface that cannot be
      # enumerated, which is the same state an unreadable macro leaves
      # (see #open_surface_kind) and gets the same answer: the check
      # declines to assert absence rather than guessing.
      #
      # Which surface follows what the call does to `self`. In a class
      # body `self` is the class, so `extend` adds class methods and
      # `include`/`prepend` add instance ones; inside `class << self`
      # every relation is class-level; and inside an instance method
      # `extend other` is `Object#extend` on that instance, so it adds to
      # the instance surface -- which is the `Rack::Reloader` shape and
      # the reason this is not gated on `@in_method_body`.
      def record_dynamic_ancestor(relation)
        return if current_owner.nil?

        kind =
          if @cref.declares_singleton? then :singleton
          elsif relation == :extend && !@cref.in_method_body? then :singleton
          else :instance
          end
        @open_surface_owners << [Index::SymbolId.bare_name(current_owner), kind]
      end

      # `alias_method :new, :old` — the method-call form; symbol (or
      # plain string) arguments only. A non-literal argument (a variable,
      # an interpolated string) can't be resolved statically and is
      # skipped, same policy as Task 006/007's "constantize前に検証する"
      # (docs/03-semantic-engine.md 7.1) — never guess at dynamic input.
      def record_alias_method_call(node)
        return unless node.arguments

        new_arg, old_arg = node.arguments.arguments
        new_name = symbol_name(new_arg)
        old_name = symbol_name(old_arg)
        return unless new_name && old_name

        @alias_facts << Index::AliasFact.new(
          owner: current_owner, new_name: new_name, old_name: old_name,
          singleton: @cref.declares_singleton?,
          location: Index::SourceLocation.to_range(node.location, @lines)
        )
      end

      # `attr_reader :name` declares `name` as surely as `def name` does.
      # The index recorded the call and not the declaration, so on a class
      # whose ancestry is fully known -- the receiver the unknown-method
      # check acts on -- every attribute reader was reported missing.
      # Thor's `attr_accessor :options` is the instance this release had
      # to close: 024.23's fix reads a `define_method` body as an instance
      # and would otherwise have handed users that report where they had
      # none.
      #
      # Each suffix is what the DSL actually defines: a reader takes no
      # arguments, a writer takes exactly one, and the argument-count
      # check reads both.
      ATTRIBUTE_DSLS = {
        attr_reader: [["", 0]],
        attr_writer: [["=", 1]],
        attr_accessor: [["", 0], ["=", 1]]
      }.freeze

      # A class body that runs something this parser cannot read may have
      # methods no `def` and no recognised macro accounts for, so the
      # owner's surface is *open*: absence is unprovable there, and
      # Diagnostics::Engine#closed_nominal? declines rather than reporting.
      #
      # Deliberately about the enclosing owner and not the file: the cost
      # is paid by exactly the class that ran the unreadable call.
      # `@in_method_body` excludes calls that merely execute at call time
      # -- but not blocks, because `included do ... end` and
      # `class_eval { ... }` define methods on the owner and are the shape
      # this rule exists for.
      # `define_method` and `define_singleton_method` name what they do.
      # Written inside a block -- `%w[a b].each { |n| define_singleton_method(n) { … } }`,
      # which is how a class generates a family of methods -- the block
      # guard below dropped them, and every call they answer was reported
      # (`024.116`). Unlike an arbitrary macro, these two are not a guess:
      # the call defines a method whose name this parser cannot compute,
      # which is exactly what an open surface means.
      # `define_method` adds to whichever surface a bare `def` would add
      # to *here*, which is what `Cref#surface_kind` answers -- inside
      # `class << self` that is the singleton side. Hardcoding `:instance`
      # inverted both directions there, and both were right in 0.2.10.
      #
      # `define_singleton_method` is a level further out: inside
      # `class << self` Ruby puts the method on
      # `C.singleton_class.singleton_class`, which this index cannot name
      # at all -- so it opens nothing there rather than claiming the
      # class side.
      METHOD_DEFINING_CALLS = %i[define_method define_singleton_method].freeze

      def method_defining_surface(node)
        return nil unless node.receiver.nil? && current_owner && METHOD_DEFINING_CALLS.include?(node.name)
        return @cref.surface_kind if node.name == :define_method
        return nil if @cref.declares_singleton?

        :singleton
      end

      def record_open_surface(node, read_as_a_macro = false)
        if (kind = method_defining_surface(node))
          # **The name, when there is one** (`024.116`). `define_method(:x)`
          # names its method as plainly as a `def` does, and recording
          # only the open surface meant calls to `x` stopped being
          # reported while hover, go-to-definition and completion all
          # answered nothing -- silence instead of an answer, which is the
          # safe direction and not the right one.
          #
          # The surface still opens either way: a *computed* name is
          # exactly what this parser cannot read, and one such call in the
          # body makes the whole owner unenumerable however many literal
          # ones sit beside it.
          record_defined_method_name(node, kind)
          return @open_surface_owners << [Index::SymbolId.bare_name(current_owner), kind]
        end

        return unless @cref.defines_surface?
        # Written inside a block, this call says nothing about the
        # enclosing class's members -- the call that *owns* the block does,
        # and it is visited separately. `included do ... end` opens the
        # surface through `included`; `assert_equal` inside somebody's
        # `test` block does not, and neither does `helper_thing` inside
        # `DEFAULT = -> { helper_thing }`, which used to silence every
        # report about the class it was written in.
        # A setter or an operator is named in a way no method-defining
        # macro is: Ruby will not let `def default_query_parser=(v)`
        # define something else, and `singleton_class < Comparable` is a
        # comparison. A shape rather than more names, because a list can
        # only ever hold the calls somebody has already seen.
        return unless node.name.to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]*[!?]?\z/)
        return if NON_DEFINING_CLASS_BODY_CALLS.include?(node.name)
        # Ancestor relations are exempt by name because
        # `#record_dynamic_ancestor` already opens the surface for the
        # ones it cannot read.
        return if ANCESTOR_RELATIONS.key?(node.name)
        # **`read_as_a_macro`, passed in, not an ivar read back.** This was
        # `@recorded_a_declaration`, which is recomputed only in the
        # receiverless branch above and is therefore sticky across every
        # call that has a receiver:
        #
        #   class Sticky
        #     attr_reader :first                    # sets the flag
        #     self.delegate(*NAMES, to: :inner)     # receiver, so no reset
        #   end
        #
        # `delegate` is on this list, the stale flag said a declaration had
        # been recorded, and the surface stayed closed over a call whose
        # splat this parser cannot read -- so every method it defines was
        # reported missing. The call-local value is false for anything
        # with a receiver, which is the answer this exemption wants: it is
        # about a macro *this call* recorded, not about an earlier one.
        # Found by cold review, one reader over from `024.327`'s own.
        return if RECORDING_CALLS.include?(node.name) && read_as_a_macro

        kind = open_surface_kind(node)
        return if kind.nil?

        owner = Index::SymbolId.bare_name(current_owner)
        @open_surface_owners << [owner, kind]

        # **And the other side, for a receiverless call.** A macro written
        # bare in a class body is itself a call on that owner's class
        # side, and one this engine could not identify -- so the same
        # evidence that says "I cannot enumerate this owner's instance
        # members" says "I cannot enumerate its class members either",
        # because whatever supplies the macro is exactly the thing that
        # could not be read. Without it the engine gave two contradictory
        # answers about one fact: it declined to report anything the macro
        # *might* define and reported the macro itself (`024.110`).
        #
        # **0.2.11 shipped this line and rolled it back the same
        # release**, because `#open_surface?` then read it through the
        # `Class`/`Module`/`Object` tail of every chain: one bare
        # `alias_method` in a `core_ext` file switched off `Foo.bar`
        # checking for the whole workspace, 117 constant-receiver findings
        # to 0 over 16 gems. That reader ignores a synthesised link now,
        # so this says something about *this owner* and nothing about
        # anyone who merely inherits from `Module`.
        #
        # Only receiverless: `Other.class_eval { }` says nothing about
        # this owner's class side, and `singleton_class.send` is already
        # about the class side alone.
        @open_surface_owners << [owner, :singleton] if node.receiver.nil? && kind == :instance
      end

      # Which surface the call could have added to, or nil for a call that
      # is not metaprogramming this owner at all.
      #
      # Receiverless is the ordinary case, and it opens *one* surface, not
      # both: `attr_atomic :value` in a class body defines `#value`, never
      # `.attr_atomic`. Opening the singleton surface too would make every
      # unreadable class-body call silence its own report, and reporting
      # that call is deliberate behaviour (024.23) which 19 examples pin.
      # Inside `class << self` the same call defines singleton methods, so
      # it opens that surface instead.
      #
      # Two receivers count as well, because they are the owner:
      # `singleton_class.send :alias_method, :[], :new` --
      # concurrent-ruby's `LockFreeStack::Node`, 6 findings over the gem
      # corpus -- and `self.class_eval { ... }`. Every other receiver is
      # some other object, and widening to those would open a surface for
      # `LOGGER.warn`.
      def open_surface_kind(node)
        case node.receiver
        when nil, Prism::SelfNode then @cref.surface_kind
        when Prism::CallNode
          :singleton if node.receiver.receiver.nil? && node.receiver.name == :singleton_class
        end
      end

      def record_defined_method_name(node, kind)
        name_node = node.arguments&.arguments&.first
        name = attribute_name(name_node)
        return unless name

        # `node:`, not `name_node:`, is the region: the block this call
        # carries *is* the method's body, so the whole call is what this
        # one declaration owns. See `#add_generated_method`.
        add_generated_method(
          node: node, name_node: name_node, name: name,
          kind: kind == :singleton ? :singleton_method : :instance_method,
          return_type: Types::UNKNOWN, origin: node.name, visibility: nil,
          parameters: defined_method_parameters(node)
        )
      end

      # What `define_method(:x) { |a, b| }` takes is what its block takes,
      # and Ruby enforces it the way it enforces a `def` -- the block
      # becomes a method, so its arity is strict rather than a proc's:
      #
      #   $ ruby -e '
      #   class C
      #     define_method(:two)   { |a, b| }
      #     define_method(:splat) { |*objs| objs }
      #   end
      #   begin; C.new.two(1); rescue ArgumentError => e; puts e.message; end
      #   p C.new.splat(1, 2, 3)
      #   '
      #   wrong number of arguments (given 1, expected 2)
      #   [1, 2, 3]
      #   # ruby 3.4.10
      #
      # Recorded as taking *nothing*, which is what `024.116` left here,
      # every call to one was judged against zero parameters. `024.40`:
      # **109 of the 109** `argument-count` findings over Ruby 3.4.10's
      # standard library, five Rails 8.1.3.1 gems and minitest -- 2,095
      # files -- were this one line, and two declarations produced all of
      # them. `rubygems/core_ext/kernel_warn.rb`'s
      # `module_function define_method(:warn) {|*messages, **kw| ... }` and
      # `objspace/trace.rb`'s `define_method(:p) do |*objs|` between them
      # made every `warn` (94) and every `p` (15) in the corpus a report.
      #
      # Where there is no block *literal* -- `define_method(:x, &blk)`,
      # `define_method(:x, instance_method(:y))` -- the parameter list is
      # not written here at all, and neither are numbered parameters
      # (`{ _1 }`), which nothing else in this parser reads.
      # UNSTATED_PARAMETERS is what says so.
      def defined_method_parameters(node)
        block = node.block
        return UNSTATED_PARAMETERS unless block.is_a?(Prism::BlockNode)

        case block.parameters
        when nil then []
        when Prism::BlockParametersNode then extract_parameters(block.parameters.parameters)
        else UNSTATED_PARAMETERS
        end
      end

      def record_attribute_methods(node)
        return unless node.arguments
        # No guard, deliberately: `attr_*` is attributed exactly as `def`
        # is, to the lexically enclosing owner, wherever it is written.
        #
        # Three narrower rules were tried and each was wrong, because each
        # disowned `attr_*` somewhere `def` is still owned, and a block
        # holds both. Skipping every block turned every
        # ActiveSupport::Concern's `included do attr_accessor :x end` into
        # a false report; skipping only anonymous-class builders left
        # ActiveRecord's `Class.new(Base) { class << self; attr_accessor
        # :left_model; end; def self.compute_type; left_model; end }`
        # reporting; skipping method bodies leaves the same shape
        # reporting when the builder is written inside a `def`.
        #
        # What is left is the cost `def` already carries: a declaration
        # recorded from somewhere it may not run, which silences a report
        # rather than inventing one. That is the direction this engine
        # chooses everywhere else. 024.31 records the shared defect.

        # **`#surface_for`, not `#declares_singleton?`.** They differ in
        # exactly one place and it is this one: inside a `def` written in
        # `class << self`, the cref is still the singleton class, but
        # self *at run time* is the class object -- so `attr_accessor`
        # there is `Module#attr_accessor` and defines an instance
        # accessor. `S.attr_x` was reported on code that runs (`024.34`).
        owner_for_attrs, side = @cref.surface_for
        return if owner_for_attrs.nil?

        singleton = side == :singleton
        # `private attr_reader :x` is one call taking another as its
        # argument (Ruby 3.0+). The open section still applies when it is
        # written on its own line.
        visibility = @inline_attribute_visibility || @cref.visibility
        node.arguments.arguments.each do |argument|
          name = attribute_name(argument)
          # A dynamic argument (`attr_reader(*names)`) names nothing
          # statically. Guessing here would declare a method that may not
          # exist and silence a real report.
          next unless name

          ATTRIBUTE_DSLS.fetch(node.name).each do |suffix, arity|
            # Through `add_generated_method`, so the declaration is paired
            # with a fact -- three documents state that a `:generated`
            # declaration always is, and 0.1.14 recorded these without one.
            # `node: argument`, not `node: node`. One `attr_accessor :a, :b`
            # declares four methods, and the region each of them owns is
            # its own token -- the rest of the call is the other name.
            # See `#add_generated_method`.
            add_generated_method(
              node: argument, name_node: argument, name: "#{name}#{suffix}",
              kind: singleton ? :singleton_method : :instance_method,
              # Honest rather than absent: an attribute's type is whatever
              # was last assigned to the ivar, which this does not track.
              return_type: Types::UNKNOWN, origin: node.name,
              visibility: singleton ? nil : visibility,
              parameters: arity.zero? ? [] : [Index::Parameter.new(name: "value", kind: :required, default_source: nil)]
            )
          end
        end
      end

      def attribute_name(argument)
        case argument
        when Prism::SymbolNode then argument.value
        when Prism::StringNode then argument.unescaped
        end
      end

      # `private attr_reader :x` and friends: the argument is a call, not a
      # name, so `apply_visibility_arguments` -- which reads symbols,
      # strings and `def`s -- cannot see what it declares.
      def inline_attribute_visibility_for(node)
        visibility = VISIBILITY_MODIFIERS[node.name]
        return nil unless visibility && node.arguments

        wrapped = node.arguments.arguments.first
        return nil unless wrapped.is_a?(Prism::CallNode) && ATTRIBUTE_DSLS.key?(wrapped.name)

        visibility
      end

      def record_generated_methods(node)
        case node.name
        when :enum then record_enum(node)
        when :scope then record_scope(node)
        when :delegate then record_delegate(node)
        end
      end

      # `enum status: { active: 0, archived: 1 }` (keyword form) or
      # `enum :status, { active: 0 }` / `enum :status, %i[active archived]`
      # (positional forms). Generates only the `#{value}?` predicate
      # methods -- "enum" DSL requirements list `predicate/bang/scopes`
      # in full, but predicates are the highest-value, most-used subset,
      # and this task's own priority list explicitly puts `enum` above
      # everything else it covers; bang methods and per-value scopes are
      # deferred.
      def record_enum(node)
        return unless node.arguments

        enum_values(node).each do |value_name, value_node|
          # `node: value_node`: one `enum` call declares one predicate per
          # value, and the region each owns is its own key. See
          # `#add_generated_method`.
          add_generated_method(
            node: value_node, name_node: value_node, name: "#{value_name}?", kind: :instance_method,
            return_type: Types::Nominal.new(name: "Boolean"), origin: :enum, metadata: { value: value_name },
            # Stated rather than defaulted: an enum predicate really does
            # take no arguments, and `order.active?(1)` really is an error.
            parameters: []
          )
        end
      end

      # `[name, the Prism node that spells it]` per value -- the node is
      # what gives each predicate a range of its own (`024.27`); the name
      # alone left all of them at the whole call's.
      def enum_values(node)
        first = node.arguments.arguments.first
        values_node =
          if first.is_a?(Prism::KeywordHashNode)
            first.elements.first&.value
          else
            node.arguments.arguments[1]
          end

        case values_node
        when Prism::HashNode then values_node.elements.filter_map { |e| named_node(e.key) }
        when Prism::ArrayNode then values_node.elements.filter_map { |e| named_node(e) }
        else []
        end
      end

      # **`if name` is the drop, and it is load-bearing.** This replaced
      # two `filter_map { symbol_name(...) }` call sites where the drop
      # was `filter_map`'s and invisible; carrying the pair makes it this
      # method's job to keep. An argument that is not a literal spells no
      # name -- `delegate(*names, to: :company)`, `enum :status,
      # [SOME_CONST]` -- and without the guard the recorder builds a
      # declaration from the half of the name that *is* written: none at
      # all for the splat, and the bare `?` suffix for the enum
      # constant. That is the guess `#record_attribute_methods` refuses
      # for the same reason: it declares a method that may not exist and
      # silences a real report.
      def named_node(node)
        name = symbol_name(node)
        [name, node] if name
      end

      # `scope :active, -> { where(active: true) }` -- the scope body
      # itself is never analyzed ("dynamic body内部型の断定はしない"); only
      # its name and the fact that it returns `Relation[Model]` are
      # statically knowable.
      # **The parameter list this parser does not state.** An empty list is
      # not the absence of an answer, it is the answer "takes nothing", and
      # every reader treats it as one -- the argument-count check most
      # sharply. A rest parameter is the shape that declines instead: the
      # same answer `def m(...)` gets, and the one the check bails out on.
      #
      # Three macros want it, for two reasons. `delegate` passes everything
      # through and a `scope`'s arguments are its lambda's, so the list is
      # not knowable here; `define_method(:x, &blk)` does not write one
      # here at all. Each of the three recorded *nothing* at some point and
      # each made the check judge every call to what it declared -- twice
      # over now (`024.40`), which is why the name says what the value
      # means rather than which macro asked for it.
      UNSTATED_PARAMETERS = [Index::Parameter.new(name: "args", kind: :rest, default_source: nil)].freeze

      def record_scope(node)
        return unless node.arguments

        name_node = node.arguments.arguments.first
        name = symbol_name(name_node)
        return unless name

        return_type = Types::Generic.new(name: "Relation", type_arg: Types::Nominal.new(name: qualified_owner_name))
        # `node:`, not `name_node:`, is the region: the lambda this call
        # carries is the scope's body, and one call declares one scope.
        # See `#add_generated_method`.
        add_generated_method(node: node, name_node: name_node, name: name, kind: :singleton_method,
                             return_type: return_type, origin: :scope, parameters: UNSTATED_PARAMETERS)
      end

      # `delegate :name, :age, to: :company, prefix: true, allow_nil: true`.
      # The generated method's own return type isn't resolved here (that
      # needs the *target*'s association/column facts, which aren't known
      # until Model registry data is available) -- `Types::UNKNOWN` plus
      # `to:`/delegated-name metadata lets LocalInferencer/MethodAnalyzer
      # resolve it later, the same deferred-resolution split Task 013's
      # RBS/Signature layer already uses.
      def record_delegate(node)
        return unless node.arguments

        keyword_hash = node.arguments.arguments.find { |a| a.is_a?(Prism::KeywordHashNode) }
        return unless keyword_hash

        target = delegate_option(keyword_hash, "to")
        return unless target

        prefix = truthy_option?(keyword_hash, "prefix")
        allow_nil = truthy_option?(keyword_hash, "allow_nil")
        method_names = node.arguments.arguments.take_while { |a| !a.is_a?(Prism::KeywordHashNode) }
                            .filter_map { |a| named_node(a) }

        method_names.each do |delegated_name, name_node|
          generated_name = prefix ? "#{target}_#{delegated_name}" : delegated_name
          # `node: name_node`: one `delegate` call declares one method per
          # name, and the region each owns is its own token -- the rest of
          # the call is the other names and the options. See
          # `#add_generated_method`.
          add_generated_method(
            node: name_node, name_node: name_node, name: generated_name, kind: :instance_method,
            return_type: Types::UNKNOWN, origin: :delegate,
            parameters: UNSTATED_PARAMETERS,
            metadata: { to: target, delegated_name: delegated_name, allow_nil: allow_nil }
          )
        end
      end

      def delegate_option(keyword_hash, key)
        assoc = keyword_hash.elements.find { |e| symbol_name(e.key) == key }
        assoc && symbol_name(assoc.value)
      end

      def truthy_option?(keyword_hash, key)
        assoc = keyword_hash.elements.find { |e| symbol_name(e.key) == key }
        assoc&.value.is_a?(Prism::TrueNode)
      end

      # **`parameters:` has no default.** It defaulted to `[]`, and three of
      # the five recorders that call this took the default while meaning
      # "not stated here" -- each time declaring that the method takes no
      # arguments, and each time making the argument-count check report
      # every call to it (`delegate` and `scope` in 0.1.15,
      # `define_method` in 0.2.13). The question is not one a recorder can
      # answer by omission, so it cannot be omitted: state the list, or
      # state UNSTATED_PARAMETERS.
      #
      # **`name_node:` has no default either, and for the same reason.**
      # It is the Prism node that spells this method's name -- the
      # `:title` of `attr_reader :title, :body`, the `active` of an
      # `enum` hash -- and every recorder has one in hand. Defaulting it
      # to `node` would let a recorder omit it and silently get nil, which
      # is exactly how `parameters:` went wrong three times.
      #
      # **`node:` is the region this one declaration owns**, and the two
      # arguments differ for a reason. A macro that takes a *list* of
      # names owns, per name, its own token: the rest of
      # `attr_accessor :a, :b` is the other name, so passing the whole
      # call gave four declarations one identical range, and everything
      # that picks the smallest range containing the caret then answered
      # about whichever one sorted first (`024.27`). A macro whose call
      # declares exactly one method -- `scope`, `define_method` -- owns
      # the whole call, because the rest of it is that method's body.
      def add_generated_method(node:, name:, name_node:, kind:, return_type:, origin:, parameters:, metadata: {},
                               visibility: :public)
        symbol_id = Index::SymbolId.new(kind: kind, owner: current_owner, name: name, discriminator: nil)
        location = Index::SourceLocation.to_range(node.location, @lines)
        name_token = name_token_location(node.location, name_node)

        @declarations << Index::Declaration.new(
          symbol_id: symbol_id, location: location, visibility: visibility, parameters: parameters,
          origin: :generated,
          # `name_token &&`: reachable, not defensive. A heredoc argument
          # has a name span that lies outside the region above, so
          # `#name_token_location` refuses it and this declaration falls
          # back to `location` in both fields.
          #
          # **That is not the answer the outline gave before `024.27`**,
          # and a review round corrected this comment for saying it was:
          # `node:` for `attr_*` is the argument now rather than the whole
          # call, so this shape's row moved as well -- driven through a
          # real server, `range` went from the whole `attr_reader <<~NAME`
          # call to the `<<~NAME` marker alone. What is pre-`024.27`-shaped
          # is the *equality* of the two fields, not the value of either,
          # and the equality is what the protocol's containment rule
          # allows.
          name_location: name_token && Index::SourceLocation.to_range(name_token, @lines)
        )
        @generated_method_facts << Index::GeneratedMethodFact.new(
          owner: current_owner, name: name, kind: kind, return_type: return_type, source_location: location,
          origin: origin, confidence: :high, metadata: metadata
        )
      end

      # `Index::SymbolId.bare_name`, not the last segment. Truncating gave
      # a *workspace-generated* type the naming convention RBS/RBI uses,
      # so `scope :recent` on `Billing::Order` produced `Relation[Order]`
      # -- and wherever another namespace holds an `Order`, every answer
      # about that relation belonged to the wrong class: completion listed
      # the other model's methods and go-to-definition returned nothing.
      #
      # Measured before changing it, over the installed gem corpus (3,301
      # files): **476 of 3,508 class basenames are shared by more than one
      # namespace** -- 13.6%. The collision is ordinary, not exotic.
      #
      # A companion figure first recorded here, "63 of 66 `scope`
      # declarations are namespaced", was wrong and is removed: it counted
      # every receiverless call named `scope`, most of them the routing
      # DSL. Real `scope :sym` declarations in that corpus number 2.
      #
      # `bare_name` strips a leading `::` and keeps the path, which is what
      # every other workspace-produced Nominal in this file already does.
      def qualified_owner_name
        Index::SymbolId.bare_name(current_owner)
      end

      # A dynamic superclass/module expression (`Class.new`, a local
      # variable, `send(...)`) has no statically-known name — returns nil
      # rather than guessing, matching this task's explicit "動的な
      # include(send(...))は対象外" scope boundary.
      def raw_constant_name(node)
        return nil unless node.respond_to?(:full_name)

        node.full_name
      rescue StandardError
        nil
      end

      def symbol_name(node)
        case node
        when Prism::SymbolNode, Prism::StringNode
          node.unescaped
        end
      end

      # The bare name inside a literal, without the punctuation that makes
      # it one -- `title` inside `:title`, inside `"title"` and inside the
      # `title:` of a hash key. Prism keeps that span separately from the
      # node's own, and the difference is the whole point: a
      # `selectionRange` of `:title` selects a colon the name does not
      # have, and any edit range that included it would write
      # `attr_reader ::title`.
      #
      #   $ ruby -rprism -e '
      #   src = %q{attr_accessor :title, "body", active: 0}
      #   Prism.parse(src).value.statements.body.first.arguments.arguments.each do |a|
      #     n = a.is_a?(Prism::KeywordHashNode) ? a.elements.first.key : a
      #     p [n.class.name.split("::").last, n.location.slice,
      #        (n.respond_to?(:value_loc) ? n.value_loc : n.content_loc).slice]
      #   end'
      #   ["SymbolNode", ":title", "title"]
      #   ["StringNode", "\"body\"", "body"]
      #   ["SymbolNode", "active:", "active"]
      #   # prism 1.9.0, ruby 3.4.10
      #
      # **`region` is not decoration: the name span is refused unless it
      # lies inside it.** `docs/CLIENT_BEHAVIOUR.md` records, checked
      # against the installed types, that `selectionRange` must be
      # contained by `range` -- and once `024.27` narrowed `range` to a
      # name token, that stopped being automatic, because the span Prism
      # keeps for a literal's name is not always inside the node that
      # literal occupies. A heredoc is the shape where it is not; the
      # node is the `<<~` marker and the text is on later lines:
      #
      #   $ ruby -rprism -e '
      #   src = "attr_reader <<~NAME\n  quoted\nNAME\n"
      #   a = Prism.parse(src).value.statements.body.first.arguments.arguments.first
      #   p [a.location.start_offset, a.location.end_offset, a.location.slice]
      #   p [a.content_loc.start_offset, a.content_loc.end_offset]'
      #   [12, 19, "<<~NAME"]
      #   [20, 29]
      #   # prism 1.9.0, ruby 3.4.10
      #
      # Enforced here, where the span is produced, rather than at the one
      # caller: a second caller would otherwise have to remember, and the
      # invariant is a property of the value, not of the call site.
      #
      # nil, then, for a name span outside its region -- and for a node
      # class this does not read. That second arm is not reachable from
      # the five recorders, each of which returns early unless
      # `attribute_name`/`symbol_name` recognised the argument, and those
      # two admit exactly the classes below; it declines rather than
      # raising so that a sixth recorder handing over some other literal
      # loses a `selectionRange` instead of raising out of `#summarize`,
      # which would drop the whole file's index. It is recorded as
      # unpinned in `024.27`.
      #
      # Every reader of `name_location` already treats nil as "no narrow
      # range recorded" and falls back to the declaration's own --
      # `DocumentSymbolBuilder` because the protocol field is not
      # optional, `Rename::Planner` by declining to edit -- so declining
      # here asserts nothing about the user's code.
      def name_token_location(region, node)
        span =
          case node
          when Prism::SymbolNode then node.value_loc
          when Prism::StringNode then node.content_loc
          end
        return nil unless span
        return nil unless span.start_offset >= region.start_offset && span.end_offset <= region.end_offset

        span
      end

      # The one value every recorder is handed, rather than the six stacks
      # they each used to reassemble from. See `Index::Cref`.
      attr_reader :cref

      # `Module.nesting` at the point being visited, innermost first --
      # what `AncestorFact` needs to identify a bare constant the way
      # Ruby does (`024.81`).
      def current_nesting = @cref.nesting

      def current_owner
        @cref.owner
      end

      # Real Ruby `Module.nesting`, innermost first. `@owner_stack` gets
      # exactly one push per lexical class/module *opening* (#visit_namespace
      # is called once per ClassNode/ModuleNode, regardless of whether it
      # was written in nested form, `module Foo; class Bar`, two pushes,
      # or compact form, `class Foo::Bar`, one push with the whole
      # compound name) -- which happens to already match real Ruby's own
      # nesting-depth-follows-textual-nesting rule exactly, so no extra
      # bookkeeping is needed beyond capturing this stack, reversed, at
      # the moment a reference is recorded.
      def current_lexical_nesting
        @cref.nesting
      end

      def next_scope_id
        @scope_counter += 1
      end

      # Every local-variable reference goes through here, so the two
      # questions below are asked once rather than at each of the six
      # visits. Two further declines are *not* here, because neither can
      # be answered from a name and a range: #visit_implicit_node knows
      # the node above, and #visit_local_variable_target_node knows the
      # spelling Ruby lets a pattern repeat.
      #
      # **Is this location really the name?** Prism hands back the whole
      # enclosing literal when it cannot locate a name inside it -- a
      # regexp named capture in a pattern containing an escape is the
      # shape:
      #
      #   $ ruby -e '
      #   require "prism"
      #   ["/(?<n>x)/o =~ s", "/(?<n>\\d)/ =~ s"].each { |src|
      #     Prism.parse(src).value.breadth_first_search { |node|
      #       p node.location.slice if node.is_a?(Prism::LocalVariableTargetNode)
      #       false
      #     }
      #   }
      #   '
      #   # => "n"
      #   # => "/(?<n>\\d)/"
      #   # ruby 3.4.10
      #
      # A rename edit replaces whatever range it is handed, so recording
      # the second would swap the pattern for the new name. Section 0
      # ranks that below saying nothing, and `semantic_tokens.rb` declines
      # the same shape for the same reason.
      #
      # **That comparison is necessary and it is not sufficient**, which
      # is worth stating here because for one round it was written as
      # though it were the whole answer. A value-omitted shorthand's
      # range is the *key's*, and in a pattern the key is spelled without
      # its colon -- so the slice equals the name, the comparison passes,
      # and the edit rewrites a hash pattern's key. Those three spellings
      # are declined one node up instead, where Prism marks them; see
      # #visit_implicit_node. What is left for the comparison is the
      # shape above, where there is no node to ask and the text is all
      # there is.
      #
      # Neither decline is a complete answer. The edit that would be
      # right for a shorthand *inserts* (`helper(limit: renamed)`) where
      # `Rename::Planner` replaces, and one `newText` is built from the
      # new name for every range it is handed, so what the user gets is a
      # rename that stops at that occurrence. It is published as a
      # limitation, and it is the better of the two answers available
      # here rather than a fixed feature.
      #
      # **And neither rule is `semantic_tokens.rb`'s `NAME_SHAPE`.** That
      # regex ends `[?!=]?:?`, so it accepts the trailing colon, and it
      # is right to: a highlighter marking `limit:` marks something a
      # reader sees, while an editor replacing that range writes source.
      # The two readers want different answers, so they get their own
      # rules rather than one both would have to bend to.
      #
      # **Which scope binds it?** See #binding_scope.
      def record_local_variable(name, location, write: false)
        return unless location.slice == name.to_s

        frame = binding_scope(name)
        # Not "some scope, then" but "no answer": a nil scope id puts
        # every unplaced occurrence of one name under one owner into a
        # single identity, and Find References and Rename would act on
        # that group. Declining leaves the name unresolvable, which is
        # what they already do for a name they cannot place.
        return unless frame

        # The binding frame's owner, not the current cref's -- see
        # `Scope`. `024.277`.
        record_reference(:local_variable, name.to_s, location, scope_id: frame.id, owner: frame.owner,
                         write: write)
      end

      # The frame that *binds* this name, not the innermost one that is
      # open. A block body is both a new binding scope for its own
      # parameters and a closure over the enclosing one, and one id per
      # lexical node cannot express both:
      #
      #   $ ruby -e '
      #   def m
      #     w = 1
      #     [1].each { w = 2 }
      #     w
      #   end
      #   p m
      #   v = 1
      #   f = ->(v) { v * 10 }
      #   p f.call(7)
      #   p v
      #   '
      #   # => 2
      #   # => 70
      #   # => 1
      #   # ruby 3.4.10
      #
      # The first says the `w` inside the block is the same variable as
      # the one outside; the last two say the `v` inside the lambda is a
      # different one. The innermost-frame rule answered both backwards
      # (`024.262`, `024.263`).
      #
      # The stack is a superset of the Ruby scopes enclosing the node
      # being visited, never a subset -- every scope node opens a frame
      # and nothing pops one early -- so a name Prism emitted a local
      # read for is bound by one of them. Where it is not, the caller
      # declines rather than guessing; see #record_local_variable for the
      # one shape that reaches that, and for what it costs to guess.
      #
      # **What the search does not fix** is a frame the visit opens where
      # Ruby has not. `#visit_namespace` walks a superclass expression
      # inside the class's own frame, and Ruby evaluates it in the scope
      # around it. The search now hands such a read the enclosing frame's
      # id when nothing in the body binds that name -- but the same
      # misplaced walk also records the *owner* as the class, and an
      # identity is `owner#scope_id`, so Find References still does not
      # group it. Only moving the walk fixes that, and moving it changes
      # which owner every constant in a superclass expression is recorded
      # under: a wider change than this one, with its own corpus to drive.
      # `parser_scope_frames_spec.rb` asserts both halves so the gap is
      # written down rather than remembered.
      def binding_scope(name)
        @scopes.reverse_each.find { |scope| scope.locals.include?(name) }
      end

      # `owner` defaults to the cref's, which is what every kind but a
      # local variable wants. A local's comes from the frame that binds
      # it, because it does not have one of its own -- `Scope`, `024.277`.
      def record_reference(kind, name, location, scope_id: nil, implicit_hash_value: false,
                           owner: current_owner, write: nil)
        @reference_candidates << Index::ReferenceCandidate.new(
          kind: kind, name: name, location: Index::SourceLocation.to_range(location, @lines), scope_id: scope_id,
          owner: owner, singleton: @cref.declares_singleton?, receiver: nil,
          lexical_nesting: current_lexical_nesting, implicit_hash_value: implicit_hash_value, write: write
        )
      end

      # `node.receiver`'s three shapes: nil (implicit self -- `foo`), a
      # literal constant (`Foo.bar` -- statically known, no type inference
      # needed), or an arbitrary expression (`user.name` -- needs its own
      # type resolved later, so this records *where* to query it rather
      # than a name). `node.name` ending in `=` (an attribute-write call,
      # `user.name = x`) is included the same as any other call; whether
      # that's a meaningful "reference" for Find References is a call-site
      # policy decision, not something worth filtering out here.
      def record_macro_call_range(node)
        return unless node.message_loc

        @macro_call_ranges << Index::SourceLocation.to_range(node.message_loc, @lines)
      end

      def record_method_call_candidate(node)
        return unless node.message_loc

        receiver, singleton =
          if node.receiver.nil?
            [nil, @cref.self_is_module?]
          elsif (name = raw_constant_name(node.receiver))
            [name, true] # `Foo.bar` -- always a class-level call, regardless of the lexical writing context
          else
            # The receiver's *exclusive* end, which is what selects the
            # receiver itself.
            #
            # `contains?` reads a node's exclusive end offset as
            # inclusive (024.20), so an offset one character *inside* the
            # receiver -- which is what this recorded until 0.2.1 -- is
            # also the exclusive end of the receiver's own last element,
            # and the walk answers with the innermost node containing it.
            # Every receiver whose text ends in `]` or `)` was therefore
            # judged as its own last inner expression: `[w].each`
            # reported that a workspace class has no `each`, and
            # `listeners[:on_x]&.each` that a Symbol has none. 1,545 of
            # the 3,362 `unknown-method` reports over Ruby's standard
            # library, five Rails gems and minitest had a receiver of
            # that shape -- 604 in prism's `dispatcher.rb` alone.
            #
            # The exclusive end works *with* the inclusive `contains?`
            # rather than against it: no inner element's range reaches
            # it, and the receiver's does, so the innermost containing
            # node is the receiver. The comment this replaces argued for
            # the character before on the strength of
            # `Article.find(params[:id])` resolving `[]`'s receiver to
            # `Article` -- a constant receiver never reaches this branch,
            # and the shape does not reproduce in either direction.
            position = Index::SourceLocation.to_position(node.receiver.location.end_line,
                                                           node.receiver.location.end_column, @lines)
            # `written_self:` is recorded here because here is where it is
            # known. Since `024.85` gave `self` a type, the undefined-method
            # check can reach one -- and a type read off the enclosing class
            # body is an **upper bound**, not the receiver's class. Inside
            # `class Numeric`, `self` is whichever subclass instance received
            # the call, so `Numeric` declaring no `*` says nothing about it:
            #
            #   $ ruby -e '
            #   p [Numeric.method_defined?(:*), Integer.method_defined?(:*)]
            #   '
            #   # => [false, true]
            #   # ruby 3.4.10
            #
            # The alternative was for the check to look the node up again from
            # the position, which is re-deriving downstream what was in hand
            # upstream -- the shape `049` counts eleven of.
            [{ position: position, written_self: node.receiver.is_a?(Prism::SelfNode) }, false]
          end

        # **`self` at the top level is an `Object`**, so a bare call
        # written there has a receiver after all. Recorded with no owner,
        # `ReceiverResolution` answered no receiver type and every such
        # call resolved to nothing -- which is the other half of
        # `024.230`: giving the *declaration* an owner buys nothing while
        # the *call* still has none.
        #
        #   $ ruby -e '
        #   def helper(a); end
        #   p [Object.private_instance_methods(false).include?(:helper), self.class]
        #   '
        #   # => [true, Object]
        #   # ruby 3.4.10
        #
        # Only a call with no written receiver: one with a receiver
        # already has a type, and the owner is not what answers for it.
        call_owner = current_owner
        call_owner = "Object" if call_owner.nil? && node.receiver.nil? && @cref.top_level?

        @reference_candidates << Index::ReferenceCandidate.new(
          kind: :method_call, name: node.name.to_s, location: Index::SourceLocation.to_range(node.message_loc, @lines),
          scope_id: nil, owner: call_owner, singleton: singleton, receiver: receiver,
          lexical_nesting: current_lexical_nesting, arguments: call_argument_shape(node)
        )
      end

      # What a call site passes, in the terms an arity check needs. A
      # splat makes the positional count a lower bound rather than a
      # count, and `...` forwarding says nothing at all about arity, so
      # both are recorded as such instead of being counted -- a diagnostic
      # that fires on `f(*args)` would be worse than no diagnostic.
      def call_argument_shape(node)
        arguments = node.arguments&.arguments || []
        splat = arguments.any? do |argument|
          argument.is_a?(Prism::SplatNode) || argument.is_a?(Prism::ForwardingArgumentsNode)
        end
        keyword_hashes = arguments.select { |argument| argument.is_a?(Prism::KeywordHashNode) }
        # `**opts` is a KeywordHashNode too, and it passes whatever the
        # hash holds -- nothing at all when it is empty. Its count is not
        # knowable here, so it makes the call as unjudgeable as a splat
        # does. Only literal `k: v` pairs are countable keywords.
        double_splat = keyword_hashes.any? do |hash|
          hash.elements.any? { |element| element.is_a?(Prism::AssocSplatNode) }
        end
        # A double splat makes the whole call unjudgeable, which is what
        # `splat` already means to both readers of this shape -- the arity
        # check and 0.2.0's argument-type check, each of which opens with
        # `next if shape[:splat]`. Zeroing `keywords` as well was dead for
        # the same reason: neither reader is still looking by then.
        splat ||= double_splat
        keywords = keyword_hashes.count
        positionals = arguments.reject do |argument|
          argument.is_a?(Prism::KeywordHashNode) || argument.is_a?(Prism::SplatNode) ||
            argument.is_a?(Prism::ForwardingArgumentsNode) || argument.is_a?(Prism::BlockArgumentNode)
        end
        {
          positional: positionals.size,
          # Where each positional argument actually sits, so a check can
          # ask what type is at that position and report *on the argument*
          # rather than on the whole call (0.2.0's argument type check).
          # The count above stays as it was: it is what the arity check
          # needs, and deriving it from this list is the same number.
          positional_locations: positionals.map { |argument| Index::SourceLocation.to_range(argument.location, @lines) },
          splat: splat,
          keywords: keywords.positive?,
          block: !node.block.nil?
        }
      end

      def constant_full_name(node)
        return nil unless node.respond_to?(:full_name)

        qualify(node.full_name)
      rescue StandardError
        nil
      end

      def update_visibility(node)
        case node.name
        when :public then @cref = @cref.with_visibility(:public)
        when :private then @cref = @cref.with_visibility(:private)
        when :protected then @cref = @cref.with_visibility(:protected)
        when :module_function then @cref = @cref.in_module_function
        end
      end

      VISIBILITY_MODIFIERS = { public: :public, private: :private, protected: :protected }.freeze

      # The class-side pair. They take names only -- there is no
      # section-opening form -- and they name *singleton* methods
      # wherever they are written, which is what makes them a separate
      # table rather than entries in the one above.
      CLASS_VISIBILITY_MODIFIERS = { private_class_method: :private, public_class_method: :public }.freeze

      # `private`/`protected`/`public` *with* arguments do not open a
      # section -- they change the visibility of exactly the methods named.
      # Only the bare, argumentless section form was handled, so both
      # `private def prepare; end` (idiomatic in Rails controllers) and
      # `private :prepare` recorded the method as public.
      #
      # That is a visibility-model gap, not a view-propagation gap, so it
      # is fixed here rather than in any one consumer: `contributing_actions`
      # (Rails action detection), completion filtering and method
      # resolution all read `Declaration#visibility` and all inherited the
      # same wrong answer.
      #
      # `private def …` is retroactive in the same pass because Prism
      # visits the CallNode before its DefNode argument only in source
      # order -- the DefNode is an *argument*, so `super` below visits it
      # after this runs. Matching on the recorded declaration afterwards
      # would need the def's location, which is exactly what the argument
      # node already carries; both forms therefore resolve through the
      # same by-name rewrite, applied to declarations already recorded and
      # to the pending inline def once `super` records it.
      def apply_visibility_arguments(node)
        visibility = VISIBILITY_MODIFIERS[node.name]
        return unless visibility
        # Inside `class << self`, `private :show` names the *singleton*
        # method. Declarations for singleton methods carry no visibility
        # (visit_def_node records nil for them), so there is nothing to
        # rewrite -- and rewriting by owner alone would hit the
        # same-named instance method instead, privatizing a real Rails
        # action and dropping it from view propagation.
        #
        # An *alias* is safe to rewrite here even so: an `AliasFact`
        # carries `singleton` itself, so naming one inside `class << self`
        # cannot reach the same-named instance alias. Without this,
        # `class << self; alias_method :aka, :build; private :aka; end`
        # offered `aka` on the class side, which raises.
        if @cref.declares_singleton?
          rewrite_recorded_alias_visibility(symbol_argument_names(node), visibility, singleton: true)
          return
        end
        # `private :target` written inside a method body never runs at
        # class level in Ruby, so it must not retroactively change a
        # declaration either.
        return if @cref.in_method_body?

        # Only a `def` argument needs a pending entry: it is the one form
        # whose declaration has not been recorded yet, and `visit_def_node`
        # consumes the entry moments later. A symbol/string argument names
        # a method that already exists, so `rewrite_recorded_visibility`
        # below fully handles it -- recording a pending entry for it too
        # left an unconsumed trap that the *next* `def` of that name
        # claimed instead. `def target; private :target; def target` (a
        # same-file reopen) then recorded the second, public definition as
        # private, dropping the action from view propagation.
        pending_names = []
        names = node.arguments.arguments.filter_map do |argument|
          case argument
          when Prism::SymbolNode then argument.unescaped
          when Prism::StringNode then argument.unescaped
          when Prism::DefNode
            # `private def self.x` / `private def Helper.x` declare a
            # singleton method, which carries no recorded visibility --
            # so there is nothing to rewrite, and rewriting by name and
            # owner alone reached the *instance* method `x` instead. That
            # privatized a real Rails action and dropped it from view
            # propagation, the same cross-kind hit the `class << self`
            # guard above exists to prevent. The pending entry leaked the
            # same way: it is stored under `current_owner` but consumed
            # under the def's own owner, so `private def Helper.foo`
            # inside `class A` sat there until `A#foo` claimed it.
            next if argument.receiver

            pending_names << argument.name.to_s
            argument.name.to_s
          end
        end
        return if names.empty?

        unless pending_names.empty?
          @pending_visibility_names ||= {}
          pending_names.each { |name| @pending_visibility_names[[current_owner, name]] = visibility }
        end
        # Instance side only: the `class << self` branch above returned
        # before reaching here, and `private_class_method` has its own
        # path.
        rewrite_recorded_visibility(names, visibility)
        rewrite_recorded_alias_visibility(names, visibility, singleton: false)
      end

      # `private_class_method :build` names a singleton method that has
      # already been declared, wherever it is written -- there is no
      # section-opening form to track and no pending entry to leave. A
      # `def` argument (`private_class_method def self.x; end`) is
      # recorded before this runs for the same reason the instance-side
      # symbol form is.
      def apply_class_visibility_arguments(node)
        visibility = CLASS_VISIBILITY_MODIFIERS.fetch(node.name)
        return if @cref.in_method_body? || node.arguments.nil?

        names = node.arguments.arguments.filter_map { |argument| symbol_name(argument) }
        return if names.empty?

        rewrite_recorded_visibility(names, visibility, kind: :singleton_method)
        rewrite_recorded_alias_visibility(names, visibility, singleton: true)
      end

      def visibility_for_definition(node, singleton, inline_visibility)
        # Under `module_function`, Ruby makes the instance copy private --
        # `MF.private_instance_methods(false)` is `[:mf_a]` -- which is
        # what keeps it from being offered on an instance of an including
        # class. An explicit `private def` still outranks it.
        return inline_visibility || :private if !singleton && @cref.module_function?
        return inline_visibility || @cref.visibility unless singleton
        # Singleton *because* of `class << self`, not because of an
        # explicit `self.` receiver.
        return inline_visibility || @cref.visibility if node.receiver.nil? && @cref.declares_singleton?

        inline_visibility
      end

      # `private :aka` names an alias as readily as a `def`, and an alias
      # has no declaration to rewrite -- so the visibility went nowhere
      # and completion offered a name that raises. Recorded on the fact
      # itself, which is what `MethodResolver#alias_visibility_of` reads.
      # The plain `:name` arguments of a visibility call, ignoring the
      # `def` and receiver-qualified forms the caller handles separately.
      def symbol_argument_names(node)
        node.arguments&.arguments.to_a.filter_map { |argument| symbol_name(argument) }
      end

      def rewrite_recorded_alias_visibility(names, visibility, singleton:)
        @alias_facts.map! do |fact|
          next fact unless fact.singleton == singleton
          next fact unless fact.owner == current_owner && names.include?(fact.new_name)

          fact.with(visibility: visibility)
        end
      end

      def rewrite_recorded_visibility(names, visibility, kind: :instance_method)
        @declarations.map! do |declaration|
          next declaration unless declaration.symbol_id.kind == kind
          next declaration unless declaration.symbol_id.owner == current_owner
          next declaration unless names.include?(declaration.symbol_id.name)

          Index::Declaration.new(
            symbol_id: declaration.symbol_id,
            location: declaration.location,
            visibility: visibility,
            parameters: declaration.parameters,
            origin: declaration.origin,
            body_source: declaration.body_source,
            name_location: declaration.name_location
          )
        end
      end

      # Every positional slot the declaration has, in declaration order,
      # named where a name exists.
      #
      # Two things this got wrong until round 28, both from the same
      # assumption -- that a positional parameter always has a `#name` and
      # always lives in `requireds`:
      #
      # 1. A *destructuring* parameter (`def m(a, (b, c))`) is a
      #    `Prism::MultiTargetNode`, which has no `#name` at all, so reading
      #    one raised `NoMethodError` out of `#summarize`. That is not a
      #    degraded parameter list, it is the loss of the *entire file*: a
      #    `#summarize` that raises produces no FileSummary, so every
      #    declaration in that file disappears from the index and hover,
      #    go-to-definition, completion and diagnostics all go dark for it.
      #    Measured: a workspace file containing one such method was logged
      #    as `cold index: failed to index <file>: NoMethodError: undefined
      #    method 'name' for an instance of Prism::MultiTargetNode` and
      #    contributed nothing. `LocalInferencer` already guards its own
      #    block-parameter reads with `respond_to?(:name)` for exactly this
      #    node; this path did not.
      # 2. `posts` -- the required parameters that follow a `*rest`, as in
      #    `def m(a, *rest, b)` -- were never read at all, so `b` was
      #    reported as not existing (signature help rendered `m(a, rest)`).
      def extract_parameters(parameters_node)
        return [] unless parameters_node

        params = []
        parameters_node.requireds.each { |p| params << param(parameter_name(p), :required) }
        parameters_node.optionals.each { |p| params << param(parameter_name(p), :optional, p.value) }
        if parameters_node.rest.is_a?(Prism::RestParameterNode)
          params << param(parameter_name(parameters_node.rest), :rest)
        end
        parameters_node.posts.each { |p| params << param(parameter_name(p), :required) }
        parameters_node.keywords.each do |p|
          kind = p.is_a?(Prism::OptionalKeywordParameterNode) ? :keyword_optional : :keyword
          params << param(parameter_name(p), kind, p.respond_to?(:value) ? p.value : nil)
        end
        case parameters_node.keyword_rest
        when Prism::KeywordRestParameterNode
          params << param(parameter_name(parameters_node.keyword_rest), :keyrest)
        when Prism::ForwardingParameterNode
          # `def m(...)` forwards every argument, so the parameter list is
          # not a mapping at all. Prism puts `...` in `keyword_rest`, and
          # reading only `KeywordRestParameterNode` recorded such a method
          # as taking *nothing* -- so the arity check judged every call to
          # it. Recorded as a rest parameter, which is what the check
          # already bails out on.
          params << param("...", :rest)
        end
        params << param(parameter_name(parameters_node.block), :block) if parameters_node.block

        params
      end

      # Not every parameter node carries a name, and asking one that doesn't
      # is what took a whole file's index down (above). A `nil` name is
      # already an ordinary, supported shape here -- an anonymous `*`/`**`/
      # `&` produces one too, and every consumer already handles it
      # (`MethodAnalyzer` guards on `if param.name`, `QueryService`'s
      # signature label renders it as an empty segment) -- so the slot is
      # kept rather than dropped, which is what keeps every later parameter
      # at its own position.
      def parameter_name(node)
        node.name if node.respond_to?(:name)
      end

      # A half-typed default is a `MissingNode`, and its `slice` is the
      # `=` itself -- so `def f(a = )`, an ordinary buffer mid-edit,
      # recorded `default_source` as `"="`. Nothing rendered it until
      # `024.89`, at which point the label would have read `a = =`. The
      # default is unreadable here, not equal to an equals sign, so
      # nothing is recorded and `Index::Parameter#label` says the
      # parameter is optional without inventing a value for it.
      def param(name, kind, default_node = nil)
        readable = default_node unless default_node.is_a?(Prism::MissingNode)
        Index::Parameter.new(name: name&.to_s, kind: kind, default_source: readable&.slice)
      end
    end
    private_constant :Visitor
  end
end
