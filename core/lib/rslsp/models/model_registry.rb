# frozen_string_literal: true

module Rslsp
  module Models
    Column = Data.define(:name, :ruby_type)
    Association = Data.define(:name, :macro, :class_name, :optional)
    ModelInfo = Data.define(:name, :table_name, :columns, :associations, :partial)

    # Standard DB-type -> Ruby-type mapping (docs/03-semantic-engine.md
    # section 7.3). Adapters/plugins can override this later; unmapped
    # column types widen to "Untyped" rather than guessing.
    COLUMN_TYPE_MAP = {
      "integer" => "Integer",
      "bigint" => "Integer",
      "float" => "Float",
      "decimal" => "BigDecimal",
      "boolean" => "Boolean",
      "string" => "String",
      "text" => "String",
      "datetime" => "Time",
      "date" => "Date",
      "json" => "Hash",
      "jsonb" => "Hash",
      "uuid" => "String"
    }.freeze

    # Holds per-model column/association facts fetched (lazily, one model
    # at a time) via agent/model, keyed by model name so LocalInferencer
    # can resolve `user.company`, `company.orders`, DB-column accessors,
    # and so on (docs/design/tasks/007-active-record-model-snapshot.md).
    class ModelRegistry
      def initialize
        @models = {}
      end

      # Builds a ModelInfo from an agent/model response's `:result` hash
      # and registers it. `name` is passed separately because an
      # NOT_FOUND/error response has no name to key off reliably.
      def register_from_agent_response(name, response)
        columns = (response[:columns] || []).map do |c|
          Column.new(name: c[:name].to_s, ruby_type: COLUMN_TYPE_MAP.fetch(c[:type].to_s, "Untyped"))
        end
        associations = (response[:associations] || []).map do |a|
          Association.new(
            name: a[:name].to_s, macro: a[:macro].to_sym, class_name: a[:className].to_s,
            optional: a[:optional] != false
          )
        end

        @models[name] = ModelInfo.new(
          name: name, table_name: response[:tableName], columns: columns, associations: associations,
          partial: response[:partial] == true
        )
      end

      def known_model?(name)
        @models.key?(name)
      end

      def model(name)
        @models[name]
      end

      def association(model_name, association_name)
        @models[model_name]&.associations&.find { |a| a.name == association_name.to_s }
      end

      def column(model_name, column_name)
        @models[model_name]&.columns&.find { |c| c.name == column_name.to_s }
      end
    end
  end
end
