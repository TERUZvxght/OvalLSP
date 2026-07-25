# frozen_string_literal: true

require "bundler"

module Ovallsp
  # Builds the environment Hash a child process must use to run inside a
  # *different* Bundler context than Core's own -- above all the Rails
  # Runtime Agent, which must always resolve gems via the target
  # workspace's own Gemfile, never Core's (Core and the analyzed Rails app
  # are two entirely separate Bundle graphs; Core has no business
  # deciding what the workspace's own bundle install looks like, and vice
  # versa).
  #
  # Two separate leaks make naive approaches insufficient here:
  #
  # 1. `Bundler.unbundled_env` returns a Hash with every `BUNDLE_`-prefixed
  #    key (and `BUNDLER_SETUP`) *deleted* -- literally absent from the
  #    returned Hash, not set to nil. `Process.spawn(env_hash, ...)`
  #    treats an *absent* key as "inherit unchanged from the parent
  #    process" and only a key present with an explicit `nil` value as
  #    "unset for the child". Passing `Bundler.unbundled_env` straight to
  #    `Process.spawn` therefore silently leaves every Bundler-owned
  #    variable inherited from Core's own (possibly isolated/non-default,
  #    e.g. a review-bundle script's temporary BUNDLE_PATH) environment.
  # 2. `GEM_HOME`/`GEM_PATH` are RubyGems-level, not Bundler-level, and
  #    `Bundler.unbundled_env` doesn't touch them at all -- but `bundle
  #    exec` itself sets them (redirecting `GEM_HOME` to wherever the
  #    active BUNDLE_PATH resolves to, and `GEM_PATH` to an explicit empty
  #    string, suppressing RubyGems' own default search locations
  #    entirely) as part of relaunching a subprocess inside its own
  #    Bundle context. A child meant to run against an entirely different
  #    Ruby installation's default gems inherits this and can no longer
  #    find them even though they're genuinely installed --
  #    `GEM_PATH=""` isn't "unset", it actively means "search nowhere but
  #    GEM_HOME".
  #
  # Both were found the same way: core's review-bundle process
  # deliberately runs `bundle install`/`bundle exec rspec` against a
  # throwaway BUNDLE_PATH to isolate Core's own gem install. Fixing only
  # the BUNDLE_*-prefixed leak (1) still left the Rails Runtime Agent
  # spawned by spec/integration/real_rails_spec.rb degrading to
  # :static_only -- `bundle install --local` inside the fixture could no
  # longer find its own already-installed rails/sqlite3/activerecord,
  # because GEM_PATH="" (inherited from Core's own `bundle exec`, per (2))
  # meant RubyGems refused to look anywhere else for them.
  #
  # Every public method takes an optional `env:` (defaulting to the real
  # `ENV`) specifically so this is unit-testable without ever mutating
  # global ENV -- a test can pass a plain Hash simulating a polluted
  # parent environment (BUNDLE_PATH pointing somewhere isolated, a wrong
  # BUNDLE_GEMFILE, RUBYOPT carrying "-rbundler/setup", ...) and assert on
  # the resulting spawn-env directly. Mutating real global ENV from test
  # code (even scoped via an `ensure`) was deliberately avoided: Server is
  # a multi-threaded LSP process that can spawn/reload several Runtime
  # Agents and route completions concurrently, and every method here is a
  # pure function returning a plain Hash for the caller to pass straight
  # to `Process.spawn`/`Open3.capture3` -- never a global ENV mutation
  # (no `Bundler.with_unbundled_env`, no `ENV[...] =`) that could race
  # another thread reading ENV during the same window.
  module BundleEnvironment
    module_function

    # Every ENV key, in `env`, that Bundler or RubyGems could plausibly
    # have set as a side effect of `bundle exec` relaunching a process
    # inside its own Bundle context -- computed from whatever `env` was
    # actually given (not memoized, and not tied to Bundler's own
    # internal ORIGINAL_ENV snapshot, which reflects whatever the
    # environment looked like when *this* process' Bundler instance
    # first loaded, not necessarily "before any Bundler-shaped variable
    # was ever set" if something upstream -- a review script, a parent
    # shell -- exported BUNDLE_PATH before Core's own `bundle exec` even
    # ran).
    def bundler_owned_keys(env: ENV)
      env.keys.select { |key| key.start_with?("BUNDLE_") || key == "BUNDLER_SETUP" } + gem_home_path_keys(env)
    end

    # GEM_HOME/GEM_PATH are nil'd only when they actually *look*
    # bundle-exec-derived, not unconditionally -- found by an independent
    # review: a version that always nil'd them (whenever present at all)
    # is correct on rbenv (where GEM_HOME is unset outside `bundle exec`)
    # but silently *breaks* chruby/RVM setups, which export their own
    # GEM_HOME/GEM_ROOT/GEM_PATH unconditionally, not just inside `bundle
    # exec` -- unconditional nil'ing would discard the very location a
    # chruby/RVM user's actual gems live in for the spawned child, which
    # is exactly the class of bug this whole module exists to fix, just
    # in the opposite direction. `GEM_PATH == ""` is unambiguous (only
    # `bundle exec` sets it to an explicit empty string; a version
    # manager has no reason to). Otherwise, only treat GEM_HOME as
    # bundle-exec-derived when it's actually nested under the live
    # BUNDLE_PATH -- exactly what `bundle exec` does
    # (GEM_HOME=<BUNDLE_PATH>/ruby/<version>) and a version manager's own
    # GEM_HOME independently would not be.
    def gem_home_path_keys(env)
      return %w[GEM_HOME GEM_PATH] if env["GEM_PATH"] == ""

      bundle_path = env["BUNDLE_PATH"]
      gem_home = env["GEM_HOME"]
      return %w[GEM_HOME GEM_PATH] if bundle_path && gem_home&.start_with?(bundle_path)

      []
    end

    # The exact `-r<path ending in bundler/setup>` flag(s) `bundle exec`
    # injects into RUBYOPT, and nothing else -- removed by exact
    # flag-shape match, not by clearing RUBYOPT wholesale, so any other
    # Ruby options a caller's own environment legitimately set (e.g.
    # `-W2`, `-rdebug`) survive untouched. Requires either the bare
    # relative form (`-rbundler/setup`) or a path ending in
    # `/bundler/setup` -- not just "ends with the substring
    # bundler/setup" -- so a hypothetical `-r/opt/gems/mybundler/setup`
    # (a different, unrelated `-r` flag that merely happens to share a
    # suffix) is never mistaken for Bundler's own injection (found by an
    # independent review).
    def strip_bundler_setup_flag(rubyopt)
      rubyopt.to_s.split(" ").reject do |flag|
        next false unless flag.start_with?("-r")

        value = flag[2..]
        value == "bundler/setup" || value.end_with?("/bundler/setup")
      end.join(" ")
    end

    # Core's own Bundler installation's lib directory (wherever *this*
    # process' `require "bundler"` actually resolved to) -- the one
    # RUBYLIB entry `bundle exec` adds that a child running a different
    # Bundle graph must not inherit. Removed by exact path match (mirrors
    # Bundler's own `unbundle_env`'s `rubylib.delete(__dir__)`), not by
    # clearing RUBYLIB wholesale, so unrelated entries (an rbenv/asdf
    # shim's own RUBYLIB contribution, say) survive untouched.
    def strip_core_bundler_lib(rubylib)
      bundler_lib_dir = File.dirname(Bundler.method(:unbundled_env).source_location.first)
      rubylib.to_s.split(File::PATH_SEPARATOR).reject { |path| path == bundler_lib_dir }.join(File::PATH_SEPARATOR)
    end

    # Explicit-nil overrides for every Bundler/RubyGems-owned key present
    # in `env` right now, plus RUBYOPT/RUBYLIB with Core's own Bundler
    # injection stripped out (not nil'd -- a child still needs whatever
    # *other* RUBYOPT/RUBYLIB content was legitimately there).
    #
    # Everything NOT covered above is deliberately absent from the
    # returned Hash, so `Process.spawn` leaves it untouched (inherited
    # from the caller's own process) -- e.g. PATH, HOME, a mise/asdf/rbenv
    # shim directory -- none of that is Bundler's concern, and this
    # module's job is narrowly "don't leak the source Bundle graph", not
    # "sanitize the child's entire environment".
    def base(env: ENV)
      overrides = {}
      bundler_owned_keys(env: env).each { |key| overrides[key] = nil }
      overrides["RUBYOPT"] = strip_bundler_setup_flag(env["RUBYOPT"]) if env.key?("RUBYOPT")
      overrides["RUBYLIB"] = strip_core_bundler_lib(env["RUBYLIB"]) if env.key?("RUBYLIB")
      overrides
    end

    # The environment a child process should use to run entirely inside
    # `workspace_root`'s own Bundler context. `BUNDLE_GEMFILE` is pointed
    # explicitly at the workspace's own Gemfile when it has one -- without
    # this, a `bundle exec` launched with no BUNDLE_GEMFILE at all falls
    # back to searching *upward* from `chdir` for the nearest Gemfile,
    # which happens to still find the workspace's own in the common case
    # but is fragile (a workspace with no Gemfile of its own, nested
    # inside a monorepo that has one, would silently pick up the wrong
    # one) and worth being explicit about rather than relying on.
    def for_workspace(workspace_root, env: ENV)
      result = base(env: env)
      gemfile = File.join(workspace_root, "Gemfile")
      result["BUNDLE_GEMFILE"] = gemfile if File.file?(gemfile)
      result
    end
  end
end
