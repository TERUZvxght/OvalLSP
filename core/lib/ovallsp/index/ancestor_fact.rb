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
    AncestorFact = Data.define(:owner, :relation, :target, :location)
  end
end
