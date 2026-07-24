# frozen_string_literal: true

require "digest"
require "prism"

require_relative "index/symbol_id"
require_relative "index/parameter"
require_relative "index/declaration"
require_relative "index/ancestor_fact"
require_relative "index/alias_fact"
require_relative "index/file_summary"
require_relative "index/source_location"
require_relative "erb/ruby_region_extractor"

module Rslsp
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
        diagnostics: result.errors.map { |error| to_diagnostic(error, lines) },
        ancestor_facts: visitor.ancestor_facts,
        alias_facts: visitor.alias_facts
      )
    end

    private

    def erb_document?(uri)
      uri.to_s.end_with?(".erb")
    end

    def to_diagnostic(error, lines)
      {
        range: Index::SourceLocation.to_range(error.location, lines),
        severity: DIAGNOSTIC_ERROR_SEVERITY,
        message: error.message,
        source: "rslsp"
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

      attr_reader :declarations, :ancestor_facts, :alias_facts

      def initialize(lines)
        super()
        @lines = lines
        @declarations = []
        @ancestor_facts = []
        @alias_facts = []
        @owner_stack = []
        @singleton_context_stack = [false]
        @visibility_stack = [:public]
      end

      def visit_module_node(node)
        visit_namespace(node, kind: :module)
      end

      def visit_class_node(node)
        visit_namespace(node, kind: :class)
      end

      def visit_singleton_class_node(node)
        @singleton_context_stack.push(true)
        super
      ensure
        @singleton_context_stack.pop
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

        @declarations << Index::Declaration.new(
          symbol_id: symbol_id,
          location: Index::SourceLocation.to_range(node.location, @lines),
          visibility: singleton ? nil : @visibility_stack.last,
          parameters: extract_parameters(node.parameters),
          origin: :source,
          body_source: node.body&.slice
        )

        super
      end

      def visit_call_node(node)
        if node.receiver.nil?
          update_visibility(node) if node.arguments.nil?
          record_ancestor_call(node) if ANCESTOR_RELATIONS.key?(node.name)
          record_alias_method_call(node) if node.name == :alias_method
        end
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
          origin: :source
        )

        super
      end

      private

      def visit_namespace(node, kind:)
        local_path = node.constant_path.full_name
        absolute_name = qualify(local_path)

        @declarations << Index::Declaration.new(
          symbol_id: Index::SymbolId.new(kind: kind, owner: current_owner, name: absolute_name, discriminator: nil),
          location: Index::SourceLocation.to_range(node.location, @lines),
          visibility: nil,
          parameters: [],
          origin: :source
        )

        record_superclass(node, absolute_name) if node.is_a?(Prism::ClassNode)

        @owner_stack.push(absolute_name)
        @singleton_context_stack.push(false)
        @visibility_stack.push(:public)
        node.each_child_node { |child| child.accept(self) }
      ensure
        @owner_stack.pop
        @singleton_context_stack.pop
        @visibility_stack.pop
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
      def record_superclass(node, owner)
        return unless node.superclass

        target = raw_constant_name(node.superclass)
        return unless target

        @ancestor_facts << Index::AncestorFact.new(
          owner: owner, relation: :superclass, target: target,
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

      def extract_parameters(parameters_node)
        return [] unless parameters_node

        params = []
        parameters_node.requireds.each { |p| params << param(p.name, :required) }
        parameters_node.optionals.each { |p| params << param(p.name, :optional, p.value) }
        params << param(parameters_node.rest.name, :rest) if parameters_node.rest.is_a?(Prism::RestParameterNode)
        parameters_node.keywords.each do |p|
          kind = p.is_a?(Prism::OptionalKeywordParameterNode) ? :keyword_optional : :keyword
          params << param(p.name, kind, p.respond_to?(:value) ? p.value : nil)
        end
        if parameters_node.keyword_rest.is_a?(Prism::KeywordRestParameterNode)
          params << param(parameters_node.keyword_rest.name, :keyrest)
        end
        params << param(parameters_node.block.name, :block) if parameters_node.block

        params
      end

      def param(name, kind, default_node = nil)
        Index::Parameter.new(name: name&.to_s, kind: kind, default_source: default_node&.slice)
      end
    end
    private_constant :Visitor
  end
end
