# frozen_string_literal: true

require "json"

require_relative "../index/symbol_id"
require_relative "../types"

module Ovallsp
  module Plugins
    # The format a forked plugin's result crosses the process boundary in.
    #
    # `Loader` forks so that a broken or hostile plugin cannot take Core
    # down, and until 0.2.6 read the child's answer back with
    # `Marshal.load`. Those bytes are written by the plugin's own code,
    # and `Marshal.load` instantiates whatever classes the stream names,
    # **in the parent, before any of `Loader`'s validation runs** -- so an
    # ordinary deserialisation gadget crossed the boundary the fork exists
    # to create. `Server#partition_plugin_facts` validated afterwards,
    # which is too late to matter. `024.73`.
    #
    # A `Marshal.load` allowlist proc is not the fix: the proc runs after
    # each object has been constructed, which is after a gadget has fired.
    # The fix is that the boundary carries plain data -- JSON, so nothing
    # in the payload can name a class at all -- and the parent rebuilds
    # the typed values from fields it has checked. Validation now precedes
    # construction, which is the invariant that was wanted.
    #
    # Everything here is a closed list. An encoding this module does not
    # know is dropped rather than guessed at, and no encoded string ever
    # reaches `const_get` or `String#to_sym`: `kind` is matched against
    # the symbols this Core actually uses, so a payload naming `system` or
    # `Kernel` produces nothing rather than a symbol or a constant.
    module Wire
      # The `kind:` values `Index::SymbolId` is built with anywhere in
      # Core. A plugin registering anything else contributes nothing --
      # `StaticContext#register_declarations` only ever makes methods, and
      # the other kinds are here because `SymbolId` accepts them and a
      # narrower list would silently drop a legitimate future one.
      SYMBOL_KINDS = {
        "instance_method" => :instance_method,
        "singleton_method" => :singleton_method,
        "class" => :class,
        "module" => :module,
        "constant" => :constant
      }.freeze

      module_function

      # `{ok: true, result: …}` or `{ok: false, error: "…"}`, the two
      # shapes `Loader#run_isolated` produces.
      def encode_result(result)
        return { ok: false, error: result[:error].to_s } unless result[:ok]

        { ok: true, result: encode_payload(result[:result]) }
      end

      def decode_result(payload)
        return nil unless payload.is_a?(Hash)
        return { ok: false, error: payload[:error].to_s } if payload[:ok] == false

        return nil unless payload[:ok] == true && payload.key?(:result)

        decoded = decode_payload(payload[:result])
        decoded.nil? ? nil : { ok: true, result: decoded }
      end

      # Two payloads cross this boundary: a static plugin's declarations
      # (an array) and a runtime plugin's summary (a Hash of names and a
      # count). Nothing else does, so nothing else is representable.
      def encode_payload(payload)
        case payload
        when Array then { shape: "declarations", declarations: payload.map { |fact| encode_fact(fact) } }
        when Hash
          { shape: "summary",
            snapshot_section_names: Array(payload[:snapshot_section_names]).map(&:to_s),
            reload_hook_count: payload[:reload_hook_count].to_i }
        end
      end

      def decode_payload(payload)
        return nil unless payload.is_a?(Hash)

        case payload[:shape]
        when "declarations" then Array(payload[:declarations]).filter_map { |fact| decode_fact(fact) }
        when "summary"
          # Strings, not symbols: `RuntimeContext#register_snapshot_section`
          # already stores `name.to_s`, so a String is what the sender
          # actually produced and interning here would change it. It also
          # means no plugin-chosen text is ever interned, which is the
          # property worth having on this boundary.
          { snapshot_section_names: Array(payload[:snapshot_section_names]).map(&:to_s),
            reload_hook_count: payload[:reload_hook_count].to_i }
        end
      end

      def encode_fact(fact)
        symbol_id = fact[:symbol_id]
        { symbol_id: { kind: symbol_id.kind.to_s, owner: symbol_id.owner, name: symbol_id.name },
          return_type: encode_type(fact[:return_type]) }
      end

      def decode_fact(fact)
        return nil unless fact.is_a?(Hash)

        raw = fact[:symbol_id]
        return nil unless raw.is_a?(Hash)

        kind = SYMBOL_KINDS[raw[:kind].to_s]
        name = raw[:name]
        return nil unless kind && name.is_a?(String) && !name.empty?
        return nil unless raw[:owner].nil? || raw[:owner].is_a?(String)

        { symbol_id: Index::SymbolId.new(kind: kind, owner: raw[:owner], name: name, discriminator: nil),
          return_type: decode_type(fact[:return_type]) }
      end

      def encode_type(type)
        case type
        when nil then nil
        when Types::Unknown then { kind: "unknown" }
        when Types::NilType then { kind: "nil" }
        when Types::Nominal then { kind: "nominal", name: type.name }
        when Types::TypeParameter then { kind: "type_parameter", name: type.name }
        when Types::Generic then { kind: "generic", name: type.name, type_arg: encode_type(type.type_arg) }
        when Types::Union then { kind: "union", members: type.members.map { |m| encode_type(m) } }
        when Types::ProcType
          { kind: "proc", parameters: type.parameters.map { |p| encode_type(p) },
            return_type: encode_type(type.return_type) }
        end
      end

      def decode_type(encoded)
        return nil unless encoded.is_a?(Hash)

        case encoded[:kind]
        when "unknown" then Types::UNKNOWN
        when "nil" then Types::NIL
        when "nominal" then decode_named(encoded) { |name| Types::Nominal.new(name: name) }
        when "type_parameter" then decode_named(encoded) { |name| Types::TypeParameter.new(name: name) }
        when "generic" then decode_generic(encoded)
        when "union" then decode_union(encoded)
        when "proc" then decode_proc(encoded)
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
      # that invariant and `normalize_union` is what upholds it, so a
      # payload claiming otherwise is dropped rather than normalised into
      # something the sender did not send.
      def decode_union(encoded)
        members = Array(encoded[:members]).map { |member| decode_type(member) }
        return nil if members.size < 2 || members.any?(&:nil?)

        Types::Union.new(members: members)
      end

      def decode_proc(encoded)
        parameters = Array(encoded[:parameters]).map { |parameter| decode_type(parameter) }
        return nil if parameters.any?(&:nil?)

        return_type = decode_type(encoded[:return_type])
        return nil unless return_type

        Types::ProcType.new(parameters: parameters, return_type: return_type)
      end
    end
  end
end
