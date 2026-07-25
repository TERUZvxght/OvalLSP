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
        params = fn.required_positionals.map { |p| convert(p.type) }
        Types::ProcType.new(parameters: params, return_type: convert(fn.return_type))
      end

      # RBS type names are fully-qualified with a leading "::" — the
      # internal type model (Nominal/Generic#name) uses bare simple names
      # (matching how Models::ModelRegistry and source Nominal types are
      # already named), so this strips the namespace down to the last
      # path component (`::Foo::Bar` -> "Bar", `::Array` -> "Array").
      def simple_name(type_name)
        type_name.name.to_s
      end
    end
  end
end
