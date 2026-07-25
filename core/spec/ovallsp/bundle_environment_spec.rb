# frozen_string_literal: true

require "tmpdir"

RSpec.describe Ovallsp::BundleEnvironment do
  # A plain Hash standing in for a polluted ENV -- never mutates real
  # ENV (see the module's own docs for why: Server is multi-threaded, and
  # a global ENV mutation would race any other thread reading ENV during
  # the same window). Every method under test accepts `env:` precisely so
  # this is possible.
  # The actual directory `Bundler.method(:unbundled_env).source_location`
  # resolves to on *this* machine -- used (not a hardcoded guess) so the
  # RUBYLIB fixture below genuinely exercises #strip_core_bundler_lib's
  # removal branch rather than silently never matching anything (found by
  # an independent review: an earlier fixture's RUBYLIB entry didn't
  # match the real bundler lib dir on any machine, so the whole suite
  # stayed green even with the removal logic completely deleted).
  def real_bundler_lib_dir
    File.dirname(Bundler.method(:unbundled_env).source_location.first)
  end

  def polluted_env(overrides = {})
    {
      "BUNDLE_GEMFILE" => "/repo/core/Gemfile",
      "BUNDLE_PATH" => "/tmp/core-only-bundle",
      "BUNDLE_APP_CONFIG" => "/tmp/core-only-config",
      "BUNDLE_BIN_PATH" => "/repo/core/.bundle/bin/bundle",
      # A real absolute path in practice (what `bundle exec` actually sets
      # it to -- RubyGems' own bootstrap auto-`require`s this exact path
      # unconditionally, independent of RUBYOPT's own -r flags), not a
      # boolean-ish flag; the exact value doesn't matter for what's tested
      # here (only that the key gets nil'd), but kept realistic since a
      # spec/integration/real_rails_spec.rb regression was found the hard
      # way from treating this as a mere flag.
      "BUNDLER_SETUP" => "/repo/core/.bundle/bundler/setup",
      "GEM_HOME" => "/tmp/core-only-bundle/ruby/3.4.0",
      "GEM_PATH" => "",
      "RUBYOPT" => "-r/repo/core/.bundle/bundler/setup",
      "RUBYLIB" => "#{real_bundler_lib_dir}#{File::PATH_SEPARATOR}/some/other/legit/entry",
      "PATH" => "/usr/bin:/bin",
      "HOME" => "/Users/example"
    }.merge(overrides)
  end

  # Regression A: Core's own BUNDLE_PATH/BUNDLE_APP_CONFIG must be
  # unset (nil, not merely absent -- see the module's own docs on why
  # Process.spawn needs an explicit nil) for the child, regardless of
  # what Core's own process currently has set.
  it "unsets BUNDLE_PATH and BUNDLE_APP_CONFIG (regression A)" do
    env = described_class.base(env: polluted_env)

    expect(env["BUNDLE_PATH"]).to be_nil
    expect(env.key?("BUNDLE_PATH")).to be(true) # present-with-nil, not merely absent
    expect(env["BUNDLE_APP_CONFIG"]).to be_nil
    expect(env.key?("BUNDLE_APP_CONFIG")).to be(true)
  end

  # Regression B: even when the parent's BUNDLE_GEMFILE points at Core's
  # own Gemfile, #for_workspace must override it with the *workspace's*
  # own Gemfile, not merely unset it (a bare unset would fall back to
  # searching upward from chdir for the nearest Gemfile, which is fragile
  # -- see #for_workspace's own docs).
  it "overrides BUNDLE_GEMFILE with the workspace's own Gemfile, not Core's (regression B)" do
    Dir.mktmpdir do |workspace_root|
      File.write(File.join(workspace_root, "Gemfile"), "source \"https://rubygems.org\"\n")

      env = described_class.for_workspace(workspace_root, env: polluted_env)

      expect(env["BUNDLE_GEMFILE"]).to eq(File.join(workspace_root, "Gemfile"))
      expect(env["BUNDLE_GEMFILE"]).not_to eq("/repo/core/Gemfile")
    end
  end

  # Regression C: a parent RUBYOPT carrying "-rbundler/setup" (exactly
  # what `bundle exec` injects) must not survive into the child's RUBYOPT
  # -- but any *other* RUBYOPT content the parent legitimately had must
  # not be destroyed either.
  it "strips only the bundler/setup flag from RUBYOPT, preserving other options (regression C)" do
    env = described_class.base(env: polluted_env("RUBYOPT" => "-W2 -r/repo/core/.bundle/bundler/setup -rdebug"))

    rubyopt_flags = env["RUBYOPT"].split(" ")
    expect(rubyopt_flags).not_to include(a_string_ending_with("bundler/setup"))
    expect(rubyopt_flags).to include("-W2", "-rdebug")
  end

  it "leaves RUBYOPT untouched when it never had bundler/setup in the first place" do
    env = described_class.base(env: polluted_env("RUBYOPT" => "-W2"))

    expect(env["RUBYOPT"]).to eq("-W2")
  end

  it "does not touch RUBYOPT at all when the source env never had it set" do
    source = polluted_env
    source.delete("RUBYOPT")

    env = described_class.base(env: source)

    expect(env.key?("RUBYOPT")).to be(false)
  end

  # GEM_HOME/GEM_PATH: RubyGems-level, not Bundler-level, but `bundle
  # exec` sets them as a side effect of relaunching inside its own Bundle
  # context -- found missing from Bundler.unbundled_env entirely (it only
  # ever handles BUNDLE_*-prefixed keys), and specifically what let
  # spec/integration/real_rails_spec.rb's own fixture `bundle install
  # --local` fail even after BUNDLE_PATH itself was correctly unset.
  it "unsets GEM_HOME and GEM_PATH" do
    env = described_class.base(env: polluted_env)

    expect(env["GEM_HOME"]).to be_nil
    expect(env.key?("GEM_HOME")).to be(true)
    expect(env["GEM_PATH"]).to be_nil
    expect(env.key?("GEM_PATH")).to be(true)
  end

  it "removes Bundler's own lib directory from RUBYLIB, and only that entry" do
    env = described_class.base(env: polluted_env)

    rubylib_entries = env["RUBYLIB"].split(File::PATH_SEPARATOR)
    expect(rubylib_entries).not_to include(real_bundler_lib_dir)
    expect(rubylib_entries).to include("/some/other/legit/entry")
  end

  it "leaves keys unrelated to Bundler/RubyGems entirely untouched (absent from the returned Hash)" do
    env = described_class.base(env: polluted_env)

    expect(env.key?("PATH")).to be(false)
    expect(env.key?("HOME")).to be(false)
  end

  it "is a no-op (empty Hash) when given an env with nothing Bundler-owned at all" do
    env = described_class.base(env: { "PATH" => "/usr/bin", "HOME" => "/Users/example" })

    expect(env).to eq({})
  end

  # Regression D/E (workspace-only gem visibility / Core-only gem
  # invisibility): verified end-to-end against a real spawned process in
  # spec/integration/real_rails_spec.rb, which needs an actual separate
  # Bundle graph with its own installed gems to prove anything -- nothing
  # meaningful to assert on at this pure-function level beyond "the
  # returned env correctly isolates BUNDLE_GEMFILE per #for_workspace's
  # own regression B above", already covered.

  # Regression F: #base/#for_workspace must be pure functions with no
  # shared mutable state -- two concurrent calls for two different
  # workspaces must never cross-contaminate each other's result. Note
  # (found by an independent review): this test detects a coarse-grained
  # shared-mutable-state regression (e.g. a memoized/cached result Hash
  # reused across calls) reliably, but is NOT a guaranteed catch-all for
  # every conceivable implementation that mutates global ENV -- a
  # sufficiently fine-grained race (no yield point inside the critical
  # section) can pass this test by chance under MRI's GIL even with a
  # genuinely racy implementation, the same class of false confidence
  # this project's own agent_supervisor_spec.rb history already
  # documents for a different race. This module's env: parameter design
  # (no global ENV mutation at all, ever) is what actually makes the bug
  # class impossible; this test is a real, non-vacuous regression check
  # for the specific "shared mutable Hash" shape, not a substitute for
  # that design guarantee.
  it "never cross-contaminates concurrent calls for different workspaces (regression F)" do
    Dir.mktmpdir do |workspace_a|
      Dir.mktmpdir do |workspace_b|
        File.write(File.join(workspace_a, "Gemfile"), "source \"https://rubygems.org\"\ngem \"a_only\"\n")
        File.write(File.join(workspace_b, "Gemfile"), "source \"https://rubygems.org\"\ngem \"b_only\"\n")

        results = Queue.new
        threads = 20.times.map do |i|
          Thread.new do
            workspace_root, expected_gemfile = i.even? ? [workspace_a, File.join(workspace_a, "Gemfile")] : [workspace_b, File.join(workspace_b, "Gemfile")]
            env = described_class.for_workspace(workspace_root, env: polluted_env)
            results << (env["BUNDLE_GEMFILE"] == expected_gemfile)
          end
        end
        threads.each { |t| t.join(5) }

        expect(threads).to all(satisfy { |t| !t.alive? })
        expect(Array.new(20) { results.pop(timeout: 1) }).to all(be(true))
      end
    end
  end

  it "never mutates the env Hash (or ENV) it was given" do
    source = polluted_env
    snapshot = source.dup

    described_class.for_workspace("/some/workspace", env: source)

    expect(source).to eq(snapshot)
  end

  describe ".for_workspace" do
    it "does not set BUNDLE_GEMFILE at all when the workspace has no Gemfile of its own" do
      Dir.mktmpdir do |workspace_root|
        env = described_class.for_workspace(workspace_root, env: polluted_env)

        expect(env["BUNDLE_GEMFILE"]).to be_nil
        expect(env.key?("BUNDLE_GEMFILE")).to be(true) # still unset, from #base
      end
    end
  end

  describe "with the real, live ENV (default env: ENV)" do
    it "produces a Hash usable as a Process.spawn env argument without raising" do
      expect { described_class.for_workspace(Dir.pwd) }.not_to raise_error
    end
  end
end
