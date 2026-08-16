# frozen_string_literal: true

require_relative "symbol_id"

module Ovallsp
  module Index
    # Recognising the one case where the index's answer is worse than no
    # answer, for the one reader that can act on it.
    #
    # `WorkspaceIndex#resolve_type_name` matches on the *last segment*, and
    # should: for completion and go-to-definition a plausible class beats
    # none, and a name written without its namespace is the ordinary way
    # Ruby is read. The exception is a bare name that signatures already
    # declare. A workspace `Serializer::Elements::String` then stands in
    # for the `String` a literal produced, and every reader downstream
    # inherits it: completion after `title.` offers `emit` and omits every
    # String method, and hover says `String` throughout.
    #
    # A module function rather than a method on either collaborator: the
    # rule needs the workspace index *and* the signature environment, and
    # neither owns the other.
    #
    # **Only the diagnostics engine applies it, and that is deliberate.**
    # 0.2.1 tried the other arrangement -- refusing the substitution in
    # resolution itself, so that every reader would get one answer -- and
    # it broke a bare name the user *wrote*: `Range.new` inside `module
    # Billing` is how Ruby refers to a class from its own namespace, and
    # hover, definition and completion all stopped answering it. The two
    # cases are told apart by whether the name was written or inferred,
    # which resolution is not given. So the refusal lives where declining
    # is safe -- a diagnostic -- and 024.47 holds what a real fix needs.
    # A `canonical` wrapper for the resolution-side arrangement was left
    # behind unreferenced by that rollback and is gone with it; wiring one
    # back in is the regression, not the fix.
    module TypeNameResolution
      module_function

      # Whether resolving `name` to `resolved` swapped in a differently
      # namespaced class for a name signatures already declare.
      #
      # Only for a *bare* name. A receiver written or inferred as
      # `Foo::Logger` carries its namespace and is nobody else's answer;
      # what has no namespace to check is a type that came from a literal
      # or from inference, which is exactly the population this protects.
      #
      # A workspace that genuinely reopens `String` at the top level
      # resolves to `::String` -- the same name, not a substitution, and
      # that shape is 024.13's question rather than this one.
      def substitution?(name, resolved, signatures)
        return false unless signatures && resolved

        bare = SymbolId.bare_name(name.to_s)
        return false if bare.include?("::")
        return false if SymbolId.bare_name(resolved) == bare

        declared_by_signatures?(bare, signatures)
      end

      def declared_by_signatures?(name, signatures)
        !signatures.ancestors(SymbolId.qualify_owner(name)).empty?
      rescue StandardError
        false
      end
    end
  end
end
