# frozen_string_literal: true

module Ovallsp
  module Routes
    # One controller action a route helper can lead to. A single helper
    # (e.g. `post_path`) commonly maps to several actions that share a path
    # but differ by HTTP verb (GET show, PATCH/PUT update, DELETE destroy).
    ActionTarget = Data.define(:controller, :action, :verb)

    # Everything Core needs to offer completion, signature help, and
    # definition for one named route helper, built from every RouteFact
    # sharing that route name (docs/design/tasks/006-routes-snapshot.md).
    RouteHelper = Data.define(:name, :path_helper, :url_helper, :required_parts, :optional_parts, :source_location,
                              :action_targets)

    # Holds the current set of named-route helpers derived from an
    # agent/snapshot "routes" section. #replace performs a full swap, so a
    # later snapshot (e.g. after a routes.rb edit + Agent reload) that no
    # longer includes a route makes that helper disappear from completion
    # and definition — there's no merge/accumulation across snapshots.
    #
    # #replace may run on a background thread (RailsBootstrap) concurrently
    # with reads from the main thread. A mutex publishes the complete table
    # and its generation atomically.
    class RouteRegistry
      def self.from_route_facts(route_facts)
        new.tap { |registry| registry.replace(route_facts) }
      end

      def initialize
        @helpers = {}
        @generation = 0
        @mutex = Mutex.new
      end

      def generation = @mutex.synchronize { @generation }

      # Whether a snapshot has ever been applied. An empty table means two
      # different things -- "this application has no named routes" and
      # "nobody has told us about any" -- and the diagnostics check can
      # only report against the first. Without a Runtime Agent the second
      # is what holds, and answering "no such route" there reported every
      # ordinary method whose name happens to end `_path` or `_url`:
      # 8 across Ruby's own standard library, all false (024.24).
      #
      # `@generation` counts applications rather than routes, so an
      # application whose `routes.rb` is empty still loads.
      def loaded? = @mutex.synchronize { @generation.positive? }

      def replace(route_facts)
        commit_replace(prepare_replace(route_facts))
      end

      # See ModelRegistry#prepare_replace: building and publication are
      # separate so Server can validate a routes+models snapshot before
      # making either half visible.
      def prepare_replace(route_facts)
        grouped = Hash.new { |h, k| h[k] = [] }
        route_facts.each do |fact|
          name = fact[:name]
          grouped[name] << fact if name && !name.to_s.empty?
        end

        grouped.transform_values { |facts| build_helper(facts) }
      end

      def commit_replace(replacement)
        @mutex.synchronize do
          @helpers = replacement.dup
          @generation += 1
        end
      end

      def helper(name)
        @mutex.synchronize { @helpers[name.to_s] }
      end

      # Resolves a Ruby method call name like "post_path" or "posts_url"
      # back to its RouteHelper, regardless of which of the two forms was
      # used.
      def find_by_method_name(method_name)
        match = method_name.to_s.match(/\A(?<name>.+)_(?:path|url)\z/)
        return nil unless match

        helper(match[:name])
      end

      def completion_names(prefix = "")
        @mutex.synchronize do
          @helpers.each_key.flat_map { |name| ["#{name}_path", "#{name}_url"] }
                  .select { |candidate| candidate.start_with?(prefix) }
                  .sort
        end
      end

      def empty?
        @mutex.synchronize { @helpers.empty? }
      end

      private

      def build_helper(facts)
        first = facts.first

        RouteHelper.new(
          name: first[:name].to_s,
          path_helper: "#{first[:name]}_path",
          url_helper: "#{first[:name]}_url",
          required_parts: Array(first[:requiredParts]).map(&:to_s),
          optional_parts: Array(first[:optionalParts]).map(&:to_s),
          source_location: valid_source_location(first[:sourceLocation]),
          action_targets: action_targets(facts)
        )
      end

      # The Agent is expected to normalize source locations to
      # { path:, line:, column: } before this ever arrives
      # (docs/design/tasks/008.5-runtime-and-index-corrections.md), but
      # Core must not crash or build a bogus jump target if it doesn't —
      # an Agent Protocol implementation is still a boundary, not a
      # trusted internal call.
      def valid_source_location(value)
        return nil unless value.is_a?(Hash)

        path = value[:path]
        line = value[:line]
        return nil unless path.is_a?(String) && !path.empty? && line.is_a?(Integer)

        { path: path, line: line, column: value[:column].is_a?(Integer) ? value[:column] : 0 }
      end

      def action_targets(facts)
        targets = facts.map do |fact|
          defaults = fact[:defaults] || {}
          ActionTarget.new(
            controller: (defaults[:controller] || defaults["controller"]).to_s,
            action: (defaults[:action] || defaults["action"]).to_s,
            verb: fact[:verb].to_s
          )
        end.uniq

        # sort_by isn't guaranteed stable, and GET should always lead
        # (definition surfaces it as the primary secondary-target — see
        # Server#route_helper_definitions) without otherwise reshuffling.
        targets.each_with_index.sort_by { |target, i| [target.verb == "GET" ? 0 : 1, i] }.map(&:first)
      end
    end
  end
end
