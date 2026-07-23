# frozen_string_literal: true

module Rslsp
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
    # with reads from the main thread. No mutex: `@helpers` is only ever
    # reassigned wholesale, after the new Hash is fully built, so a reader
    # sees either the complete old table or the complete new one — never a
    # partial one. This relies on CRuby's GVL making that single Hash
    # reference reassignment atomic.
    class RouteRegistry
      def self.from_route_facts(route_facts)
        new.tap { |registry| registry.replace(route_facts) }
      end

      def initialize
        @helpers = {}
      end

      def replace(route_facts)
        grouped = Hash.new { |h, k| h[k] = [] }
        route_facts.each do |fact|
          name = fact[:name]
          grouped[name] << fact if name && !name.to_s.empty?
        end

        @helpers = grouped.transform_values { |facts| build_helper(facts) }
      end

      def helper(name)
        @helpers[name.to_s]
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
        @helpers.each_key.flat_map { |name| ["#{name}_path", "#{name}_url"] }
                .select { |candidate| candidate.start_with?(prefix) }
                .sort
      end

      def empty?
        @helpers.empty?
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
          source_location: first[:sourceLocation],
          action_targets: action_targets(facts)
        )
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
