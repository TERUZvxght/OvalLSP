# frozen_string_literal: true

require "uri"

module Rslsp
  # Minimal file:// URI <-> path conversion. Only the `file` scheme is
  # supported, which matches the MVP's single-Bundler-app, local-workspace
  # scope (docs/design/README.md "初期対応範囲").
  module UriUtil
    module_function

    def to_path(uri)
      return nil unless uri.is_a?(String) && uri.start_with?("file://")

      URI::DEFAULT_PARSER.unescape(URI.parse(uri).path)
    rescue URI::InvalidURIError
      nil
    end

    def from_path(path)
      "file://#{path}"
    end
  end
end
