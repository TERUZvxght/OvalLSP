# frozen_string_literal: true

module Ovallsp
  module Semantic
    # Candidates for a bare prefix -- what to offer when the user has typed
    # `art` with no receiver in front of it (0.2.0, closes 024.R8).
    #
    # The receiver-based path answers a narrow question: given this exact
    # type, what can be called on it. A bare prefix asks a much wider one,
    # and the difficulty is entirely in the answer's *size*. `a` matches
    # thousands of symbols in a real workspace, and an editor handed all of
    # them sorted alphabetically is worse than one handed none: VS Code will
    # show them, the right answer will be on page four, and the user learns
    # to stop pressing the key.
    #
    # So this class is mostly ranking and bounding, and the ordering rule is
    # a single idea -- offer what is *closest to the cursor* first:
    #
    #   locals -> methods on self -> workspace constants -> Kernel
    #
    # with a hard cap and `isIncomplete` when it bites, so the editor
    # re-asks as the prefix narrows instead of filtering a truncated list
    # itself.
    class PrefixCompletion
      # Enough to fill a completion popup several times over; small enough
      # that assembling it stays cheap on the request path, which holds the
      # index lock.
      MAX_ITEMS = 50

      # Below this, the two workspace-wide sources are skipped entirely.
      # One character matches essentially every constant and every Kernel
      # method, so including them means burying the two sources that are
      # actually near the cursor under noise that carries no information.
      MIN_PREFIX_FOR_WORKSPACE = 2

      # LSP CompletionItemKind.
      KIND_METHOD = 2
      KIND_FUNCTION = 3
      KIND_VARIABLE = 6
      KIND_CLASS = 7

      # Lower sorts first. `sortText` is what the editor actually orders by
      # -- it will re-sort the array otherwise -- so the group index is
      # rendered into it rather than left implicit in the array order.
      GROUP_LOCAL = 0
      GROUP_SELF_METHOD = 1
      GROUP_CONSTANT = 2
      GROUP_KERNEL = 3

      Result = Data.define(:items, :incomplete)

      def initialize(query_service:, workspace_index:)
        @query_service = query_service
        @workspace_index = workspace_index
      end

      # `prefix` is what the user has typed so far, with no receiver in
      # front of it. An empty prefix returns nothing: there is no signal in
      # it, and answering with the workspace is the failure mode this class
      # exists to avoid.
      def items(document:, position:, prefix:)
        return Result.new(items: [], incomplete: false) if prefix.to_s.empty?

        scope = @query_service.scope_at(document, position)
        candidates = locals(scope, prefix) + self_methods(scope, prefix)
        candidates += constants(prefix) + kernel_methods(prefix) if prefix.length >= MIN_PREFIX_FOR_WORKSPACE

        ranked = candidates.sort_by { |item| [item[:__group], item[:label]] }
        # Incomplete for two different reasons. The cap is the obvious
        # one. The other is that below MIN_PREFIX_FOR_WORKSPACE the answer
        # *grows a new source* at the next keystroke, which no amount of
        # client-side filtering can produce -- so an editor told this
        # answer is complete caches it and filters locally, and a user
        # typing straight through from the first letter never sees a
        # workspace constant at all.
        Result.new(items: ranked.first(MAX_ITEMS).map { |item| finalize(item) },
                   incomplete: ranked.size > MAX_ITEMS || prefix.length < MIN_PREFIX_FOR_WORKSPACE)
      end

      private

      # `sortText` carries the group so the editor preserves this order;
      # `__group` is internal bookkeeping and must not reach the wire.
      def finalize(item)
        group = item.fetch(:__group)
        item.except(:__group).merge(sortText: format("%<group>d-%<label>s", group: group, label: item[:label]))
      end

      def matches?(name, prefix)
        name.to_s.downcase.start_with?(prefix.downcase)
      end

      def locals(scope, prefix)
        scope.locals.filter_map do |name, type|
          next unless matches?(name, prefix)

          { label: name, kind: KIND_VARIABLE, detail: type.to_s, __group: GROUP_LOCAL }
        end
      end

      # The same `members_of` the receiver path calls, with the receiver
      # taken from lexical scope instead of from before a dot.
      #
      # The nil guard is about *cost*, not correctness: `members_of`
      # already answers empty for a nil receiver, so removing it changes
      # no result -- it changes how much work every keystroke at a file's
      # top level does, on the request path, holding the index lock.
      # Pinned as such, by asserting the call is not made.
      def self_methods(scope, prefix)
        return [] unless scope.self_type

        @query_service.members_of(scope.self_type, prefix: prefix).map do |member|
          { label: member.name, kind: KIND_METHOD, detail: member.detail&.to_s, __group: GROUP_SELF_METHOD }
        end
      end

      # `WorkspaceIndex#prefix_search`, not `#search`. `search` answers
      # `workspace/symbol`'s question -- substring, every kind -- and
      # narrowing its answer afterwards narrows what survived *its*
      # truncation: on a workspace with more than `limit` substring
      # matches the prefix matches can all have been dropped already, and
      # this group came back empty. `search` also returns methods, which
      # were being offered here as `CompletionItemKind.Class` under a
      # group documented as constants.
      CONSTANT_KINDS = %i[class module constant].freeze

      def constants(prefix)
        seen = {}
        @workspace_index.prefix_search(prefix, limit: MAX_ITEMS * 4, kinds: CONSTANT_KINDS).each do |symbol_id|
          name = symbol_id.name.to_s.split("::").last
          seen[name] ||= { label: name, kind: KIND_CLASS, detail: symbol_id.name.to_s, __group: GROUP_CONSTANT }
        end
        seen.values
      end

      # So `pu` offers `puts`. Kernel is what a receiverless call falls
      # back to in Ruby, which makes it the last honest source rather than
      # an arbitrary one.
      def kernel_methods(prefix)
        @query_service.members_of(Types::Nominal.new(name: "Kernel"), prefix: prefix).map do |member|
          { label: member.name, kind: KIND_FUNCTION, detail: member.detail&.to_s, __group: GROUP_KERNEL }
        end
      end
    end
  end
end
