# frozen_string_literal: true

module Rslsp
  # MVP subset of the type lattice in docs/design/docs/03-semantic-engine.md
  # section 2.4. Method body summaries, RBS, blocks, and generics are out of
  # scope for Task 004, so only what local inference actually needs exists
  # here: Unknown (no information yet), nil, a Nominal class reference, and
  # Union for branch merges.
  module Types
    # No information is available yet; more evidence could still narrow it.
    # Distinct from a resolved-but-unrepresentable type (which this
    # implementation doesn't need yet, so it isn't modeled).
    class Unknown
      def to_s
        "Unknown"
      end
    end
    UNKNOWN = Unknown.new.freeze

    class NilType
      def to_s
        "nil"
      end
    end
    NIL = NilType.new.freeze

    # A concrete class/module reference, e.g. Nominal("User"). Generic
    # arguments (Relation[T], Array[T]) are out of scope until Rails/generic
    # support lands.
    Nominal = Data.define(:name) do
      def to_s
        name
      end
    end

    # A normalized set of >= 2 distinct member types. Never nests another
    # Union — use Types.normalize_union to build one safely.
    Union = Data.define(:members) do
      def to_s
        members.map(&:to_s).join(" | ")
      end
    end

    module_function

    # Flattens nested unions, removes duplicate members (structural
    # equality — Nominal/Union are Data classes), and unwraps to a bare
    # type when only one distinct member remains. Member order is
    # normalized so equivalent unions compare equal regardless of the
    # order branches were visited in.
    def normalize_union(types)
      flattened = types.flat_map { |t| t.is_a?(Union) ? t.members : [t] }
      unique = flattened.uniq.sort_by { |t| t.to_s }

      case unique.size
      when 0 then UNKNOWN
      when 1 then unique.first
      else Union.new(members: unique.freeze)
      end
    end

    # Removes a `nil` member from a (possibly union) type, e.g. after a
    # truthiness guard. A type that was exactly `nil` widens to Unknown,
    # since asserting truthiness of something statically known to be nil
    # only would indicate dead code, not a real narrower type.
    def remove_nil(type)
      case type
      when NilType then UNKNOWN
      when Union then normalize_union(type.members.reject { |m| m == NIL })
      else type
      end
    end
  end
end
