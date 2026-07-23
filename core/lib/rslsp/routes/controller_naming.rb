# frozen_string_literal: true

module Rslsp
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
        "::#{segments.join('::')}"
      end

      def camelize(segment)
        segment.split("_").map { |part| part[0]&.upcase.to_s + part[1..].to_s }.join
      end
    end
  end
end
