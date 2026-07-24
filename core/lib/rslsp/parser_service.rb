# frozen_string_literal: true

require "digest"
require "prism"

require_relative "index/symbol_id"
require_relative "index/parameter"
require_relative "index/declaration"
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

      declarations = Visitor.new(lines).tap { |visitor| result.value.accept(visitor) }.declarations

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
        declarations: declarations,
        diagnostics: result.errors.map { |error| to_diagnostic(error, lines) }
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
      attr_reader :declarations

      def initialize(lines)
        super()
        @lines = lines
        @declarations = []
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
          origin: :source
        )

        super
      end

      def visit_call_node(node)
        update_visibility(node) if node.receiver.nil? && node.arguments.nil?
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
