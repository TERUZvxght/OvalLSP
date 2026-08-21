# frozen_string_literal: true

module Ovallsp
  module Index
    # One raw, per-occurrence ancestor-modifying statement found while
    # parsing a file — a superclass declaration or an `include`/`prepend`/
    # `extend` call. `owner` is the fully-qualified name of the class/module
    # the statement appears directly inside (computed the same way
    # Declaration#symbol_id.owner is). `target` is the referenced
    # constant's name *as written* in source — not qualified against
    # `owner`, since a superclass or included module is resolved via
    # normal Ruby constant lookup, not automatic nesting under the class
    # that references it. Semantic::HierarchyIndex resolves `target`
    # against the workspace when it aggregates these into ancestor chains
    # (docs/design/tasks/009-method-hierarchy-and-lookup.md).
    # `nesting` is `Module.nesting` at the point the constant was
    # written, innermost first -- the one thing needed to identify it and
    # the one thing this fact did not carry (`024.81`). Ruby's constant
    # lookup is lexical, so `include Helpers` inside
    # `Rackish::Request` means `Rackish::Request::Helpers` whatever other
    # namespace has a `Helpers`. Without it the index could only pick,
    # and picking put an unrelated module into the chain -- so it refused
    # instead, and a class whose ancestor name was claimed anywhere else
    # lost that module's members from completion, hover and go to
    # definition as well as from the check.
    #
    # Defaulted, so a caller that has no nesting to give -- a fact
    # reconstructed from a cache written before 0.2.12 -- gets exactly
    # the previous behaviour.
    AncestorFact = Data.define(:owner, :relation, :target, :location, :nesting) do
      def initialize(nesting: [], **rest)
        super(nesting: nesting, **rest)
      end
    end
  end
end
