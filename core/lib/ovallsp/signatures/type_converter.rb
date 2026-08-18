# frozen_string_literal: true

require "rbs"
require_relative "../types"

module Ovallsp
  module Signatures
    # Converts `rbs` gem AST type objects into Ovallsp::Types values. RBS AST
    # objects are never stored anywhere long-lived themselves (Environment
    # converts on the way out of every query) — this is the one place that
    # translation happens (docs/design/tasks/012-rbs-rbi-and-external-signatures.md
    # "RBS AST objectを長寿命のWorkspaceIndexへ直接保存しない").
    #
    # Ovallsp::Types::Generic only models a single type argument
    # (docs/design/tasks/011-generic-types-and-block-inference.md), so a
    # two-argument container like `Hash[K, V]` necessarily loses its key
    # type here and keeps only the value type — the same simplification
    # Task 011's own generic model already accepts project-wide.
    module TypeConverter
      module_function

      def convert(rbs_type)
        case rbs_type
        when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface
          convert_class_type(rbs_type)
        when RBS::Types::Alias
          Types::Nominal.new(name: simple_name(rbs_type.name))
        when RBS::Types::Union
          Types.normalize_union(rbs_type.types.map { |t| convert(t) })
        when RBS::Types::Optional
          Types.normalize_union([convert(rbs_type.type), Types::NIL])
        when RBS::Types::Variable
          Types::TypeParameter.new(name: rbs_type.name.to_s)
        when RBS::Types::Proc
          convert_function(rbs_type.type)
        when RBS::Types::Tuple
          Types::Generic.new(name: "Array", type_arg: Types.normalize_union(rbs_type.types.map { |t| convert(t) }))
        when RBS::Types::Literal
          Types::Nominal.new(name: rbs_type.literal.class.name.split("::").last)
        when RBS::Types::Bases::Nil
          Types::NIL
        when RBS::Types::Bases::Bool
          Types::Nominal.new(name: "Boolean")
        when RBS::Types::Bases::Any, RBS::Types::Bases::Void, RBS::Types::Bases::Top, RBS::Types::Bases::Bottom,
             RBS::Types::Bases::Instance, RBS::Types::Bases::Class, RBS::Types::Bases::Self,
             RBS::Types::Record, nil
          Types::UNKNOWN
        else
          Types::UNKNOWN
        end
      rescue StandardError
        Types::UNKNOWN
      end

      def convert_class_type(rbs_type)
        name = simple_name(rbs_type.name)
        args = rbs_type.respond_to?(:args) ? rbs_type.args : []
        return Types::Nominal.new(name: name) if args.empty?

        # Hash[K, V]-shaped: keep the value type (last arg), matching
        # Generic's single-argument model; Array[T]/Set[T]-shaped: keep the
        # one arg they actually have.
        Types::Generic.new(name: name, type_arg: convert(args.last))
      end

      # Shared by `RBS::Types::Proc` (a `^(...) -> ...` type expression) and
      # `RBS::Types::Block` (a method's `{ ... }` parameter) -- both wrap an
      # `RBS::Types::Function` the same way.
      def convert_function(fn)
        Types::ProcType.new(parameters: positional_parameter_types(fn), return_type: convert(fn.return_type))
      end

      # RBS models `(?)` -- "takes anything" -- as `UntypedFunction`, which
      # carries a return type and *no* parameter lists at all. Asking it for
      # `required_positionals` raises, and the blanket rescue around
      # signature building turned that into "this method has no signature",
      # which the unknown-method check reads as "RBS does not declare it".
      # `send`, `__send__`, `public_send`, `instance_exec` and `Proc#call`
      # are all declared that way, so ordinary Ruby was reported as a
      # mistake on every closed receiver (0.1.12).
      #
      # No parameters is the honest answer for such a function: nothing is
      # declared about them, and an empty list is what every caller here
      # already means by "nothing known".
      def positional_parameter_types(fn)
        return [] unless fn.respond_to?(:required_positionals)

        fn.required_positionals.map { |p| convert(p.type) }
      end

      # RBS type names are fully-qualified with a leading `::`. This
      # strips that prefix and keeps the path: `::Foo::Bar` -> "Foo::Bar",
      # `::Array` -> "Array".
      #
      # It used to take the last path component instead, which threw the
      # namespace away and made every nested type answer under a bare
      # name. Measured against the loaded RBS environment: **240 of 334
      # types are nested**, and of their 238 distinct basenames **27 are
      # also defined as classes in the installed gem corpus** -- `Error`,
      # `Node`, `Generator`, `Buffer`, `Location` and the like. Where a
      # workspace defines one, it shadowed the core type: `File.stat(x)`
      # answered as a workspace `Stat`, listing its methods and denying
      # the real ones. That is the ordinary path, not the rare one 0.4
      # permits shipping as a known limitation.
      #
      # `Signatures::Environment#rbs_type_name` already parses a
      # `::`-qualified string, and resolution prefers an exact qualified
      # match before falling back to a last-segment one, so this adds
      # information rather than removing an answer.
      #
      # What changes for a reader: an aliased core type now shows its real
      # path -- `Mutex.new` says `Thread::Mutex`, which is what it is.
      def simple_name(type_name)
        Ovallsp::Index::SymbolId.bare_name(type_name.to_s)
      end
    end
  end
end
