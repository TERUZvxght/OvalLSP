# frozen_string_literal: true

module Ovallsp
  module Index
    # A single method parameter, as declared (no type inference here — that
    # arrives with the type engine in a later task).
    #
    # kind: :required, :optional, :rest, :keyword, :keyword_optional, :keyrest, :block
    Parameter = Data.define(:name, :kind, :default_source) do
      # How the source spells this parameter, which is what signature help
      # and hover show while the reader is typing arguments into the call.
      #
      # Both of those used to render `parameters.map(&:name)`, so
      # `def simple(a, b = 2, *rest, key:, opt: 1, **others, &blk)`
      # presented as `simple(a, b, rest, key, opt, others, blk)` — telling
      # the reader `key` is the fourth positional argument when it is a
      # required keyword (`024.89`). Every kind and both defaults were
      # recorded the whole time; only the rendering dropped them.
      #
      # The kinds are Ruby's, one for one:
      #
      #   $ ruby -e 'def simple(a, b = 2, *rest, key:, opt: 1, **others, &blk); end
      #              p method(:simple).parameters'
      #   # => [[:req, :a], [:opt, :b], [:rest, :rest], [:keyreq, :key],
      #   #     [:key, :opt], [:keyrest, :others], [:block, :blk]]
      #   # ruby 3.4.10
      #
      # This lives on the value rather than in either reader because two
      # of them need it and a third (`#completion_snippet`) deliberately
      # does not — a snippet's tab stops want the bare name. One method
      # they call, rather than a rule each spells out.
      #
      # Deliberately *not* shared with `QueryService#rbs_signature_parts`:
      # that renders RBS **types** (`?Integer`, `name:`) and this renders
      # source **names and defaults**. Two different renderings of two
      # different things, and merging them because they look alike is the
      # move `024.47` had to roll back.
      def label
        spelled = name.to_s
        case kind
        # `... ` rather than a made-up value: the parameter really is
        # optional and its default really is unreadable, which is what a
        # buffer mid-edit looks like. The same marker `#rbs_signature_parts`
        # uses for "accepts more than it names".
        when :optional then default_source ? "#{spelled} = #{default_source}" : "#{spelled} = ..."
        when :rest then "*#{spelled}"
        when :keyword then "#{spelled}:"
        when :keyword_optional then default_source ? "#{spelled}: #{default_source}" : "#{spelled}:"
        when :keyrest then "**#{spelled}"
        when :block then "&#{spelled}"
        else spelled
        end
      end
    end
  end
end
