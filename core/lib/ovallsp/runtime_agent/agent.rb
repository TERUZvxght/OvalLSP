# frozen_string_literal: true

require_relative "../io/framed_reader"
require_relative "../io/framed_writer"

module Ovallsp
  module RuntimeAgent
    # The Runtime Agent side of the OvalLSP Agent Protocol v1
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
        @reader = Ovallsp::IO::FramedReader.new(input)
        @writer = Ovallsp::IO::FramedWriter.new(output)
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
          rescue Ovallsp::IO::FramedReader::EOF
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
        when "agent/models"
          respond(id, models_result)
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
          agentVersion: Ovallsp::VERSION,
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
      #
      # `::ActiveRecord::Base.descendants` only reflects classes Ruby has
      # already autoloaded, which in Rails' default (non-eager-load)
      # development mode is often just whatever the app happened to touch
      # since boot -- a model nobody has referenced yet (e.g. a controller
      # behind a view that was never opened) would silently be missing.
      # #eager_load_models! loads every autoload path first so discovery
      # sees the app's full model set, not just an accident of boot order
      # (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      def discover_models
        return [] unless active_record_available?

        eager_load_models!

        ::ActiveRecord::Base.descendants.reject(&:abstract_class?).filter_map do |klass|
          next nil unless klass.respond_to?(:name) && klass.name

          { name: klass.name, tableName: safely { klass.table_name } }
        end
      end

      # Zeitwerk (Rails >= 6 default) exposes `Rails.autoloaders.main`;
      # `Rails.application.eager_load!` is the version-spanning fallback
      # for the classic autoloader and for any additional autoload paths
      # Zeitwerk's main loader doesn't own. Never lets a broken model file
      # (a real syntax/load error somewhere under an autoload path) take
      # the whole Agent down with it -- discovery/model-fetch just falls
      # back to whatever was already loaded, same as any other
      # ActiveRecord failure this Agent degrades around.
      def eager_load_models!
        return unless rails_defined?

        if Rails.respond_to?(:autoloaders) && Rails.autoloaders.respond_to?(:main) && Rails.autoloaders.main
          Rails.autoloaders.main.eager_load
        elsif Rails.respond_to?(:application) && Rails.application.respond_to?(:eager_load!)
          Rails.application.eager_load!
        end
      rescue StandardError => e
        @logger.call("model eager load failed: #{e.class}: #{e.message}")
      end

      # docs/design/docs/05-protocol.md's agent/model. Associations never
      # need a live DB connection in real ActiveRecord (they're pure Ruby
      # reflection), so they're always returned; columns do need one, so a
      # DB outage degrades to a partial result instead of failing the whole
      # request (docs/design/tasks/007-active-record-snapshot.md
      # "DB unavailable partial result").
      def model_result(params)
        name = params && params[:name].to_s
        eager_load_models! if active_record_available?
        klass = valid_model_class(name)
        return { name: name, error: { code: "NOT_FOUND", message: "no such model: #{name.inspect}" } } unless klass

        model_payload(klass)
      end

      # Bulk counterpart to discover_models + N x agent/model: returns
      # every non-abstract model's full columns/associations in a single
      # response. Real Rails apps can have hundreds of models, and issuing
      # one agent/model round trip per model made initial registry
      # population (RailsBootstrap) slow purely from request/response
      # overhead, not actual work -- this does the same
      # descendants/extract_columns/extract_associations work Core needed
      # anyway, just without a round trip per model
      # (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      # agent/snapshot's "models" section stays deliberately lightweight
      # (name/tableName only) for callers that just need to know what
      # exists, not this method's full detail.
      def models_result
        return { models: [] } unless active_record_available?

        eager_load_models!

        models = ::ActiveRecord::Base.descendants.reject(&:abstract_class?).filter_map do |klass|
          next nil unless klass.respond_to?(:name) && klass.name

          model_payload(klass)
        end

        { models: models, activeRecordApi: active_record_api }
      end

      # The Active Record API itself, reported once rather than per model.
      #
      # A model's ancestors above ApplicationRecord are outside the
      # workspace and have no signatures, so Core could see a model's
      # columns and associations but not `save`, `destroy`, `find` or
      # `where` -- the methods a Rails developer reaches for constantly.
      # Completion on a model offered columns only, and the unknown-method
      # check stayed silent because the receiver was never a closed class.
      #
      # Taken from the loaded classes rather than guessed or hardcoded:
      # this Agent has the real Rails booted, which is the entire reason
      # it exists (ADR-0002). What ships is therefore what that version of
      # Rails actually defines, not what some vendored signature claims.
      #
      # ActiveRecord::Base's own API is the same for every model, so it is
      # sent once (~1000 names, ~17KB) instead of once per model, which
      # for an app with hundreds of models would have been megabytes of
      # identical strings. Per-model additions (concerns, scopes) already
      # arrive through each model's own payload.
      def active_record_api
        return nil unless active_record_available?

        {
          instance: callable_names(::ActiveRecord::Base.instance_methods - Object.instance_methods),
          singleton: callable_names(::ActiveRecord::Base.methods - Object.methods)
        }
      rescue StandardError => e
        @logger.call("active record api unavailable: #{e.class}: #{e.message}")
        nil
      end

      # Operators (`==`, `<=>`, `[]`) are real methods but never useful as
      # completion items after a dot, so they are dropped here rather than
      # shipped and filtered by every consumer.
      #
      # So are leading-underscore names. Rails' callback and internal
      # machinery contributes hundreds of them (`__callbacks`,
      # `_create_callbacks`, `_reflections`, ...) -- measured: they were
      # most of a 442-item completion list on a three-column model, which
      # buries the handful of methods anyone is looking for. Ruby's own
      # convention already reads a leading underscore as "not for you".
      def callable_names(names)
        names.map(&:to_s).select { |name| name.match?(/\A[a-z][A-Za-z0-9_]*[?!=]?\z/) }.sort
      end

      def model_payload(klass)
        columns, partial = extract_columns(klass)
        instance_extras, singleton_extras = model_method_extras(klass)

        {
          name: klass.name,
          tableName: safely { klass.table_name },
          columns: columns,
          associations: extract_associations(klass),
          partial: partial,
          instanceMethods: instance_extras,
          singletonMethods: singleton_extras
        }
      end

      # What this model adds on top of ActiveRecord::Base: attribute
      # readers/writers and their dirty-tracking variants
      # (`title_changed?`, `saved_change_to_title?`, ...), association
      # accessors, enum predicates, scopes, concerns, and its own `def`s.
      #
      # Reported rather than reconstructed. Rails generates these by
      # convention, and a convention re-implemented here is a convention
      # that drifts: every Rails version that adds a variant would produce
      # a false "no method named" on code that runs fine. Asking the
      # loaded class removes the guesswork -- including whether the model
      # defines `method_missing`, which is what decides whether the
      # unknown-method check may run against it at all.
      #
      # `define_attribute_methods` first, because Rails defines attribute
      # methods lazily: before something touches them, `instance_methods`
      # genuinely does not list `title` for a model with a title column
      # (measured: 0 extras before, 119 after). It is the same call Rails
      # itself makes on first access, so this only does earlier what the
      # app would do anyway.
      def model_method_extras(klass)
        safely { klass.define_attribute_methods }
        base = ::ActiveRecord::Base
        [
          callable_names(klass.instance_methods - base.instance_methods),
          callable_names(klass.methods - base.methods)
        ]
      rescue StandardError => e
        @logger.call("method list unavailable for #{klass.name}: #{e.class}: #{e.message}")
        [[], []]
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
            optional: association_optional?(klass, reflection)
          }
        end
      end

      # `optional: reflection.options[:optional] != false` (the previous
      # implementation) is wrong for `belongs_to` on any app targeting
      # Rails 5+: `config.load_defaults` sets `belongs_to_required_by_default`
      # to true, meaning a `belongs_to` written *without* an explicit
      # `optional:` is actually REQUIRED, not optional -- but
      # `options[:optional]` is simply absent (nil) in that ordinary case,
      # and `nil != false` is true, so every belongs_to without an
      # explicit `optional:` kwarg was reported as optional regardless of
      # the app's actual (and, since Rails 5, default) configuration
      # (docs/design/tasks/008.6-agent-and-index-hardening.md). Only
      # `belongs_to` has this required-by-default behavior in Rails;
      # `has_one`/`has_many` keep the prior raw-options check, which is
      # what they've always meant here (LocalInferencer never reads
      # `.optional` for those macros the same way -- see
      # resolve_model_member in local_inferencer.rb).
      def association_optional?(klass, reflection)
        return reflection.options[:optional] != false unless reflection.macro == :belongs_to

        explicit = reflection.options[:optional]
        return explicit unless explicit.nil?

        !required_by_default?(klass)
      end

      def required_by_default?(klass)
        klass.respond_to?(:belongs_to_required_by_default) && klass.belongs_to_required_by_default ? true : false
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
      # real interface (name/verb/path.spec/defaults/required_parts,
      # source_location), so this works unchanged against a real Rails app
      # once one is wired in and against the rails_minimal fixture's fake
      # router alike. Unnamed routes produce no helper and are skipped,
      # matching the fact that Rails itself doesn't generate a `*_path`
      # method for them — real Rails only names the first verb sharing a
      # path (e.g. GET /posts is "posts", POST /posts sharing that same
      # path is unnamed), verified empirically against Rails 8.1.
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
            sourceLocation: normalize_source_location(route.respond_to?(:source_location) ? route.source_location : nil),
            routeSet: "main_app"
          }
        end
      end

      # Normalizes whatever shape `route.source_location` comes in as into
      # a stable `{ path:, line:, column: }` (or nil), per
      # docs/design/tasks/008.5-runtime-and-index-corrections.md. Real
      # Rails (verified against 8.1) returns a `"path:line"` string with a
      # 1-based line number — sometimes a gem path like
      # "railties (8.1.3) lib/rails/application/finisher.rb:143" for
      # framework-internal routes, not necessarily a real file on disk,
      # which is fine: Core degrades gracefully (docs/design/tasks/006-routes-snapshot.md
      # "source location unavailable" fallback) if the path doesn't
      # resolve to anything real. Never raises — a route whose location
      # can't be parsed just gets nil, exactly like one with no location
      # data at all.
      def normalize_source_location(raw)
        path, line = parse_source_location(raw)
        return nil unless path && line

        {
          path: absolute_source_path(path),
          line: [line.to_i - 1, 0].max, # Rails line numbers are 1-based; LSP is 0-based
          column: 0
        }
      rescue StandardError => e
        @logger.call("failed to normalize route source_location #{raw.inspect}: #{e.class}: #{e.message}")
        nil
      end

      def parse_source_location(raw)
        case raw
        when String
          match = raw.match(/\A(?<path>.+):(?<line>\d+)\z/)
          match ? [match[:path], match[:line]] : nil
        when Hash
          [raw[:path] || raw["path"], raw[:line] || raw["line"]]
        when Array
          raw.size == 2 ? raw : nil
        else
          raw.respond_to?(:path) && raw.respond_to?(:lineno) ? [raw.path, raw.lineno] : nil
        end
      end

      def absolute_source_path(path)
        return path if path.start_with?("/")

        File.expand_path(path, rails_root)
      end

      def routes_available?
        rails_defined? && Rails.respond_to?(:application) && Rails.application.respond_to?(:routes)
      end

      def reload_available?
        routes_available? && Rails.application.respond_to?(:reload_routes!)
      end

      # docs/design/docs/04-runtime-agent.md section 8, extended by Task
      # 008.5 to also reload models: `sections` (defaulting to both) picks
      # which parts to redo, each independently rescued so a routes
      # failure doesn't block a models reload or vice versa. On failure,
      # that section is left out of `changedSections` and generation only
      # advances if at least one section actually changed, so Core keeps
      # treating the last-good snapshot as current for whatever didn't
      # reload (docs/design/docs/04-runtime-agent.md: "reloadに失敗した場合:
      # generationを進めない").
      def reload_result(params)
        sections = (params && params[:sections]) || %w[routes models]
        changed = []
        errors = []

        reload_routes_section(sections, changed, errors)
        reload_models_section(sections, changed, errors)

        @generation += 1 unless changed.empty?
        { generation: @generation, changedSections: changed, errors: errors }
      end

      def reload_routes_section(sections, changed, errors)
        return unless sections.include?("routes") && reload_available?

        Rails.application.reload_routes!
        changed << "routes"
      rescue StandardError => e
        @logger.call("agent/reload (routes) failed: #{e.class}: #{e.message}")
        errors << { code: "RELOAD_FAILED", message: e.message, recoverable: true }
      end

      # `Rails.application.reloader.reload!` is Rails' own mechanism for
      # unloading and re-autoloading changed/removed app/models classes in
      # development -- without it, a deleted model's class stays defined
      # for the rest of the process, and `discover_models`/`model_result`
      # would keep finding it. Re-runs #eager_load_models! afterward so a
      # brand-new model file is immediately visible too, not just on the
      # next unrelated eager-load trigger.
      def reload_models_section(sections, changed, errors)
        return unless sections.include?("models") && active_record_available?

        Rails.application.reloader.reload! if rails_defined? && Rails.application.respond_to?(:reloader)
        eager_load_models!
        changed << "models"
      rescue StandardError => e
        @logger.call("agent/reload (models) failed: #{e.class}: #{e.message}")
        errors << { code: "RELOAD_FAILED", message: e.message, recoverable: true }
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
