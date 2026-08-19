# frozen_string_literal: true

require_relative "symbol_id"

module Ovallsp
  module Index
    # Recognising the one case where the index's answer for a type name
    # is worse than no answer: a *bare* name that signatures already
    # declare, answered by a workspace class that merely shares its last
    # segment. A workspace `Serializer::Elements::String` then stands in
    # for the `String` a literal produced, and 0.2.0 reported
    # `"hello".upcase` as an unknown method on the strength of it.
    #
    # One reader applies the rule: the diagnostics engine
    # (`Diagnostics::Engine#shadowed_declared_type?`), which declines to
    # *report* about such a receiver -- a diagnostic about a receiver the
    # engine has not identified is an assertion, not a missing answer.
    # Resolution itself (`Semantic::HierarchyIndex#canonical_name`)
    # deliberately does not refuse: 0.2.1 briefly applied the rule there
    # so that completion would agree with the diagnostic, and that broke
    # every bare name a user *wrote* from inside its own namespace --
    # `Range.new` inside `module Billing` stopped resolving anywhere.
    # The substitution test cannot tell a written name from an inferred
    # one, so it was rolled back to the engine; 024.47 records the design
    # question that remains, and what each attempted placement cost.
    #
    # A module function rather than a method on either collaborator: the
    # rule needs the workspace index's answer *and* the signature
    # environment, and neither owns the other.
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

      # No `rescue` here, and none in `MethodResolver#accounted_for?`
      # either: `Signatures::Environment#ancestors` answers `[]` for a
      # name it cannot parse or does not know, so a blanket rescue at each
      # caller could only ever hide a *different* failure -- and there
      # were two of them, agreeing about a containment that already lived
      # where the failure happens. `environment_spec` pins that answer.
      def declared_by_signatures?(name, signatures)
        !signatures.ancestors(SymbolId.qualify_owner(name)).empty?
      end
    end
  end
end
