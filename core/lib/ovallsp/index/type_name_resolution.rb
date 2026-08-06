# frozen_string_literal: true

require_relative "symbol_id"

module Ovallsp
  module Index
    # Turning a written type name into the declaration it means, and the
    # one case where the index's answer is worse than no answer.
    #
    # `WorkspaceIndex#resolve_type_name` matches on the *last segment*, and
    # should: for completion and go-to-definition a plausible class beats
    # none, and a name written without its namespace is the ordinary way
    # Ruby is read. The exception is a bare name that signatures already
    # declare. A workspace `Serializer::Elements::String` then stands in
    # for the `String` a literal produced, and every reader downstream
    # inherits it: `"hello".upcase` was reported as an unknown method,
    # completion after `title.` offered `emit` and omitted every String
    # method, and hover said `String` throughout -- three answers to one
    # question.
    #
    # A module function rather than a method on either collaborator: the
    # rule needs the workspace index *and* the signature environment, and
    # neither owns the other. 0.2.1 first put it inside the diagnostics
    # engine, which silenced the diagnostic and left completion wrong --
    # the rule belongs where the name is resolved, so that every reader
    # gets one answer.
    module TypeNameResolution
      module_function

      # The declared name `name` resolves to, or `name` itself when the
      # index has no answer or its answer would be a substitution.
      def canonical(name, workspace_index:, signatures: nil)
        resolved = workspace_index.resolve_type_name(name)
        return name.to_s if resolved.nil? || substitution?(name, resolved, signatures)

        resolved
      end

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
