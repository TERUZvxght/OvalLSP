# frozen_string_literal: true

require_relative "../index/symbol_id"

module Ovallsp
  module Routes
    # Converts a Rails route's `defaults[:controller]` path (e.g. "posts",
    # "admin/projects") into the fully-qualified class name ParserService's
    # SymbolId would use for it (e.g. "::PostsController",
    # "::Admin::ProjectsController"), so a route helper's action targets can
    # be looked up in the WorkspaceIndex.
    module ControllerNaming
      module_function

      def owner_name(controller_path)
        segments = controller_path.to_s.split("/").map { |segment| camelize(segment) }
        return nil if segments.empty?

        segments[-1] = "#{segments[-1]}Controller"
        Index::SymbolId.qualify_owner(segments.join("::"))
      end

      def camelize(segment)
        segment.split("_").map { |part| part[0]&.upcase.to_s + part[1..].to_s }.join
      end

      # The inverse of #owner_name: "::UsersController" -> "users",
      # "::Admin::ProjectsController" -> "admin/projects". Used to find a
      # view's conventional controller (Task 008) as well as a route
      # helper's underlying controller path.
      def view_directory(owner_name)
        segments = Index::SymbolId.bare_name(owner_name).split("::")
        return nil if segments.empty?

        segments[-1] = segments[-1].sub(/Controller\z/, "")
        segments.map { |segment| underscore(segment) }.join("/")
      end

      def underscore(segment)
        segment.gsub(/([a-z0-9])([A-Z])/, '\1_\2').downcase
      end
    end
  end
end
