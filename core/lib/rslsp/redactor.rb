# frozen_string_literal: true

module Rslsp
  # Log-message redaction (Task 022 "token/credential/path redaction方針" --
  # docs/design/tasks/022-compatibility-resilience-and-release.md). Applied
  # to every message Logger writes, since a log message is very often the
  # *rendered text of a caught exception* -- and an exception raised deep
  # inside a workspace's own Rails app (a `bundle install` failure, a
  # misconfigured initializer) can legitimately contain a credential the
  # exception message happened to interpolate (a DB connection string, an
  # API client's own error text), not just something this codebase wrote
  # itself.
  #
  # Deliberately conservative: a false-positive redaction (a harmless
  # value that happens to look credential-shaped) only costs a little log
  # readability; a false negative (a real secret that slips through)
  # could leak into a shared log file or a bug-report paste. Never
  # perfect -- this is a best-effort net, not a guarantee that no secret
  # can ever appear in a log line, which is why Logger's own docs still
  # say "must never be pointed at stdout" as the actual hard boundary
  # (stdout carries the LSP protocol, never logs, so this is defense in
  # depth on top of that, not instead of it).
  module Redactor
    # key=value / key: value / "key": "value" shapes for common
    # credential-sounding key names, case-insensitive, value quoted or
    # bare up to the next whitespace/quote/comma. Deliberately excludes
    # "authorization"/"auth" -- BEARER_PATTERN (below), applied first,
    # already covers the overwhelmingly common "Authorization: Bearer
    # <token>" shape; including a generic "auth" key here too caused it
    # to re-match the word "Bearer" itself (already redacted by that
    # point) as this pattern's own "value", redacting twice and,
    # ultimately, deleting the "Bearer" label from the output entirely.
    CREDENTIAL_KEY_PATTERN = /
      (?<key>password|passwd|secret|api[_-]?key|token|access[_-]?key|credential)
      (?<sep>\s*[:=]\s*"?)
      (?<value>[^\s"',}]+)
    /ix

    # A bearer/authorization-header-shaped token, wherever it appears
    # (not just after a `key=` label).
    BEARER_PATTERN = /\bBearer\s+[A-Za-z0-9\-._~+\/]+=*/

    # A long (20+ char) run of base64/hex-alphabet characters is the
    # generic shape most API keys/tokens/secrets take, regardless of
    # which service issued them -- deliberately broad rather than trying
    # to enumerate every vendor's own key format.
    GENERIC_TOKEN_PATTERN = /\b[A-Za-z0-9\-_]{20,}\b/

    module_function

    def redact(message)
      text = message.to_s
      # Bearer-token redaction runs first: CREDENTIAL_KEY_PATTERN's own
      # `auth(?:orization)?` key alternative would otherwise match
      # "Authorization: Bearer <token>" itself, consuming only the word
      # "Bearer" as its "value" and leaving the actual token after it
      # completely unredacted.
      text = text.gsub(BEARER_PATTERN, "Bearer [REDACTED]")
      text = text.gsub(CREDENTIAL_KEY_PATTERN) { "#{Regexp.last_match(:key)}#{Regexp.last_match(:sep)}[REDACTED]" }
      redact_home_directory(text)
    end

    # Replaces this process' own $HOME with `~` -- doesn't attempt every
    # possible username-bearing path shape (a different user's home
    # directory on a shared machine, Windows' `C:\Users\<name>`), only
    # the one this process can actually know for certain without
    # false-positiving on an unrelated path that happens to share a
    # substring.
    def redact_home_directory(text)
      home = ENV["HOME"] || ENV["USERPROFILE"]
      return text if home.nil? || home.empty?

      text.gsub(home, "~")
    end

    # Applied to the generic-token pattern *after* the more specific
    # label-based redactions above, and only ever called explicitly --
    # kept separate from #redact's default pipeline since it's
    # deliberately the broadest, most false-positive-prone check (a long
    # commit SHA, a UUID, a base64-encoded but entirely non-secret blob
    # would all match) and callers that already know their message is
    # exception-text from arbitrary, untrusted third-party code (a
    # workspace's own Gemfile/initializer) are the ones that most need
    # this extra net.
    def redact_generic_tokens(text)
      text.gsub(GENERIC_TOKEN_PATTERN, "[REDACTED]")
    end
  end
end
