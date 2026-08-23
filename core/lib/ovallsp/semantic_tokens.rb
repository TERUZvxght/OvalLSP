# frozen_string_literal: true

module Ovallsp
  # Semantic highlighting (0.2.0).
  #
  # Ruby's `foo` is ambiguous between a local variable and a method call
  # on self, and a grammar cannot tell them apart -- it has no scope. The
  # engine already parses the file and knows which, so the editor colours
  # them the same only because nobody told it otherwise.
  #
  # Deliberately narrow. This reports the things a *parser* settles and a
  # regex cannot; it does not re-colour keywords, strings or numbers,
  # which the TextMate grammar already gets right and which a second,
  # disagreeing opinion would only make flicker.
  module SemanticTokens
    # Index into this list is the `tokenType` an encoded token carries, so
    # the order is part of the protocol: appending is safe, reordering is
    # not.
    LEGEND = %w[variable parameter property method class namespace].freeze
    TYPE_INDEX = LEGEND.each_with_index.to_h { |name, index| [name.to_sym, index] }.freeze

    # No modifiers are reported. An empty list is a valid legend and says
    # honestly that nothing here distinguishes a declaration from a use;
    # declaring modifiers we never emit would invite a client to render
    # for them.
    MODIFIERS = [].freeze

    Token = Data.define(:line, :character, :length, :type)

    module_function

    # The LSP `data` array: five integers per token -- deltaLine,
    # deltaStartChar, length, tokenType, tokenModifiers -- sorted by
    # position, each relative to the token before it.
    def encode(document)
      tokens = collect(document)
      previous_line = 0
      previous_character = 0

      tokens.flat_map do |token|
        delta_line = token.line - previous_line
        delta_character = delta_line.zero? ? token.character - previous_character : token.character
        previous_line = token.line
        previous_character = token.character
        [delta_line, delta_character, token.length, TYPE_INDEX.fetch(token.type), 0]
      end
    end

    def collect(document)
      # An .erb template's Ruby lives in its tags; the extractor blanks
      # everything else while preserving line and column layout, so a
      # token's position in the extracted source is its position in the
      # template. Highlighting the raw template instead means parsing HTML
      # as Ruby.
      # By URI suffix, as `Server#erb_view?` and `Engine#analysis_document`
      # both do. Not by `language_id`: VS Code assigns no built-in id to
      # `.erb`, so the extension registers those files by pattern with no
      # id at all -- keying on one meant this produced nothing for exactly
      # the templates it advertises covering.
      erb = document.uri.to_s.end_with?(".erb")
      source = erb ? Erb::RubyRegionExtractor.extract_ruby_source(document.text) : document.text
      result = Prism.parse(source)
      # A file mid-edit does not parse, and a partial tree yields tokens
      # for the half of the file above the break and none below it --
      # which reads as highlighting that keeps falling off. Returning
      # nothing lets the client keep the tokens it already has.
      return [] if result.failure?

      visitor = Collector.new(source.lines)
      result.value.accept(visitor)
      visitor.tokens.sort_by { |token| [token.line, token.character] }
    rescue StandardError
      []
    end

    # Walks the tree recording only what the parser settles.
    class Collector < Prism::Visitor
      attr_reader :tokens

      def initialize(lines)
        @lines = lines
        @tokens = []
        @claimed = {}
        super()
      end

      def visit_local_variable_read_node(node)
        record(node.location, :variable)
        super
      end

      def visit_local_variable_write_node(node)
        record(node.name_loc, :variable)
        super
      end

      def visit_instance_variable_read_node(node)
        record(node.location, :property)
        super
      end

      def visit_instance_variable_write_node(node)
        record(node.name_loc, :property)
        super
      end

      # Every remaining write shape Ruby has for these two, and the three
      # parameter forms with no node type of their own above. Without
      # them the same identifier was classified on one line and left
      # unclassified on the next inside one method: `sum = amount` marked,
      # `sum += 1` not; `@memo = sum` marked, `@memo ||= sum` not; and
      # `*rest`, `**kw`, `&blk` never.
      #
      # `*_target_node` is the multiple-assignment and block-parameter
      # form (`a, @b = 1, 2`). `engine.rb`'s `IvarWriteCollector`
      # enumerates the same five ivar shapes, for the same reason.
      {
        local_variable_or_write_node: :variable,
        local_variable_and_write_node: :variable,
        local_variable_operator_write_node: :variable,
        local_variable_target_node: :variable,
        instance_variable_or_write_node: :property,
        instance_variable_and_write_node: :property,
        instance_variable_operator_write_node: :property,
        instance_variable_target_node: :property,
        rest_parameter_node: :parameter,
        keyword_rest_parameter_node: :parameter,
        block_parameter_node: :parameter
      }.each do |suffix, type|
        define_method(:"visit_#{suffix}") do |node|
          # A target node *is* its name; a write node has a `name_loc`,
          # and an anonymous `*`/`**`/`&` has neither a name nor a
          # `name_loc` to mark.
          location = node.respond_to?(:name_loc) ? node.name_loc : node.location
          record(location, type) if location
          super(node)
        end
      end

      # The other half of the ambiguity: a bare `foo` that Prism resolved
      # to a call rather than a local read. Only the name is marked, not
      # the arguments -- those are expressions with their own tokens.
      #
      # Named methods only. An operator call's message is `+`, which the
      # grammar already colours and this class says it does not touch; and
      # an index call's message location spans `[idx]` *including the
      # index expression*, so marking it produces a token overlapping the
      # one for `idx` -- which the protocol forbids, on `hash[key]` and
      # every other ordinary subscript.
      def visit_call_node(node)
        record(node.message_loc, :method) if node.message_loc && node.name.to_s.match?(/\A[A-Za-z_]/)
        super
      end

      def visit_constant_read_node(node)
        record(node.location, :class)
        super
      end

      # `024.21`. Without this, only the head of `Ovallsp::Server` was
      # visited -- Prism nests a path as `ConstantPathNode(parent:
      # ConstantReadNode)`, so `visit_constant_read_node` fired for
      # `Ovallsp` and nothing reached `Server`. A semantic token
      # overrides the editor's grammar colour, so every namespaced
      # constant rendered with its two halves coloured by different
      # systems.
      #
      # **A segment with something after it is a namespace
      # syntactically** -- it is being qualified through, whatever it was
      # declared as -- so that is decidable here, and it is what makes
      # the declaration and the read agree: `module Ovallsp` and the
      # `Ovallsp` of `Ovallsp::Server` are both `namespace` now.
      #
      # The final segment stays `:class`, which is what a bare constant
      # read already gets. Telling a class from a module there needs
      # resolution this collector does not have, and guessing is the
      # wrong-answer half of section 0.
      def visit_constant_path_node(node)
        record(node.name_loc, :class) if node.name_loc
        mark_namespace_segments(node.parent)
        super
      end

      # Every segment left of the last one, innermost outward. Recorded
      # rather than visited, because visiting would take the `:class`
      # branch above for the head and the whole point is that it is not
      # one here.
      def mark_namespace_segments(node)
        case node
        when Prism::ConstantReadNode then record(node.location, :namespace)
        when Prism::ConstantPathNode
          record(node.name_loc, :namespace) if node.name_loc
          mark_namespace_segments(node.parent)
        end
      end

      def visit_class_node(node)
        record(node.constant_path.location, :class)
        super
      end

      def visit_module_node(node)
        record(node.constant_path.location, :namespace)
        super
      end

      def visit_required_parameter_node(node)
        record(node.location, :parameter)
        super
      end

      def visit_optional_parameter_node(node)
        record(node.name_loc, :parameter)
        super
      end

      def visit_required_keyword_parameter_node(node)
        record(node.name_loc, :parameter)
        super
      end

      def visit_optional_keyword_parameter_node(node)
        record(node.name_loc, :parameter)
        super
      end

      private

      # A token that spans lines cannot be encoded -- the protocol's
      # `length` is within one line -- and a multi-line call chain's
      # message never does, so anything that does is not what this
      # reports.
      # An identifier, an ivar/gvar/cvar, a constant, or a keyword
      # parameter's `name:` -- everything this collector marks.
      NAME_SHAPE = /\A[@$]{0,2}[A-Za-z_][A-Za-z0-9_]*[?!=]?:?\z/

      def record(location, type)
        return unless location
        return unless location.start_line == location.end_line

        # The slice has to look like a name. Prism falls back to a whole
        # node when it cannot locate the name inside it -- a named capture
        # in a regex containing an escape gives a
        # `LocalVariableTargetNode` whose location is the entire literal,
        # and a semantic token overrides the grammar, so the regex
        # rendered as a variable. Four times in the stdlib.
        return unless NAME_SHAPE.match?(location.slice)

        range = Index::SourceLocation.to_range(location, @lines)
        # Single-line by the check above, so the columns are on the same
        # line and the subtraction is a real length. No zero-length guard:
        # a name is at least one character, and a guard nothing can reach
        # states an invariant it does not enforce.
        length = range[:end][:character] - range[:start][:character]

        # First writer wins, and the outer node is visited first: `module
        # Billing` records its name as a namespace, and the descent then
        # reaches the same constant as a plain read and would record it a
        # second time as a class. Two tokens at one position is not a
        # protocol error -- the client simply renders whichever it likes,
        # which is highlighting that depends on nothing the reader can see.
        key = [range[:start][:line], range[:start][:character]]
        return if @claimed.key?(key)

        @claimed[key] = true
        @tokens << Token.new(line: range[:start][:line], character: range[:start][:character],
                             length: length, type: type)
      end
    end
  end
end
