# frozen_string_literal: true

require_relative "../types"

module Ovallsp
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

        as_nominal_name(value.class.name)
      end

      def normalize_module(mod)
        name = as_nominal_name(mod.name)
        return Types::UNKNOWN if name == Types::UNKNOWN

        Types.class_object(name)
      end

      # `#name` is one of the handful of methods this module calls
      # directly on an observed value (or its `.class`) -- an ordinary
      # object can't make that return anything but `nil` or a String, but
      # an adversarial one (a proxy/delegator with `#class`/`#name`
      # overridden) could return anything at all. Found by an independent
      # review of Task 019: an earlier version trusted whatever came back
      # verbatim, which could have put a non-String into
      # `Types::Nominal#name` -- and since `Nominal#to_s` (types.rb)
      # returns `name` as-is rather than `name.to_s`, that non-String
      # value would have flowed unchanged all the way out to
      # `ovallsp/showTypeEvidence`'s JSON response. Only ever runs inside
      # the already-fully-untrusted isolated observation runner process
      # (never Core's own), so this is a data-integrity fix, not a
      # privilege boundary -- an adversarial value here could already run
      # arbitrary code in that same process via the workspace's own test
      # suite.
      def as_nominal_name(name)
        return Types::UNKNOWN unless name.is_a?(String)

        Types::Nominal.new(name: name)
      end
    end
  end
end
