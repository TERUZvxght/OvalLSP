# frozen_string_literal: true

require_relative "../types"

module Rslsp
  module Observation
    # Turns one observed Ruby *value* into a Types shape -- never keeps
    # the value itself, never calls #inspect/#to_s on it, only ever reads
    # `.class`/`.name` ("保存禁止: 実値, 文字列内容" --
    # docs/design/tasks/019-runtime-observation.md). The only method this
    # module ever calls on the observed value is `#nil?`, `#is_a?`, and
    # (for a Class/Module value itself) `#name` -- reading a name off a
    # constant is not the same as reading application data.
    module TypeNormalizer
      module_function

      # `value.class.name` is nil for both an anonymous Class/Module and
      # any instance of one (`Class.new.new.class.name` => nil) --
      # "anonymous classやsingleton classは安全に正規化する" means never
      # crash and never fabricate a fake name for these, so both widen to
      # Types::UNKNOWN: there is no stable, source-linkable identity to
      # report.
      #
      # A Class/Module *value itself* (e.g. an argument like `Widget`, or
      # `self` inside a `def self.foo` singleton method) doesn't normalize
      # via its own `.class` (always plain `Class`, useless) -- it
      # normalizes to `Generic("ClassOf", Nominal(name))`, the same shape
      # this codebase's own LocalInferencer already uses for singleton
      # method receivers (see `locate_in_singleton_class`), so observed
      # evidence and statically-inferred types compare on equal footing.
      def normalize(value)
        return Types::NIL if value.nil?
        return normalize_module(value) if value.is_a?(Module)

        name = value.class.name
        return Types::UNKNOWN if name.nil?

        Types::Nominal.new(name: name)
      end

      def normalize_module(mod)
        name = mod.name
        return Types::UNKNOWN if name.nil?

        Types::Generic.new(name: "ClassOf", type_arg: Types::Nominal.new(name: name))
      end
    end
  end
end
