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
      # 2: `agent/gemIndex` (0.3.0, 024.R7). Core refuses an Agent whose
      # version differs rather than discovering a missing method at the
      # first call, so a protocol that gains one is a new version -- the
      # Agent ships inside the same artifact as the Core, and the guard
      # exists for a stale process spawned by an earlier install.
      PROTOCOL_VERSION = 2

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
        when "agent/gemIndex"
          respond(id, gem_index_result(message[:params]))
        when "agent/ancestors"
          respond(id, ancestors_result(message[:params]))
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
      # a full model dump.
      #
      # **`"metadata"` is gone.** Task 006 implemented it and nothing ever
      # asked for it: every caller of `AgentProcessManager#fetch_snapshot`
      # passes `["routes"]` (`rails_bootstrap.rb:118`, `server.rb:3426`),
      # and no spec requested the section. It also restated three of
      # `#hello_result`'s four fields, so a Core that wanted it had a
      # cheaper way to ask. The `|| ["metadata"]` default went with it: a
      # request naming no section now returns nothing, which is what
      # "returns only the requested sections" already said (`048`).
      def snapshot_result(params)
        sections = (params && params[:sections]) || []
        result = {}
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
        concrete_models { |klass| { name: klass.name, tableName: safely { klass.table_name } } }
      end

      # The one place that decides which classes count as a model.
      #
      # `#discover_models` and `#models_result` had the same four
      # decisions written out twice -- is ActiveRecord loaded, eager-load
      # first, drop `abstract_class?`, drop anything without a usable
      # `name` -- and differed only in the payload built from each class.
      # Two copies of an enumeration is how one of them ends up answering
      # about a different set (`048`).
      #
      # Yields the class rather than returning a payload, because the two
      # payloads are genuinely different: discovery is deliberately
      # lightweight and `agent/models` is not.
      def concrete_models
        return [] unless active_record_available?

        eager_load_models!

        ::ActiveRecord::Base.descendants.reject(&:abstract_class?).filter_map do |klass|
          next nil unless klass.respond_to?(:name) && klass.name

          yield klass
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

        { models: concrete_models { |klass| model_payload(klass) },
          activeRecordApi: active_record_api }
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

        base = ::ActiveRecord::Base
        instance = callable_names(base.instance_methods - Object.instance_methods)
        # Not `- Object.methods`. `Object` is itself a class object, so
        # subtracting its singleton list removes every public `Module`
        # instance method -- and that is where ActiveSupport puts
        # `delegate`, `class_attribute`, `mattr_accessor`,
        # `thread_mattr_accessor`, `concerning` and `deprecate`. All six
        # were reported as unknown methods on every model that used them,
        # `delegate` being one of the commonest lines in a Rails model,
        # because `Diagnostics::Engine` reads this list as the model's
        # *complete* class-level method set rather than as an addition to
        # a known baseline.
        #
        # The instance side keeps its subtraction: `Object.instance_methods`
        # is what a plain object has, which is a real baseline. There is
        # no equivalent for the class side -- a class object genuinely
        # responds to everything `Class`, `Module`, `Object` and `Kernel`
        # give it, and the engine has no other source that knows what
        # ActiveSupport added to them at runtime. 783 names rather than
        # 620, once.
        singleton = callable_names(base.methods)
        {
          instance: instance,
          singleton: singleton,
          # Which of those accept an argument at all. Rails' own methods
          # are nearly all `(*, **, &)`, so their parameter *names* are
          # worthless for completion -- but "takes something" versus
          # "takes nothing" is exactly what decides whether an editor
          # should offer `where()` with the cursor inside, or a bare
          # `save`. That distinction is derivable here and nowhere else.
          instanceWithArguments: names_taking_arguments(instance) { |name| base.instance_method(name) },
          singletonWithArguments: names_taking_arguments(singleton) { |name| base.method(name) }
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
      # A method "takes arguments" when its parameter list contains
      # anything a caller could pass: required, optional, keyword, or the
      # variadic forms. A lone block parameter does not count -- `each`
      # is written `each` in Ruby, not `each()`.
      def names_taking_arguments(names)
        names.select do |name|
          parameters = yield(name).parameters
          parameters.any? { |kind, _| %i[req opt rest key keyreq keyrest].include?(kind) }
        rescue StandardError
          false
        end
      end

      # Answers, for each requested name, the ancestors the application
      # really gives that class -- and `Object.ancestors` alongside them,
      # because that is the baseline Core subtracts. Core's unknown-method
      # check believes a class's ancestry is complete when the workspace
      # declares every link in it; a class the workspace merely *reopens*
      # looks exactly the same, and only this process can tell the
      # difference (docs/design/tasks/024-deferred-review-findings.md, 024.R5).
      #
      # `null` for a name is a real answer -- "the application does not
      # have this" -- and Core relies on it to leave the static reading
      # alone rather than waiting for something that will never come.

      # 024.R7. What the gems define, which is the thing nothing else here
      # can see.
      #
      # The undefined-method check fires only on a *closed* receiver, and a
      # class is closed only when the workspace can see its whole ancestry.
      # In a Rails application that is a minority: a controller inherits
      # from `ApplicationController`, whose parent is in a gem, so the check
      # stays silent exactly where most code is written. The running
      # application knows all of it.
      #
      # **Attribution is by definition site, not by namespace.** A constant
      # is credited to a gem when `Object.const_source_location` puts it
      # inside that gem's directory -- so a class an application reopens is
      # still the gem's, and a class named like a gem's but defined in the
      # app is not.
      #
      # Names only. Measured on a small Rails 8 app: 3027 named modules,
      # 2204 attributable to 63 gems, 15868 methods defined directly on
      # them -- roughly 365KB, which is small enough to persist and far too
      # much to send per query. So this is asked once and cached, never
      # asked on the request path.
      def gem_index_result(_params)
        by_gem = Hash.new { |h, k| h[k] = [] }
        each_named_module do |mod, name|
          gem = gem_for(mod, name) or next

          by_gem[gem] << module_answer(mod, name)
        end
        { gems: by_gem.transform_values { |classes| { classes: classes } } }
      end


      # `false` on each: this class's own definition, not an inherited one.
      # The chain is reported separately and Core asks every link, so
      # searching ancestors here would mark 2,000 classes dynamic because
      # one of them is.
      def answers_dynamically?(mod)
        %i[method_missing respond_to_missing?].any? do |name|
          mod.private_method_defined?(name, false) || mod.method_defined?(name, false)
        end
      end

      def each_named_module
        ::ObjectSpace.each_object(::Module) do |mod|
          name = module_name(mod) or next

          yield mod, name
        end
      end

      # `…/gems/<name>-<version>/` is the shape every installed gem's path
      # has, whatever the bundle layout, and it carries the version -- which
      # is what makes the cache invalidate per gem rather than wholesale.
      GEM_PATH = %r{/gems/(?<gem>[^/]+-[0-9][^/]*)/}

      def gem_for(mod, name)
        location = safely { ::Object.const_source_location(name) }
        path = location.is_a?(Array) ? location.first : nil
        return nil unless path

        GEM_PATH.match(path.to_s)&.[](:gem)
      end

      # Its own methods, not its inherited ones: the ancestors are reported
      # separately and reassembling them is Core's job, because sending each
      # class its full ancestry's methods would repeat `Object`'s set 2204
      # times.
      #
      # `definesMethodMissing` is reported because a class that defines one
      # answers to names no index can enumerate -- and "closed" has to mean
      # "we know the full method set", or the check built on it asserts
      # something it has not established.
      def module_answer(mod, name)
        {
          name: name,
          ancestors: safely { mod.ancestors.filter_map { |a| module_name(a) } } || [],
          instanceMethods: safely { mod.instance_methods(false).map(&:to_s) } || [],
          singletonMethods: safely { mod.singleton_methods(false).map(&:to_s) } || [],
          # `extend`ed modules put their *instance* methods on the
          # class-level chain, and `singleton_methods(false)` does not
          # see them. Asked of Ruby rather than assumed:
          #
          #   $ ruby -rcgi -e '
          #   p CGI.singleton_methods(false).include?(:escapeHTML)
          #   p CGI.singleton_class.ancestors.first(3).map(&:to_s)
          #   '
          #   # => false
          #   # => ["#<Class:CGI>", "CGI::Escape", "CGI::Util"]
          #   # ruby 3.4.10
          #
          # Without this, `CGI.escapeHTML` -- which exists -- was
          # reported missing over rack's own source.
          singletonAncestors: safely { mod.singleton_class.ancestors.filter_map { |a| module_name(a) } } || [],
          # **Both visibilities.** `method_missing` is conventionally
          # private, and `private_method_defined?` alone cannot see a
          # public one -- so a class that defines it publicly was
          # reported as having none, called closed, and every name it
          # answers dynamically became a false report. Asked of Ruby:
          #
          #   $ ruby -e '
          #   class Pub; def method_missing(n, *) = :a; end
          #   p Pub.private_method_defined?(:method_missing, false)
          #   p Pub.method_defined?(:method_missing, false)
          #   '
          #   # => false
          #   # => true
          #   # ruby 3.4.10
          #
          # `respond_to_missing?` too: a class that implements only that
          # one still answers to names no enumeration can list.
          definesMethodMissing: safely { answers_dynamically?(mod) } || false
        }
      end

      def ancestors_result(params)
        names = Array(params && (params[:names] || params["names"])).map(&:to_s)

        {
          objectAncestors: ::Object.ancestors.filter_map { |mod| module_name(mod) },
          classes: names.to_h { |name| [name, class_answer(name)] }
        }
      end

      # One of three answers, and the difference between them is the whole
      # point:
      #
      # - `{ancestors: [...]}` -- the class is loaded, so its real ancestry
      #   can be compared against Object's;
      # - `{definedOutsideWorkspace: true}` -- not loaded, but registered
      #   for autoload from a file that is not the workspace's, which
      #   settles the question without loading anything;
      # - `null` -- the application does not know this name, or knows it
      #   only from a workspace file it has not loaded yet. Both leave
      #   Core's static reading standing, which is the right answer for a
      #   class the workspace really does own.
      def class_answer(name)
        owner, segment = resolve_owner(name)
        return nil unless owner
        return nil unless safely { owner.const_defined?(segment, false) }

        # `false`, matching #const_defined? above: `autoload?` inherits by
        # default, so a class that really does define the constant itself
        # would otherwise be handed its *superclass's* autoload path and
        # judged to live outside the workspace on that evidence.
        registered = safely { owner.autoload?(segment, false) }
        return autoload_answer(registered) if registered

        value = safely { owner.const_get(segment, false) }
        return nil unless value.is_a?(::Module)

        { ancestors: safely { value.ancestors.filter_map { |ancestor| module_name(ancestor) } } }
      end

      # Zeitwerk registers the application's own classes by absolute path
      # (".../app/models/article.rb"), while a gem's `autoload` registers
      # the bare require path it was written with ("active_support/test_case").
      # So a registration that is not a real file under this workspace is
      # someone else's class -- which is exactly the provenance question,
      # answered without loading anything.
      def autoload_answer(path)
        return nil if workspace_path?(path)

        { definedOutsideWorkspace: true }
      end

      # A root that is not itself absolute cannot decide whose file a path
      # is, and treating it as a prefix would be worse than useless: an
      # empty root would make `"/anything"` look like the workspace's own
      # and silence the check everywhere.
      def workspace_path?(path)
        root = rails_root.to_s
        return false unless root.start_with?("/")

        path.to_s.start_with?(root.chomp("/") + "/")
      end

      # Walks every namespace segment but the last, and returns nil rather
      # than resolving through anything that would have to be loaded first.
      # `const_get` on an autoload-registered constant *runs the autoload*:
      # in a real application that raised Gem::LoadError from a gem outside
      # the bundle, and an Agent that loads arbitrary application code to
      # answer a diagnostic question is not one worth having (024.R5).
      def resolve_owner(name)
        segments = name.split("::")
        last = segments.pop
        owner = segments.reduce(::Object) do |current, segment|
          return nil unless current.is_a?(::Module)
          return nil unless safely { current.const_defined?(segment, false) }
          return nil if safely { current.autoload?(segment, false) }

          safely { current.const_get(segment, false) }
        end
        owner.is_a?(::Module) ? [owner, last] : nil
      rescue StandardError
        nil
      end

      # An anonymous class or one still being defined has no name to send.
      def module_name(mod)
        name = safely { mod.name }
        name && !name.empty? ? name : nil
      end

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
            # **From the route, not from the path spec's text.** This tested
            # the spec string for the literal `(.:format)`, so a route with
            # any other optional segment was reported as having none, and
            # Signature Help understated the helper's parameters -- a wrong
            # answer, since the helper does accept them (`024.136`).
            #
            # Rails carries both lists and the difference is the answer,
            # asked of a real 8.1.3.1 route set:
            #
            #   get "/posts(/:page)", to: "posts#index", as: :paged_posts
            #   r.parts          # => [:page, :format]
            #   r.required_parts # => []
            #
            # Duck-typed the same way `requiredParts` above already is, so
            # a route object without `parts` degrades to none rather than
            # raising.
            optionalParts: optional_parts_for(route),
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
      # `parts` minus `required_parts`, both duck-typed. A route that
      # answers neither has no optional parts to report, which is what an
      # empty list already means (`024.136`).
      def optional_parts_for(route)
        return [] unless route.respond_to?(:parts)

        Array(route.parts).map(&:to_s) - Array(route.required_parts).map(&:to_s)
      end

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
