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
    # (not just after a `key=` label). Case-insensitive: found by a
    # follow-up review round that only the exact capitalization `Bearer`
    # was ever matched, so a `bearer`/`BEARER` header value (common --
    # curl and several HTTP libraries normalize header names/values to
    # lowercase in their own logging) passed through completely
    # unredacted. The replacement text always reads "Bearer [REDACTED]"
    # regardless of the original casing -- redaction only needs to hide
    # the secret, not preserve exactly how the label was capitalized.
    BEARER_PATTERN = /\bBearer\s+[A-Za-z0-9\-._~+\/]+=*/i

    # `Authorization: Basic <base64>` -- previously a known, accepted gap
    # (BEARER_PATTERN had no counterpart for this shape). A 401 from an
    # HTTP client commonly echoes the request's own Authorization header
    # verbatim into its exception text, so this is a real, plausible leak
    # path, just a narrower one than the connection-string/bearer-token
    # cases (Basic-Auth-over-plain-HTTP is itself already a security
    # anti-pattern in whatever code produced it). Same base64/padding
    # character class as BEARER_PATTERN, since both carry base64-encoded
    # payloads.
    BASIC_AUTH_PATTERN = /\bBasic\s+[A-Za-z0-9\-._~+\/]+=*/i

    # `scheme://user:password@host` -- a DB connection string
    # (`postgres://user:pass@host/db`), a Redis URL, an HTTP Basic-Auth
    # URL, etc. Found missing by an independent review of this task: the
    # module's own docstring names "a DB connection string" as its
    # motivating example, but nothing here actually matched that shape
    # before this fix -- only an explicit `password=`-labeled assignment
    # was ever caught. The username is kept (useful for troubleshooting,
    # rarely secret on its own); only the password is redacted.
    #
    # The password group deliberately does NOT exclude "@"/"#" the way
    # an earlier version did -- a password containing either of those
    # characters (legal in practice, even if technically requiring
    # percent-encoding per RFC 3986) made that version either leak a
    # suffix of the real password (stopping at an embedded "@" and
    # treating the rest as host) or skip redacting the message entirely
    # (an embedded "#", found by a follow-up review round, meant no
    # `@`-terminated run of allowed characters existed at all, so the
    # whole pattern simply failed to match). Excluding only "/", "?",
    # and whitespace and relying on `+`'s default greedy backtracking
    # finds the *last* "@" before the next `/`/`?`/whitespace -- exactly
    # the delimiter between userinfo and host, however much `@`/`#` the
    # password itself contains.
    URL_USERINFO_PATTERN = %r{(?<prefix>[a-zA-Z][a-zA-Z0-9+.\-]*://)(?<user>[^:/?\s@]+):(?<password>[^/?\s]+)@}

    # High-confidence, low-false-positive vendor secret shapes -- unlike
    # GENERIC_TOKEN_PATTERN (below), these are specific enough to enable
    # by default without drowning ordinary log messages (commit SHAs,
    # content digests, UUIDs) in false positives. Also found missing by
    # the same review: a bare API key with no `key=`/`token=` label
    # immediately in front of it (e.g. straight from a third-party
    # client library's own exception message) previously passed through
    # completely unredacted.
    KNOWN_SECRET_PATTERN = %r{
      \bAKIA[0-9A-Z]{16}\b                              # AWS access key ID
      | \b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{10,}\b  # Stripe-style secret, publishable, restricted keys
      | \bgh[aoprsu]_[A-Za-z0-9]{20,}\b                  # GitHub personal-access, OAuth, app tokens
      | \bxox[baprs]-[A-Za-z0-9\-]{10,}\b                # Slack tokens
    }x

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
      text = text.gsub(BASIC_AUTH_PATTERN, "Basic [REDACTED]")
      text = text.gsub(URL_USERINFO_PATTERN) { "#{Regexp.last_match(:prefix)}#{Regexp.last_match(:user)}:[REDACTED]@" }
      text = text.gsub(KNOWN_SECRET_PATTERN, "[REDACTED]")
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
