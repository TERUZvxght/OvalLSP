# frozen_string_literal: true

require "json"

require_relative "observed_signature"
require_relative "../index/symbol_id"
require_relative "../types"

module Ovallsp
  module Observation
    # The format an observation run's results cross the process boundary in.
    #
    # `Runner` spawns the workspace's own test command as a genuinely
    # separate OS process, and until 0.2.16 read its answer back with
    # `Marshal.load`. `Marshal.load` instantiates whatever classes the
    # stream names, **before** any of `#read_results`' validation runs:
    # driven against a payload holding one object with a `marshal_load`
    # hook, `#read_results` answered `nil` -- its shape check did its job
    # -- with the hook already having run inside Core's process. That is
    # `024.73`'s defect on the channel that entry did not cover, recorded
    # as `024.135`.
    #
    # So the payload is JSON: nothing in it can name a class at all, and
    # Core validates fields and only then builds the typed values, so
    # validation precedes construction rather than following it.
    #
    # Everything here is a closed list, and each list is what this channel
    # actually carries rather than what `Types` or `SymbolId` can express:
    #
    # - `Collector#defined_method` builds only the two method kinds, so
    #   `constant` or `class` on the wire is a payload Core did not write.
    # - `TypeNormalizer` answers `NIL`, `UNKNOWN`, a `Nominal`, or
    #   `Generic("ClassOf", …)`, and `Collector#results` unions those. A
    #   `TypeParameter` never survives resolution and a `ProcType` is
    #   structural -- an observed Proc normalises to `Nominal("Proc")` --
    #   so neither can arrive from a run this Core observed.
    #
    # A malformed entry rejects the **whole** payload rather than being
    # dropped from it. `Store#replace_run` is a full generation swap, so a
    # partially decoded run would install itself as "everything the suite
    # observed"; `Runner#read_results` turns a rejection into its own
    # `nil` -- no outcome -- which leaves what the user already had.
    module Wire
      SHAPE = "observations"

      # The `kind:` values `Collector` records. See the class note above
      # for why this is narrower than `SymbolId`'s own set.
      SYMBOL_KINDS = { "instance_method" => :instance_method, "singleton_method" => :singleton_method }.freeze

      module_function

      def encode(results)
        { shape: SHAPE, signatures: results.map { |signature| encode_signature(signature) } }
      end

      # `nil` for anything this module did not write; `[]` only for a run
      # that genuinely observed nothing.
      def decode(payload)
        return nil unless payload.is_a?(Hash) && payload[:shape] == SHAPE
        return nil unless payload[:signatures].is_a?(Array)

        decoded = payload[:signatures].map { |entry| decode_signature(entry) }
        decoded.any?(&:nil?) ? nil : decoded
      end

      def encode_signature(signature)
        { symbol_id: encode_symbol_id(signature.symbol_id),
          parameter_types: signature.parameter_types.map { |type| encode_type(type) },
          return_type: encode_type(signature.return_type),
          samples: signature.samples,
          run_id: signature.run_id,
          code_fingerprint: signature.code_fingerprint,
          # A number, not a formatted string: nothing reads this value
          # yet, and it is the one representation that cannot depend on
          # two processes agreeing about a zone or a locale.
          created_at: signature.created_at.to_f }
      end

      def decode_signature(entry)
        return nil unless entry.is_a?(Hash)

        symbol_id = decode_symbol_id(entry[:symbol_id])
        parameter_types = decode_types(entry[:parameter_types])
        return_type = decode_type(entry[:return_type])
        return nil if symbol_id.nil? || parameter_types.nil? || return_type.nil?
        return nil unless plain_fields?(entry)

        ObservedSignature.new(
          symbol_id: symbol_id, parameter_types: parameter_types, return_type: return_type,
          samples: entry[:samples], run_id: entry[:run_id], code_fingerprint: entry[:code_fingerprint],
          created_at: Time.at(entry[:created_at])
        )
      end

      # `code_fingerprint` is genuinely optional --
      # `Fingerprint.for_file_and_line` answers nil for a file it could
      # not read -- and nothing else here is.
      def plain_fields?(entry)
        entry[:samples].is_a?(Integer) && entry[:run_id].is_a?(String) &&
          (entry[:code_fingerprint].nil? || entry[:code_fingerprint].is_a?(String)) &&
          entry[:created_at].is_a?(Numeric)
      end

      # `discriminator` is written by neither side: `SymbolId` documents it
      # as reserved and nothing produces one, so a payload cannot put a
      # value in a field no reader understands.
      def encode_symbol_id(symbol_id)
        { kind: symbol_id.kind.to_s, owner: symbol_id.owner, name: symbol_id.name }
      end

      def decode_symbol_id(raw)
        return nil unless raw.is_a?(Hash)

        kind = SYMBOL_KINDS[raw[:kind].to_s]
        name = raw[:name]
        return nil unless kind && name.is_a?(String) && !name.empty?
        return nil unless raw[:owner].is_a?(String) && !raw[:owner].empty?

        Index::SymbolId.new(kind: kind, owner: raw[:owner], name: name, discriminator: nil)
      end

      def encode_type(type)
        case type
        when Types::Unknown then { kind: "unknown" }
        when Types::NilType then { kind: "nil" }
        when Types::Nominal then { kind: "nominal", name: type.name }
        when Types::Generic then { kind: "generic", name: type.name, type_arg: encode_type(type.type_arg) }
        when Types::Union then { kind: "union", members: type.members.map { |member| encode_type(member) } }
        end
      end

      def decode_type(encoded)
        return nil unless encoded.is_a?(Hash)

        case encoded[:kind]
        when "unknown" then Types::UNKNOWN
        when "nil" then Types::NIL
        when "nominal" then decode_named(encoded) { |name| Types::Nominal.new(name: name) }
        when "generic" then decode_generic(encoded)
        when "union" then decode_union(encoded)
        end
      end

      def decode_named(encoded)
        name = encoded[:name]
        yield(name) if name.is_a?(String) && !name.empty?
      end

      def decode_generic(encoded)
        type_arg = decode_type(encoded[:type_arg])
        return nil unless type_arg

        decode_named(encoded) { |name| Types::Generic.new(name: name, type_arg: type_arg) }
      end

      # A Union of fewer than two members is not one -- `Types` documents
      # that invariant and `normalize_union` upholds it -- so a payload
      # claiming otherwise is dropped rather than normalised into
      # something the sender did not send.
      def decode_union(encoded)
        members = Array(encoded[:members]).map { |member| decode_type(member) }
        return nil if members.size < 2 || members.any?(&:nil?)

        Types::Union.new(members: members)
      end

      def decode_types(raw)
        return nil unless raw.is_a?(Array)

        decoded = raw.map { |type| decode_type(type) }
        decoded.any?(&:nil?) ? nil : decoded
      end
    end
  end
end
