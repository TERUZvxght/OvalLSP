# frozen_string_literal: true

module Rslsp
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
    # - code_fingerprint: the observed method's own Declaration#body_source
    #   digest at observation time, used to detect "source changed since
    #   this was observed" (Store#invalidate_changed)
    # - created_at: wall-clock Time the run finished
    ObservedSignature = Data.define(
      :symbol_id, :parameter_types, :return_type, :samples, :run_id, :code_fingerprint, :created_at
    )
  end
end
