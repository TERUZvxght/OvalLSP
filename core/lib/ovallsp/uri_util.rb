# frozen_string_literal: true

require "uri"

module Ovallsp
  # Minimal file:// URI <-> path conversion. Only the `file` scheme is
  # supported, which matches the MVP's single-Bundler-app, local-workspace
  # scope (docs/design/README.md "初期対応範囲"). Task 008.5 hardens both
  # directions against: spaces, non-ASCII (Japanese) characters, `#`, `%`,
  # Windows drive letters, Windows `\` separators, UNC paths, and
  # already-URI-formatted input -- previously a bare `"file://#{path}"`
  # concatenation with no escaping at all, which produced a URI that
  # didn't round-trip (and in the `#`/`%` case, silently truncated or
  # mis-parsed the path) for anything but a plain ASCII path with no
  # special characters.
  module UriUtil
    module_function

    WINDOWS_DRIVE_PATH = %r{\A/?(?<drive>[A-Za-z]):(?<rest>/.*)?\z}

    def to_path(uri)
      return nil unless uri.is_a?(String) && uri.start_with?("file://")

      parsed = URI.parse(uri)
      return nil unless parsed.scheme == "file"

      path = URI::DEFAULT_PARSER.unescape(parsed.path.to_s)
      host = parsed.host

      if host && !host.empty? && host != "localhost"
        # UNC path: file://server/share/foo -> //server/share/foo
        "//#{URI::DEFAULT_PARSER.unescape(host)}#{path}"
      elsif (match = WINDOWS_DRIVE_PATH.match(path))
        # file:///C:/foo has an RFC 8089-style path of "/C:/foo"; the
        # leading slash isn't part of the actual (Windows) path.
        "#{match[:drive]}:#{match[:rest]}"
      else
        path
      end
    rescue URI::InvalidURIError
      nil
    end

    # Raises rather than silently building a bogus URI from a relative
    # path -- a relative path has no fixed meaning as a `file://` URI, and
    # every real caller in this codebase already has an absolute one
    # (Cold Index walks from an expanded root, route source_locations are
    # normalized to absolute at the Agent boundary).
    def from_path(path)
      raise ArgumentError, "from_path requires an absolute path: #{path.inspect}" unless absolute_path?(path)

      return path if path.start_with?("file://") # already a URI; pass through as-is

      normalized = path.tr("\\", "/")

      if (match = WINDOWS_DRIVE_PATH.match(normalized))
        "file:///#{match[:drive]}:#{escape(match[:rest] || "")}"
      elsif normalized.start_with?("//")
        # UNC: //server/share/foo -> file://server/share/foo
        host, _, rest = normalized[2..].partition("/")
        "file://#{escape(host)}/#{escape(rest)}"
      else
        "file://#{escape(normalized)}"
      end
    end

    def absolute_path?(path)
      return false unless path.is_a?(String) && !path.empty?
      return true if path.start_with?("file://")
      return true if path.start_with?("/") || path.start_with?("\\")

      WINDOWS_DRIVE_PATH.match?(path.tr("\\", "/"))
    end

    # Escapes every path segment individually so a literal `/` in the
    # input never turns into an extra path separator, while leaving `/`
    # itself unescaped between segments.
    def escape(path)
      path.split("/", -1).map { |segment| URI::DEFAULT_PARSER.escape(segment, /[^A-Za-z0-9\-._~:]/) }.join("/")
    end
  end
end
