# frozen_string_literal: true

module Ovallsp
  module Observation
    # One method's aggregated observation, from a single opt-in run
    # (docs/design/tasks/019-runtime-observation.md). Never stores an
    # actual argument/return *value* — only the Types shape TypeNormalizer
    # derived from it, aggregated across every call this run observed.
    #
    # - symbol_id: the observed method's Index::SymbolId
    # - parameter_types: ordered array of Types values, one per positional
    #   parameter slot, each the union of every class actually observed at
    #   that slot this run
    # - return_type: the union of every class the method actually returned
    #   this run (Types::UNKNOWN if every call this run raised instead of
    #   returning -- see Store's authority policy: this is never treated
    #   as a confirmed "returns nothing")
    # - samples: how many calls contributed to this aggregate
    # - run_id: identifies which observation run produced this (Store
    #   replaces a run wholesale rather than merging across runs -- see
    #   Store#replace_run)
    # - code_fingerprint: a digest of the whole *file* the observed method
    #   is defined in, plus that method's line number
    #   (Fingerprint.for_file_and_line) -- not a digest of the method body.
    #   Any change anywhere in the file changes it, which is what makes it
    #   a conservative "may have changed since this was observed" signal
    #   (Store#invalidate_changed). Described as a `body_source` digest
    #   until 0.1.12; it never was one.
    # - created_at: wall-clock Time the run finished
    ObservedSignature = Data.define(
      :symbol_id, :parameter_types, :return_type, :samples, :run_id, :code_fingerprint, :created_at
    )
  end
end
