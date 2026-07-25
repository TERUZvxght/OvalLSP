# frozen_string_literal: true

module Ovallsp
  module Models
    # `nullable` mirrors the Agent's raw `null` column flag as-is (Task
    # 008.5) so it survives into the type model even though nothing
    # widens `ruby_type` to a nil-union yet -- that's LocalInferencer's
    # call to make (currently: `String | nil` for a nullable column,
    # docs/design/tasks/008.5-runtime-and-index-corrections.md), not a
    # reason to drop the information here.
    Column = Data.define(:name, :ruby_type, :nullable)
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
    # and so on (docs/design/tasks/007-active-record-snapshot.md).
    # Populated from a background thread (RailsBootstrap) while the main
    # thread may already be reading it (LocalInferencer). No mutex: each
    # #register_from_agent_response call is a single Hash#[]= on `@models`,
    # which is atomic under CRuby's GVL — a concurrent reader sees either
    # the old or the new value, never a torn write. This relies on CRuby's
    # GVL specifically; a JRuby/TruffleRuby port would need real locking
    # here (unlike WorkspaceIndex, which already uses a Mutex throughout).
    class ModelRegistry
      def initialize
        @models = {}
      end

      # Builds a ModelInfo from an agent/model response's `:result` hash
      # and registers (or overwrites) it in place. `name` is passed
      # separately because a NOT_FOUND/error response has no name to key
      # off reliably. Used for a single live model refresh (Server#refresh_models);
      # #replace is the full-generation counterpart used at bootstrap.
      def register_from_agent_response(name, response)
        @models[name] = build_model_info(name, response)
      end

      # Full swap from a generation's worth of agent/model responses,
      # keyed by model name -- a model this generation doesn't include
      # (renamed, deleted, no longer eager-loadable) disappears entirely,
      # the same generation-replace semantics RouteRegistry#replace
      # already gives routes (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      # Deliberately not a per-model merge: a stale entry from a previous
      # generation must never survive just because this generation didn't
      # happen to re-mention it.
      def replace(responses_by_name)
        @models = responses_by_name.to_h { |name, response| [name, build_model_info(name, response)] }
      end

      # Drops one model entirely -- used when the Agent reports NOT_FOUND
      # for a model whose file changed (most often: deleted), so it stops
      # being resolvable for completion/definition/type inference instead
      # of lingering with its last-known columns/associations.
      def remove(name)
        @models.delete(name)
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

      private

      def build_model_info(name, response)
        columns = (response[:columns] || []).map do |c|
          Column.new(
            name: c[:name].to_s, ruby_type: COLUMN_TYPE_MAP.fetch(c[:type].to_s, "Untyped"),
            nullable: c[:null] != false
          )
        end
        associations = (response[:associations] || []).map do |a|
          Association.new(
            name: a[:name].to_s, macro: a[:macro].to_sym, class_name: a[:className].to_s,
            optional: a[:optional] != false
          )
        end

        ModelInfo.new(
          name: name, table_name: response[:tableName], columns: columns, associations: associations,
          partial: response[:partial] == true
        )
      end
    end
  end
end
