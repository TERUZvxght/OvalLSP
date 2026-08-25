# frozen_string_literal: true

# A tiny stand-in for ActionDispatch::Routing. Real Rails isn't a
# dependency of this repo (see docs/design/tasks/006-routes-snapshot.md),
# so this fixture implements just enough of a `resources`/`namespace`/
# `member`/`collection` DSL to exercise Task 006's route extraction against
# something resources/nested-resources/namespace-shaped, without pulling in
# actionpack. Every FakeRoute exposes the same accessor names a real
# ActionDispatch::Journey::Route does (name, verb, path.spec, defaults,
# required_parts), so Ovallsp::RuntimeAgent::Agent#extract_routes only ever
# talks to that duck-typed interface.
module FakeRouting
  Route = Struct.new(:name, :verb, :path_spec, :defaults, :required_parts, :parts, :source_location,
                     keyword_init: true) do
    def path
      Struct.new(:spec).new(path_spec)
    end
  end

  class RouteSet
    attr_reader :routes

    def initialize
      @routes = []
    end

    def draw(&block)
      Drawer.new(self).instance_eval(&block)
    end
  end

  class Drawer
    def initialize(route_set, path_prefix: "", helper_prefix: "", namespace: nil)
      @route_set = route_set
      @path_prefix = path_prefix
      @helper_prefix = helper_prefix
      @namespace = namespace
    end

    def namespace(name, &block)
      self.class.new(
        @route_set,
        path_prefix: "#{@path_prefix}/#{name}",
        helper_prefix: "#{@helper_prefix}#{name}_",
        namespace: [@namespace, name].compact.join("/")
      ).instance_eval(&block)
    end

    def resources(name, location: nil, &block)
      location ||= caller_locations(1, 1).first
      singular = name.to_s.sub(/s\z/, "")
      controller = [@namespace, name].compact.join("/")
      base_path = "#{@path_prefix}/#{name}"
      member_path = "#{base_path}/:id"

      # Real Rails only names the *first* verb sharing a path — index (GET
      # /posts) is named "posts", but create (POST /posts) shares that
      # path and gets no name of its own; same for show vs. update/destroy
      # on /posts/:id. Verified against actual Rails 8.1 route output
      # (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      add_route(name: "#{@helper_prefix}#{name}", verb: "GET", path: base_path, action: "index",
                controller: controller, location: location)
      add_route(name: nil, verb: "POST", path: base_path, action: "create",
                controller: controller, location: location)
      add_route(name: "#{@helper_prefix}new_#{singular}", verb: "GET", path: "#{base_path}/new", action: "new",
                controller: controller, location: location)
      add_route(name: "#{@helper_prefix}#{singular}", verb: "GET", path: member_path, action: "show",
                controller: controller, location: location)
      add_route(name: nil, verb: "PATCH", path: member_path, action: "update",
                controller: controller, location: location)
      add_route(name: nil, verb: "PUT", path: member_path, action: "update",
                controller: controller, location: location)
      add_route(name: nil, verb: "DELETE", path: member_path, action: "destroy",
                controller: controller, location: location)
      add_route(name: "#{@helper_prefix}edit_#{singular}", verb: "GET", path: "#{member_path}/edit", action: "edit",
                controller: controller, location: location)

      return unless block

      ResourceScope.new(
        route_set: @route_set, name: name, singular: singular, base_path: base_path, member_path: member_path,
        helper_prefix: @helper_prefix, namespace: @namespace, controller: controller
      ).instance_eval(&block)
    end

    %i[get post put patch delete].each do |verb|
      define_method(verb) do |path, to:, as: nil|
        location = caller_locations(1, 1).first
        controller, action = to.split("#")
        add_route(
          name: as && "#{@helper_prefix}#{as}", verb: verb.to_s.upcase, path: "#{@path_prefix}#{path}",
          action: action, controller: controller, location: location
        )
      end
    end

    # Adds a route with no source location at all, simulating a route
    # whose definition can't be pinned to a file/line (Task 006's "route
    # source location unavailable" fallback case).
    def unlocatable(name:, path:, action:, controller:)
      add_route(name: "#{@helper_prefix}#{name}", verb: "GET", path: path, action: action, controller: controller,
                location: nil)
    end

    private

    def add_route(name:, verb:, path:, action:, controller:, location:)
      full_path = "#{path}(.:format)"
      required = full_path.scan(/:(\w+)/).flatten - ["format"]

      @route_set.routes << Route.new(
        name: name,
        verb: verb,
        path_spec: full_path,
        defaults: { "controller" => controller, "action" => action },
        required_parts: required,
        # Rails' route carries both lists, and the Agent reads optional
        # parts as the difference (`024.136`). This fixture exists to
        # mimic that interface, so it carries both too.
        parts: required + ["format"],
        # Matches real Rails' actual format (verified against Rails 8.1:
        # "/abs/path/config/routes.rb:12", 1-based) rather than a
        # pre-normalized Hash — normalization is the Agent's job
        # (docs/design/tasks/008.5-runtime-and-index-corrections.md), not
        # something a Rails app itself provides pre-digested.
        source_location: location && "#{location.absolute_path}:#{location.lineno}"
      )
    end
  end

  # The context inside `resources :x do ... end`: only `member`, `collection`,
  # and further nested `resources` are meaningful here.
  class ResourceScope
    def initialize(route_set:, name:, singular:, base_path:, member_path:, helper_prefix:, namespace:, controller:)
      @route_set = route_set
      @name = name
      @singular = singular
      @base_path = base_path
      @member_path = member_path
      @helper_prefix = helper_prefix
      @namespace = namespace
      @controller = controller
    end

    def member(&block)
      MemberCollectionScope.new(
        route_set: @route_set, path: @member_path, helper_prefix: "#{@helper_prefix}#{@singular}_",
        controller: @controller
      ).instance_eval(&block)
    end

    def collection(&block)
      MemberCollectionScope.new(
        route_set: @route_set, path: @base_path, helper_prefix: "#{@helper_prefix}#{@name}_",
        controller: @controller
      ).instance_eval(&block)
    end

    def resources(nested_name, &block)
      location = caller_locations(1, 1).first
      # Real Rails renames the parent segment to avoid colliding with the
      # nested resource's own :id (e.g. /posts/:post_id/comments/:id).
      nested_prefix = "#{@base_path}/:#{@singular}_id"
      Drawer.new(
        @route_set, path_prefix: nested_prefix, helper_prefix: "#{@helper_prefix}#{@singular}_", namespace: @namespace
      ).resources(nested_name, location: location, &block)
    end
  end

  # The context inside `member do ... end` / `collection do ... end`.
  class MemberCollectionScope
    def initialize(route_set:, path:, helper_prefix:, controller:)
      @route_set = route_set
      @path = path
      @helper_prefix = helper_prefix
      @controller = controller
    end

    %i[get post put patch delete].each do |verb|
      define_method(verb) do |action|
        location = caller_locations(1, 1).first
        full_path = "#{@path}/#{action}(.:format)"
        required = full_path.scan(/:(\w+)/).flatten - ["format"]

        @route_set.routes << Route.new(
          name: "#{@helper_prefix}#{action}",
          verb: verb.to_s.upcase,
          path_spec: full_path,
          defaults: { "controller" => @controller, "action" => action.to_s },
          required_parts: required,
          parts: required + ["format"],
          source_location: "#{location.absolute_path}:#{location.lineno}"
        )
      end
    end
  end
end
