# frozen_string_literal: true

module Ovallsp
  module Semantic
    # Whether a receiver has a member, in three states rather than two.
    #
    # `MethodResolver#resolve` answers a list, and an empty list has meant
    # two different things since it was written: the method is not there,
    # or the receiver's members could not be enumerated at all. Its own
    # second line is `return [] if types.empty?` -- the second case,
    # spelled as the first.
    #
    # Every consumer then reconstructs the difference for itself.
    # `Diagnostics::Engine#closed_nominal?` keeps its own list of ways of
    # not knowing and subtracts them one at a time: 0.2.6 added four, one
    # per review round, each after a user-visible false report on working
    # code. Completion, hover and signature help reach the index by their
    # own routes and disagree at the same position -- `024.100`, plus six
    # more shapes 0.2.8's drive round measured.
    #
    # The rule that makes this worth a type: **`unknown` is produced by
    # whatever failed to enumerate, never inferred by a caller.** A new
    # way of not knowing then makes every reader silent by construction,
    # rather than by each reader being taught about it. That is the
    # difference between this and a boolean with better names.
    #
    # `037`'s C2. The two shapes this project has been rolled back for --
    # `024.15` (0.1.12: 47 files, four rounds, zero net progress) and
    # `024.47` (0.2.1: a rule centralised into resolution) -- are both
    # restructurings that moved no measurement. Each step of this one
    # carries a corpus measurement, and one that does not move it is one
    # to abandon rather than defend.
    MemberAvailability = Data.define(:state, :candidates, :reason) do
      def self.present(candidates)
        new(state: :present, candidates: candidates.freeze, reason: nil)
      end

      def self.absent
        new(state: :absent, candidates: [].freeze, reason: nil)
      end

      # `reason` is required, and the requirement is the point: an
      # unexplained unknown is the boolean this replaces, wearing a new
      # type. It is what a later reader needs in order to tell a receiver
      # nobody could identify from one whose class was reopened
      # elsewhere.
      def self.unknown(reason)
        raise ArgumentError, "an unknown availability must name its reason" if reason.nil?

        new(state: :unknown, candidates: [].freeze, reason: reason)
      end

      def initialize(**fields)
        super
        freeze
      end

      def present? = state == :present

      # The only predicate that admits absence. A check written against
      # it is silent on a receiver nobody could enumerate, whether or not
      # its author thought about that receiver -- which is the whole
      # arrangement, and the reason `#unknown?` is not its negation.
      def absent? = state == :absent

      def unknown? = state == :unknown
    end
  end
end
