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
    # The Bundler-owned keys that do NOT match the `BUNDLE_`-prefix check
    # below, because they're spelled `BUNDLER_` (position 6 is "R", not
    # "_"). Bundler's own
    # `Bundler::EnvironmentPreserver::BUNDLER_KEYS` is the authoritative
    # list of every variable `bundle exec` takes ownership of, and
    # spec/ovallsp/bundle_environment_spec.rb pins this constant against
    # it, so a future Bundler introducing another `BUNDLER_`-spelled
    # variable fails Core's own suite loudly instead of silently
    # reintroducing this leak one variable at a time (found by an
    # independent review, round 3: `BUNDLER_SETUP` had been special-cased
    # individually and `BUNDLER_VERSION` -- set by `bundle exec` at
    # bundler/shared_helpers.rb's `set_env "BUNDLER_VERSION"` -- was
    # simply missed).
    #
    # `BUNDLER_VERSION` leaking is not cosmetic: Bundler's own
    # self-manager treats a set `BUNDLER_VERSION` as "an explicit version
    # was requested, don't auto-switch"
    # (`SelfManager#autoswitching_applies?` is literally
    # `ENV["BUNDLER_VERSION"].nil? && ...`). With Core's own version
    # leaked in, the Agent's `bundle exec` silently loses the
    # auto-restart-under-the-version-your-Gemfile.lock-names behaviour, so
    # a workspace whose `Gemfile.lock` says `BUNDLED WITH 2.5.11` gets its
    # bundle resolved by whatever Bundler *Core* happens to run under
    # instead -- the exact "the Agent must run in the target workspace's
    # own Bundler context, never Core's" invariant this module exists to
    # enforce.
    BUNDLER_PREFIXED_KEYS = %w[BUNDLER_SETUP BUNDLER_VERSION].freeze

    # Bundler's `BUNDLER_ORIG_*` bookkeeping (`BUNDLER_ORIG_PATH`,
    # `BUNDLER_ORIG_GEM_HOME`, ...) is deliberately NOT nil'd, and that is
    # a considered decision rather than an oversight (documented here
    # because the naive "it's Bundler-owned, unset it" reflex actively
    # makes things worse). Those keys are Bundler's snapshot of what the
    # environment looked like *before* any `bundle exec` ran, and the
    # child's own Bundler only records a fresh snapshot for keys not
    # already present (`env[prefix + key] ||= ...` in
    # Bundler::EnvironmentPreserver#backup). Nil'ing them makes the Agent
    # snapshot Core's *already-modified* PATH/RUBYLIB as if it were the
    # pristine original, so any `Bundler.with_unbundled_env` /
    # `Bundler.original_env` inside the Rails app (a very common way for
    # apps to shell out) would restore Core's bundle-exec PATH rather than
    # the real pre-Bundler one. Inheriting Core's snapshot is strictly
    # closer to correct: Core and the workspace run on the same machine,
    # so "the environment before Bundler touched anything" is the same
    # environment for both.
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
      env.keys.select { |key| key.start_with?("BUNDLE_") || BUNDLER_PREFIXED_KEYS.include?(key) } +
        gem_home_path_keys(env)
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
    #
    # Only returns a key name that's actually present in `env` (matching
    # every other method here, per `base`'s own docstring) -- and the
    # BUNDLE_PATH/GEM_HOME nesting check compares against a real path
    # boundary, not a bare string prefix -- both found by an independent
    # review: a version of this method could return "GEM_HOME" even when
    # `env` never had that key at all (harmless at runtime -- nil'ing an
    # already-unset variable -- but a real invariant violation), and
    # `gem_home.start_with?(bundle_path)` alone would misclassify e.g.
    # BUNDLE_PATH=/tmp/core + GEM_HOME=/tmp/core-other/ruby/3.4.0 (a
    # string prefix, but not a path ancestor) as bundle-exec-derived --
    # exactly the false-positive shape #strip_bundler_setup_flag was
    # already hardened against, just not carried over to this sibling
    # method in the same original fix.
    def gem_home_path_keys(env)
      candidates =
        if env["GEM_PATH"] == ""
          %w[GEM_HOME GEM_PATH]
        else
          bundle_path = env["BUNDLE_PATH"]
          gem_home = env["GEM_HOME"]
          bundle_path && gem_home&.start_with?("#{bundle_path.chomp("/")}/") ? %w[GEM_HOME GEM_PATH] : []
        end

      candidates.select { |key| env.key?(key) }
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

    # The search-path variables `bundle exec` prepends its own entries to
    # (Bundler::SharedHelpers#set_path unshifts "#{Bundler.bundle_path}/bin"
    # onto PATH; Bundler::Runtime#setup_manpath unshifts every activated
    # gem's own man/ directory onto MANPATH). Both are listed in Bundler's
    # own `EnvironmentPreserver::BUNDLER_KEYS` -- i.e. Bundler itself
    # considers them variables it takes ownership of, and its own
    # `unbundled_env` restores them from the pre-Bundler snapshot for
    # exactly that reason.
    #
    # Found by an independent review (round 4). An earlier version of this
    # module documented PATH as "none of that is Bundler's concern" and
    # left it fully inherited, which is simply not true of a process
    # running under `bundle exec`: with Core running under an isolated
    # BUNDLE_PATH (the review-bundle script this whole task exists for),
    # Core's own `<bundle path>/bin` is the FIRST entry on PATH and was
    # inherited verbatim by the Agent. That directory holds Core's own
    # gems' executables (rspec, rbs, ovallsp, ...), and `Process.spawn`
    # resolves a bare command name through the env Hash's own PATH -- so
    # any executable the target app shells out to whose name Core's bundle
    # also provides, but the app's own bundle does not, resolved to Core's
    # copy instead of the machine's. Worse, those binstubs are then broken
    # by this module's own (correct) GEM_HOME/GEM_PATH nil'ing, so the app
    # sees "can't find executable rspec" for a gem that is genuinely
    # installed system-wide.
    SEARCH_PATH_KEYS = %w[PATH MANPATH].freeze

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

    # PATH/MANPATH with the entries `bundle exec` derived from Core's own
    # bundle removed, and nothing else -- surgical removal by path
    # containment, exactly like #strip_core_bundler_lib and
    # #strip_bundler_setup_flag, never a wholesale restore of Bundler's
    # `BUNDLER_ORIG_PATH` snapshot (that would also discard any legitimate
    # PATH entry the caller's own environment added, e.g. an editor
    # launching Core with an augmented PATH).
    #
    # Gated on the *same* "does GEM_HOME actually look bundle-exec-derived"
    # classification #gem_home_path_keys already uses, so it cannot misfire
    # on chruby/RVM (whose GEM_HOME is exported unconditionally, and whose
    # `<gem home>/bin` is the real location of that user's own gem
    # executables -- see #gem_home_path_keys' own docs for the round-1
    # finding). Under any env where this fires, GEM_HOME/GEM_PATH are
    # already being nil'd by the same predicate, so this can never be the
    # *first* thing to go wrong.
    #
    # Only emitted when something was actually removed: a PATH carrying
    # nothing of Core's bundle stays absent from the returned Hash (plain
    # inheritance), per #base's own "everything else is deliberately
    # untouched" contract.
    def strip_bundle_exec_search_paths(env)
      gem_home = bundle_exec_gem_home(env)
      return {} if gem_home.nil?

      SEARCH_PATH_KEYS.each_with_object({}) do |key, result|
        next unless env.key?(key)

        cleaned = reject_paths_under(env[key], gem_home)
        result[key] = cleaned unless cleaned == env[key]
      end
    end

    # The gem home `bundle exec` itself derived from the active BUNDLE_PATH
    # (Bundler sets GEM_HOME to `Bundler.bundle_path`, and PATH's injected
    # entry is that same directory's `bin`), or nil when this env's GEM_HOME
    # doesn't look bundle-exec-derived at all.
    # A degenerate GEM_HOME ("" or "/") is explicitly not treated as a
    # bundle path: `"".chomp("/") + "/"` and `"/".chomp("/") + "/"` are both
    # the prefix "/", which #reject_paths_under would then match against
    # *every* absolute entry, emptying the child's PATH entirely and leaving
    # it unable to resolve `bundle` at all -- turning a leak fix into a total
    # outage. Neither value can name a real bundle path, so classify as
    # "not bundle-exec-derived" and leave PATH/MANPATH alone.
    def bundle_exec_gem_home(env)
      return nil unless gem_home_path_keys(env).include?("GEM_HOME")

      gem_home = env["GEM_HOME"].to_s
      gem_home.chomp("/").empty? ? nil : gem_home
    end

    # `value` (a PATH_SEPARATOR-joined search path) with every entry that is
    # `root` itself, or nested under it, removed. Compares against a real
    # path boundary rather than a bare string prefix (the round-2 finding
    # for #gem_home_path_keys, carried over here deliberately), and splits
    # with a -1 limit so a trailing empty entry -- meaningful in both PATH
    # ("the current directory") and MANPATH ("append the system default")
    # -- survives untouched.
    def reject_paths_under(value, root)
      prefix = "#{root.chomp("/")}/"
      value.to_s
           .split(File::PATH_SEPARATOR, -1)
           .reject { |entry| entry == root || entry.start_with?(prefix) }
           .join(File::PATH_SEPARATOR)
    end

    # Explicit-nil overrides for every Bundler/RubyGems-owned key present
    # in `env` right now, plus RUBYOPT/RUBYLIB with Core's own Bundler
    # injection stripped out (not nil'd -- a child still needs whatever
    # *other* RUBYOPT/RUBYLIB content was legitimately there).
    #
    # ...plus PATH/MANPATH with only the entries `bundle exec` derived from
    # Core's own bundle removed (see SEARCH_PATH_KEYS -- these are Bundler's
    # own, per its `EnvironmentPreserver::BUNDLER_KEYS`, and were previously
    # mis-documented here as "not Bundler's concern").
    #
    # Everything NOT covered above is deliberately absent from the
    # returned Hash, so `Process.spawn` leaves it untouched (inherited
    # from the caller's own process) -- e.g. HOME, a mise/asdf/rbenv shim
    # directory, the rest of PATH -- none of that is Bundler's concern, and
    # this module's job is narrowly "don't leak the source Bundle graph",
    # not "sanitize the child's entire environment".
    def base(env: ENV)
      overrides = {}
      bundler_owned_keys(env: env).each { |key| overrides[key] = nil }
      overrides["RUBYOPT"] = strip_bundler_setup_flag(env["RUBYOPT"]) if env.key?("RUBYOPT")
      overrides["RUBYLIB"] = strip_core_bundler_lib(env["RUBYLIB"]) if env.key?("RUBYLIB")
      overrides.merge(strip_bundle_exec_search_paths(env))
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
