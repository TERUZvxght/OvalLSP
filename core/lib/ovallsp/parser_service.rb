# frozen_string_literal: true

require "digest"
require "prism"

require_relative "index/symbol_id"
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

      visitor = Visitor.new(lines).tap { |v| result.value.accept(v) }

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
        declarations: visitor.declarations,
        diagnostics: parse_diagnostics(result, lines, erb: erb_document?(document.uri)),
        ancestor_facts: visitor.ancestor_facts,
        alias_facts: visitor.alias_facts,
        reference_candidates: visitor.reference_candidates,
        generated_method_facts: visitor.generated_method_facts
      )
    end

    private

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

      attr_reader :declarations, :ancestor_facts, :alias_facts, :reference_candidates, :generated_method_facts

      # Task 017's priority-ordered DSL list, scoped to the three this
      # task actually implements (enum/scope/delegate) -- attribute/
      # store_accessor/has_one/polymorphic/Concern/helper_method/mailer-
      # job entry points are explicitly deferred (docs/design/tasks/017-rails-dsl-extension.md).
      GENERATED_METHOD_DSLS = %i[enum scope delegate].freeze

      def initialize(lines)
        super()
        @lines = lines
        @declarations = []
        @ancestor_facts = []
        @alias_facts = []
        @reference_candidates = []
        @generated_method_facts = []
        @owner_stack = []
        @singleton_context_stack = [false]
        @visibility_stack = [:public]
        @in_method_body = false
        # Task 014: a fresh local-variable scope id per class/module body,
        # `def`, `class << self`, and block — matching real Ruby's own
        # local-scoping boundaries (verified live: `class << self` does
        # NOT see an enclosing class body's locals, the same as a `def`
        # wouldn't). #next_scope_id is only ever called while entering one
        # of those, so two same-named locals in different scopes never
        # share a scope id.
        @scope_counter = 0
        @scope_stack = [next_scope_id]
      end

      def visit_module_node(node)
        visit_namespace(node, kind: :module)
      end

      def visit_class_node(node)
        visit_namespace(node, kind: :class)
      end

      def visit_singleton_class_node(node)
        @singleton_context_stack.push(true)
        # A `class << self` body has its own visibility section, exactly
        # as a class/module body does (see #visit_namespace, which has
        # always pushed both). Without this, a bare `private` inside the
        # singleton block set the *enclosing class's* visibility frame and
        # never restored it, so every instance method declared after the
        # block was recorded private. That was latent until Rails action
        # detection began filtering on `visibility == :public`, at which
        # point those methods stopped being actions and their ivars
        # silently vanished from the corresponding views.
        @visibility_stack.push(:public)
        @scope_stack.push(next_scope_id)
        super
      ensure
        @singleton_context_stack.pop
        @visibility_stack.pop
        @scope_stack.pop
      end

      def visit_def_node(node)
        singleton = node.receiver.is_a?(Prism::SelfNode) || (@singleton_context_stack.last && node.receiver.nil?)
        owner_receiver = node.receiver
        owner =
          if owner_receiver && !owner_receiver.is_a?(Prism::SelfNode)
            constant_full_name(owner_receiver) || current_owner
          else
            current_owner
          end

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
          visibility: singleton ? nil : (inline_visibility || @visibility_stack.last),
          parameters: extract_parameters(node.parameters),
          origin: :source,
          body_source: node.body&.slice,
          name_location: Index::SourceLocation.to_range(node.name_loc, @lines)
        )

        @scope_stack.push(next_scope_id)
        # Tracks "we are inside a method body", so a `private :target`
        # written there -- which never runs at class level in Ruby -- does
        # not retroactively rewrite a declaration. Restored rather than
        # cleared, since `private def foo; ...; end` nests a def inside a
        # call inside a def in the argument-form case.
        previous_in_method_body = @in_method_body
        @in_method_body = true
        # Same frame discipline as blocks and `class << self`: a bare
        # `private` written inside a method body must not rewrite the
        # class's open section. `@in_method_body` already stopped the
        # `private :x` argument form from doing this; the argumentless
        # form went straight to `update_visibility` and was unguarded, so
        # `def wrapper; private; end` privatised every method declared
        # after it. Guarding one call site was the symptom fix -- the
        # frame is the cause.
        @visibility_stack.push(@visibility_stack.last)
        super
      ensure
        @visibility_stack.pop
        @in_method_body = previous_in_method_body
        @scope_stack.pop
      end

      def visit_call_node(node)
        if node.receiver.nil?
          update_visibility(node) if node.arguments.nil?
          apply_visibility_arguments(node) unless node.arguments.nil?
          record_ancestor_call(node) if ANCESTOR_RELATIONS.key?(node.name)
          record_alias_method_call(node) if node.name == :alias_method
          record_generated_methods(node) if current_owner && GENERATED_METHOD_DSLS.include?(node.name)
        end
        record_method_call_candidate(node)
        super
      end

      def visit_block_node(node)
        @scope_stack.push(next_scope_id)
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
        @visibility_stack.push(@visibility_stack.last)
        super
      ensure
        @visibility_stack.pop
        @scope_stack.pop
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
        record_reference(:local_variable, node.name.to_s, node.location, scope_id: current_scope_id)
        super
      end

      def visit_local_variable_write_node(node)
        record_reference(:local_variable, node.name.to_s, node.name_loc, scope_id: current_scope_id)
        super
      end

      def visit_instance_variable_read_node(node)
        record_reference(:ivar, node.name.to_s, node.location)
        super
      end

      def visit_instance_variable_write_node(node)
        record_reference(:ivar, node.name.to_s, node.name_loc)
        super
      end

      def visit_class_variable_read_node(node)
        record_reference(:cvar, node.name.to_s, node.location)
        super
      end

      def visit_class_variable_write_node(node)
        record_reference(:cvar, node.name.to_s, node.name_loc)
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
            singleton: @singleton_context_stack.last,
            location: Index::SourceLocation.to_range(node.location, @lines)
          )
        end

        super
      end

      def visit_constant_write_node(node)
        @declarations << Index::Declaration.new(
          symbol_id: Index::SymbolId.new(kind: :constant, owner: current_owner, name: node.name.to_s, discriminator: nil),
          location: Index::SourceLocation.to_range(node.location, @lines),
          visibility: nil,
          parameters: [],
          origin: :source,
          name_location: Index::SourceLocation.to_range(node.name_loc, @lines)
        )

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

        within_namespace(absolute_name) { node.each_child_node { |child| child.accept(self) } }
      end

      def within_namespace(absolute_name)
        @owner_stack.push(absolute_name)
        @singleton_context_stack.push(false)
        @visibility_stack.push(:public)
        @scope_stack.push(next_scope_id)
        yield
      ensure
        @owner_stack.pop
        @singleton_context_stack.pop
        @visibility_stack.pop
        @scope_stack.pop
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

      def qualify(local_path)
        return local_path if local_path.start_with?("::")

        current_owner ? "#{current_owner}::#{local_path}" : "::#{local_path}"
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
      def record_superclass(node, owner)
        return unless node.superclass

        @ancestor_facts << Index::AncestorFact.new(
          owner: owner, relation: :superclass, target: raw_constant_name(node.superclass),
          location: Index::SourceLocation.to_range(node.superclass.location, @lines)
        )
      end

      def record_ancestor_call(node)
        return unless node.arguments

        relation = ANCESTOR_RELATIONS.fetch(node.name)
        node.arguments.arguments.each do |arg|
          target = raw_constant_name(arg)
          next unless target

          @ancestor_facts << Index::AncestorFact.new(
            owner: current_owner, relation: relation, target: target,
            location: Index::SourceLocation.to_range(arg.location, @lines)
          )
        end
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
          singleton: @singleton_context_stack.last,
          location: Index::SourceLocation.to_range(node.location, @lines)
        )
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

        enum_value_names(node).each do |value_name|
          add_generated_method(
            node: node, name: "#{value_name}?", kind: :instance_method,
            return_type: Types::Nominal.new(name: "Boolean"), origin: :enum, metadata: { value: value_name }
          )
        end
      end

      def enum_value_names(node)
        first = node.arguments.arguments.first
        values_node =
          if first.is_a?(Prism::KeywordHashNode)
            first.elements.first&.value
          else
            node.arguments.arguments[1]
          end

        case values_node
        when Prism::HashNode then values_node.elements.filter_map { |e| symbol_name(e.key) }
        when Prism::ArrayNode then values_node.elements.filter_map { |e| symbol_name(e) }
        else []
        end
      end

      # `scope :active, -> { where(active: true) }` -- the scope body
      # itself is never analyzed ("dynamic body内部型の断定はしない"); only
      # its name and the fact that it returns `Relation[Model]` are
      # statically knowable.
      def record_scope(node)
        return unless node.arguments

        name = symbol_name(node.arguments.arguments.first)
        return unless name

        return_type = Types::Generic.new(name: "Relation", type_arg: Types::Nominal.new(name: simple_owner_name))
        add_generated_method(node: node, name: name, kind: :singleton_method, return_type: return_type, origin: :scope)
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
                            .filter_map { |a| symbol_name(a) }

        method_names.each do |delegated_name|
          generated_name = prefix ? "#{target}_#{delegated_name}" : delegated_name
          add_generated_method(
            node: node, name: generated_name, kind: :instance_method, return_type: Types::UNKNOWN, origin: :delegate,
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

      def add_generated_method(node:, name:, kind:, return_type:, origin:, metadata: {})
        symbol_id = Index::SymbolId.new(kind: kind, owner: current_owner, name: name, discriminator: nil)
        location = Index::SourceLocation.to_range(node.location, @lines)

        @declarations << Index::Declaration.new(
          symbol_id: symbol_id, location: location, visibility: :public, parameters: [], origin: :generated
        )
        @generated_method_facts << Index::GeneratedMethodFact.new(
          owner: current_owner, name: name, kind: kind, return_type: return_type, source_location: location,
          origin: origin, confidence: :high, metadata: metadata
        )
      end

      def simple_owner_name
        current_owner.to_s.split("::").last
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

      def current_owner
        @owner_stack.last
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
        @owner_stack.reverse
      end

      def next_scope_id
        @scope_counter += 1
      end

      def current_scope_id
        @scope_stack.last
      end

      def record_reference(kind, name, location, scope_id: nil)
        @reference_candidates << Index::ReferenceCandidate.new(
          kind: kind, name: name, location: Index::SourceLocation.to_range(location, @lines), scope_id: scope_id,
          owner: current_owner, singleton: @singleton_context_stack.last, receiver: nil,
          lexical_nesting: current_lexical_nesting
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
      def record_method_call_candidate(node)
        return unless node.message_loc

        receiver, singleton =
          if node.receiver.nil?
            [nil, @singleton_context_stack.last]
          elsif (name = raw_constant_name(node.receiver))
            [name, true] # `Foo.bar` -- always a class-level call, regardless of the lexical writing context
          else
            # One character *inside* the receiver, not one past it. Past
            # it is the following token -- the `[` of `params[:id]` --
            # and that position belongs to the enclosing expression too,
            # so `Article.find(params[:id])` resolved `[]`'s receiver to
            # Article and reported a missing `[]` on the model. The last
            # character of the receiver is unambiguously the receiver's.
            position = Index::SourceLocation.to_position(node.receiver.location.end_line,
                                                           [node.receiver.location.end_column - 1, 0].max, @lines)
            [{ position: position }, false] # arbitrary expression receiver -- always an instance call
          end

        @reference_candidates << Index::ReferenceCandidate.new(
          kind: :method_call, name: node.name.to_s, location: Index::SourceLocation.to_range(node.message_loc, @lines),
          scope_id: nil, owner: current_owner, singleton: singleton, receiver: receiver,
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
        keywords = arguments.count { |argument| argument.is_a?(Prism::KeywordHashNode) }
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
        when :public then @visibility_stack[-1] = :public
        when :private then @visibility_stack[-1] = :private
        when :protected then @visibility_stack[-1] = :protected
        end
      end

      VISIBILITY_MODIFIERS = { public: :public, private: :private, protected: :protected }.freeze

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
        return if @singleton_context_stack.last
        # `private :target` written inside a method body never runs at
        # class level in Ruby, so it must not retroactively change a
        # declaration either.
        return if @in_method_body

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
        rewrite_recorded_visibility(names, visibility)
      end

      def rewrite_recorded_visibility(names, visibility)
        @declarations.map! do |declaration|
          next declaration unless declaration.symbol_id.kind == :instance_method
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
        if parameters_node.keyword_rest.is_a?(Prism::KeywordRestParameterNode)
          params << param(parameter_name(parameters_node.keyword_rest), :keyrest)
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

      def param(name, kind, default_node = nil)
        Index::Parameter.new(name: name&.to_s, kind: kind, default_source: default_node&.slice)
      end
    end
    private_constant :Visitor
  end
end
