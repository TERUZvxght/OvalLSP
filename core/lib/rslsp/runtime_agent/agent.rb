# frozen_string_literal: true

require_relative "../io/framed_reader"
require_relative "../io/framed_writer"

module Rslsp
  module RuntimeAgent
    # The Runtime Agent side of the RSLSP Agent Protocol v1
    # (docs/design/docs/05-protocol.md). Runs inside the target Rails app's
    # process (via `bin/rails runner`, or a plain `ruby` invocation against a
    # fixture environment for tests) and answers agent/hello, agent/status,
    # and agent/shutdown over the same Content-Length JSON-RPC framing the
    # Core Server's LSP transport uses. Task 006 adds route extraction;
    # Task 007 adds model discovery and per-model column/association
    # extraction via agent/model; Task 006's reload follow-up adds
    # agent/reload for routes. No plugins yet.
    class Agent
      PROTOCOL_VERSION = 1

      METHOD_NOT_FOUND = -32601
      INTERNAL_ERROR = -32603

      def initialize(input:, output:, logger:, root: Dir.pwd)
        @reader = Rslsp::IO::FramedReader.new(input)
        @writer = Rslsp::IO::FramedWriter.new(output)
        @logger = logger
        @root = root
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @generation = 0
      end

      # Returns the process exit code (always 0 — a clean agent/shutdown and
      # an EOF-on-stdin both count as a normal exit per docs/04-runtime-agent.md
      # section 11: "stdin EOFで即時shutdownする").
      def run
        loop do
          message = begin
            @reader.read_message
          rescue Rslsp::IO::FramedReader::EOF
            break
          end

          break if dispatch(message) == :exit
        end

        0
      end

      private

      def dispatch(message)
        method = message[:method]
        id = message[:id]

        case method
        when "agent/hello"
          respond(id, hello_result(message[:params]))
        when "agent/status"
          respond(id, status_result)
        when "agent/snapshot"
          respond(id, snapshot_result(message[:params]))
        when "agent/model"
          respond(id, model_result(message[:params]))
        when "agent/reload"
          respond(id, reload_result(message[:params]))
        when "agent/shutdown"
          respond(id, {})
          return :exit
        else
          respond_error(id, code: METHOD_NOT_FOUND, message: "Method not found: #{method}") if id
        end

        nil
      rescue StandardError => e
        @logger.call("error handling #{method.inspect}: #{e.class}: #{e.message}")
        respond_error(id, code: INTERNAL_ERROR, message: "internal error") if id
        nil
      end

      def hello_result(_params)
        {
          protocolVersion: PROTOCOL_VERSION,
          agentVersion: Rslsp::VERSION,
          root: rails_root,
          railsVersion: rails_defined? ? Rails.version.to_s : nil,
          rubyVersion: RUBY_VERSION,
          capabilities: {
            routes: routes_available?,
            activeRecord: active_record_available?,
            reload: reload_available?,
            runtimePlugins: false
          }
        }
      end

      def status_result
        {
          pid: Process.pid,
          uptimeSeconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
        }
      end

      # docs/design/docs/05-protocol.md's agent/snapshot: returns only the
      # requested sections, so a Core that only needs routes doesn't pay for
      # a full model dump. Task 006 implements "metadata" and "routes";
      # "models" arrives with Task 007.
      def snapshot_result(params)
        sections = (params && params[:sections]) || ["metadata"]
        result = {}
        result[:metadata] = metadata_section if sections.include?("metadata")
        result[:routes] = extract_routes if sections.include?("routes")
        result[:models] = discover_models if sections.include?("models")
        result
      end

      # Model *discovery* is intentionally lightweight (name/tableName
      # only) — Task 007's "lazy agent/model request" means columns and
      # associations for a given model are fetched on demand via agent/model,
      # not eagerly for every model on every snapshot.
      def discover_models
        return [] unless active_record_available?

        ::ActiveRecord::Base.descendants.reject(&:abstract_class?).filter_map do |klass|
          next nil unless klass.respond_to?(:name) && klass.name

          { name: klass.name, tableName: safely { klass.table_name } }
        end
      end

      # docs/design/docs/05-protocol.md's agent/model. Associations never
      # need a live DB connection in real ActiveRecord (they're pure Ruby
      # reflection), so they're always returned; columns do need one, so a
      # DB outage degrades to a partial result instead of failing the whole
      # request (docs/design/tasks/007-active-record-snapshot.md
      # "DB unavailable partial result").
      def model_result(params)
        name = params && params[:name].to_s
        klass = valid_model_class(name)
        return { name: name, error: { code: "NOT_FOUND", message: "no such model: #{name.inspect}" } } unless klass

        columns, partial = extract_columns(klass)

        {
          name: klass.name,
          tableName: safely { klass.table_name },
          columns: columns,
          associations: extract_associations(klass),
          partial: partial
        }
      end

      # "constantize前にconstant名を検証する" (docs/03-semantic-engine.md 7.1's
      # sibling section, docs/04-runtime-agent.md section 6): only a
      # syntactically valid, already-defined ActiveRecord model name is
      # resolved — never Object.const_get on arbitrary user input.
      def valid_model_class(name)
        return nil unless active_record_available?
        return nil unless name.is_a?(String) && name.match?(/\A[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*\z/)
        return nil unless Object.const_defined?(name, false)

        klass = Object.const_get(name, false)
        return nil unless klass.is_a?(Class) && klass < ::ActiveRecord::Base

        klass
      end

      def extract_columns(klass)
        columns = klass.columns.map { |c| { name: c.name.to_s, type: c.type.to_s, null: c.null != false } }
        [columns, false]
      rescue StandardError => e
        @logger.call("columns unavailable for #{klass.name}: #{e.class}: #{e.message}")
        [[], true]
      end

      def extract_associations(klass)
        klass.reflect_on_all_associations.map do |reflection|
          {
            name: reflection.name.to_s,
            macro: reflection.macro.to_s,
            className: reflection.class_name,
            optional: reflection.options[:optional] != false
          }
        end
      end

      def active_record_available?
        defined?(::ActiveRecord::Base) && ::ActiveRecord::Base.respond_to?(:descendants)
      end

      def safely
        yield
      rescue StandardError
        nil
      end

      def metadata_section
        {
          generation: @generation,
          railsVersion: rails_defined? ? Rails.version.to_s : nil,
          rubyVersion: RUBY_VERSION,
          root: rails_root
        }
      end

      # Reads only the duck-typed subset of ActionDispatch::Journey::Route's
      # real interface (name/verb/path.spec/defaults/required_parts), so this
      # works unchanged against a real Rails app once one is wired in and
      # against the rails_minimal fixture's fake router alike. Unnamed
      # routes produce no helper and are skipped, matching the fact that
      # Rails itself doesn't generate a `*_path` method for them.
      def extract_routes
        return [] unless routes_available?

        Rails.application.routes.routes.filter_map do |route|
          name = route.respond_to?(:name) ? route.name : nil
          next nil unless name

          {
            name: name.to_s,
            # Real Rails routes matching any verb (`match ... via: :all`)
            # report verb as "", not nil — treat both as "GET" for our
            # purposes rather than surfacing an empty string.
            verb: route.verb.to_s.empty? ? "GET" : route.verb.to_s,
            pathTemplate: route.path.spec.to_s,
            requiredParts: Array(route.required_parts).map(&:to_s),
            optionalParts: route.path.spec.to_s.include?("(.:format)") ? ["format"] : [],
            defaults: route.defaults.to_h { |k, v| [k.to_s.to_sym, v.to_s] },
            sourceLocation: route.respond_to?(:source_location) ? route.source_location : nil,
            routeSet: "main_app"
          }
        end
      end

      def routes_available?
        rails_defined? && Rails.respond_to?(:application) && Rails.application.respond_to?(:routes)
      end

      def reload_available?
        routes_available? && Rails.application.respond_to?(:reload_routes!)
      end

      # docs/design/docs/04-runtime-agent.md section 8. Only routes reload
      # so far — model/schema reload (section 9's other invalidation rules)
      # isn't implemented yet. On failure, generation does NOT advance, so
      # Core keeps treating the last-good snapshot as current
      # (docs/design/docs/04-runtime-agent.md: "reloadに失敗した場合:
      # generationを進めない").
      def reload_result(_params)
        unless reload_available?
          return { generation: @generation, changedSections: [], errors: [] }
        end

        begin
          Rails.application.reload_routes!
        rescue StandardError => e
          @logger.call("agent/reload failed: #{e.class}: #{e.message}")
          return {
            generation: @generation,
            changedSections: [],
            errors: [{ code: "RELOAD_FAILED", message: e.message, recoverable: true }]
          }
        end

        @generation += 1
        { generation: @generation, changedSections: ["routes"], errors: [] }
      end

      def rails_defined?
        defined?(Rails) && Rails.respond_to?(:version)
      end

      def rails_root
        return Rails.root.to_s if rails_defined? && Rails.respond_to?(:root) && Rails.root

        @root
      end

      def respond(id, result)
        @writer.write_message(jsonrpc: "2.0", id: id, result: result)
      end

      def respond_error(id, code:, message:)
        @writer.write_message(jsonrpc: "2.0", id: id, error: { code: code, message: message })
      end
    end
  end
end
