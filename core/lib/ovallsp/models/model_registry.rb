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
    # thread may already be reading it (LocalInferencer). A mutex publishes
    # each payload together with its generation, so reference rebuilds can
    # never observe new model data under an old generation.
    class ModelRegistry
      def initialize
        @models = {}
        @active_record_api = { instance: [], singleton: [] }
        @generation = 0
        @mutex = Mutex.new
      end

      def generation = @mutex.synchronize { @generation }

      # Active Record's own API, as reported by the Runtime Agent from the
      # really-loaded classes. Shared by every model, so it is stored once
      # rather than copied into each ModelInfo.
      #
      # Installed only when the Agent actually reports it: a failed or
      # absent report must leave the last known API in place rather than
      # blanking it, exactly as a failed model fetch leaves the last
      # known-good models alone.
      def install_active_record_api(api)
        return if api.nil?

        instance = Array(api[:instance] || api["instance"]).map(&:to_s)
        singleton = Array(api[:singleton] || api["singleton"]).map(&:to_s)
        return if instance.empty? && singleton.empty?

        @mutex.synchronize do
          @active_record_api = { instance: instance, singleton: singleton }
          @generation += 1
        end
      end

      def active_record_api = @mutex.synchronize { @active_record_api }

      # Builds a ModelInfo from an agent/model response's `:result` hash
      # and registers (or overwrites) it in place. `name` is passed
      # separately because a NOT_FOUND/error response has no name to key
      # off reliably. Used for a single live model refresh (Server#refresh_models);
      # #replace is the full-generation counterpart used at bootstrap.
      def register_from_agent_response(name, response)
        info = prepare_replace(name => response).fetch(name)
        @mutex.synchronize do
          @models[name] = info
          @generation += 1
        end
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
        commit_replace(prepare_replace(responses_by_name))
      end

      # Conversion is deliberately separated from publication. Callers
      # coordinating models with routes/cache state can validate every
      # Agent payload first, then commit only after the whole snapshot is
      # known to be usable.
      def prepare_replace(responses_by_name)
        responses_by_name.to_h { |name, response| [name, build_model_info(name, response)] }
      end

      def commit_replace(replacement)
        @mutex.synchronize do
          @models = replacement.dup
          @generation += 1
        end
      end

      # Atomically applies a partial refresh. `prepared` must come from
      # #prepare_replace, so malformed payloads fail before this method
      # can publish any member of the batch.
      def commit_updates(prepared, removals: [])
        @mutex.synchronize do
          replacement = @models.dup
          removals.each { |name| replacement.delete(name) }
          prepared.each { |name, info| replacement[name] = info }
          @models = replacement
          @generation += 1
        end
      end

      # Drops one model entirely -- used when the Agent reports NOT_FOUND
      # for a model whose file changed (most often: deleted), so it stops
      # being resolvable for completion/definition/type inference instead
      # of lingering with its last-known columns/associations.
      def remove(name)
        @mutex.synchronize do
          removed = @models.delete(name)
          @generation += 1 if removed
          removed
        end
      end

      def known_model?(name)
        @mutex.synchronize { @models.key?(name) }
      end

      def model(name)
        @mutex.synchronize { @models[name] }
      end

      def association(model_name, association_name)
        @mutex.synchronize { @models[model_name]&.associations&.find { |a| a.name == association_name.to_s } }
      end

      def column(model_name, column_name)
        @mutex.synchronize { @models[model_name]&.columns&.find { |c| c.name == column_name.to_s } }
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
