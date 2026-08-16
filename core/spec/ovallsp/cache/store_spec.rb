# frozen_string_literal: true

require "tmpdir"

RSpec.describe Ovallsp::Cache::Store do
  def summary(uri: "file:///a.rb", content_hash: "abc")
    Ovallsp::Index::FileSummary.new(uri: uri, content_hash: content_hash, document_version: nil, declarations: [],
                                   diagnostics: [])
  end

  it "returns nil for a path never saved" do
    Dir.mktmpdir do |cache_dir|
      store = described_class.new(cache_dir: cache_dir)

      expect(store.load("/a.rb")).to be_nil
    end
  end

  it "round-trips a FileSummary through #save/#load" do
    Dir.mktmpdir do |cache_dir|
      store = described_class.new(cache_dir: cache_dir)
      sig = summary

      store.save("/a.rb", sig)

      expect(store.load("/a.rb")).to eq(sig)
    end
  end

  it "keeps separate paths' entries independent" do
    Dir.mktmpdir do |cache_dir|
      store = described_class.new(cache_dir: cache_dir)
      store.save("/a.rb", summary(uri: "file:///a.rb", content_hash: "a"))
      store.save("/b.rb", summary(uri: "file:///b.rb", content_hash: "b"))

      expect(store.load("/a.rb").content_hash).to eq("a")
      expect(store.load("/b.rb").content_hash).to eq("b")
    end
  end

  it "returns nil for a corrupted cache file instead of raising" do
    Dir.mktmpdir do |cache_dir|
      store = described_class.new(cache_dir: cache_dir)
      store.save("/a.rb", summary)

      # Simulate corruption -- a truncated/garbled write, or a file from
      # an incompatible Marshal format version.
      entry = Dir.glob(File.join(cache_dir, "*.cache")).first
      File.write(entry, "not actually marshaled data")

      expect { store.load("/a.rb") }.not_to raise_error
      expect(store.load("/a.rb")).to be_nil
    end
  end

  it "returns nil rather than raising when the cache directory itself is unusable" do
    store = described_class.new(cache_dir: "/nonexistent-parent-dir-#{Process.pid}/ovallsp-cache")

    expect { store.save("/a.rb", summary) }.not_to raise_error
    expect(store.load("/a.rb")).to be_nil
  end

  it "writes atomically -- no partial/temp file is left behind after a successful save" do
    Dir.mktmpdir do |cache_dir|
      store = described_class.new(cache_dir: cache_dir)

      store.save("/a.rb", summary)

      expect(Dir.glob(File.join(cache_dir, "*.tmp.*"))).to be_empty
      expect(Dir.glob(File.join(cache_dir, "*.cache")).size).to eq(1)
    end
  end

  describe "memory bounds (Task 021)" do
    it "prunes the oldest entries once the entry count exceeds max_entries" do
      Dir.mktmpdir do |cache_dir|
        store = described_class.new(cache_dir: cache_dir, max_entries: 3)

        # #save's own auto-prune is only sampled with probability 1/64
        # (`rand(64).zero?`) precisely so it's cheap to call on every
        # save -- but that same randomness made this test flaky: on
        # roughly 1 run in 16 (4 saves x 1/64), it fired mid-setup,
        # before any of a/b/c had been deliberately backdated below, and
        # pruned by *filesystem* mtime -- which, with all four entries
        # written within the same test in quick succession, ties or
        # near-ties arbitrarily, sometimes deleting one of a/b/c early
        # and crashing the explicit File.utime backdating below with
        # ENOENT (found by a 10x flakiness-check loop; unrelated to
        # Task 022.2's own Bundler-isolation work, which that loop was
        # actually run to verify). Stubbing only the `rand(64)` call
        # (not `rand(1_000_000)`, still used unmodified for temp-file
        # naming) makes this test's own explicit
        # `store.send(:prune_if_over_bound)` below the sole source of
        # pruning, without weakening what it actually asserts.
        allow(store).to receive(:rand).with(64).and_return(1)
        allow(store).to receive(:rand).with(1_000_000).and_call_original

        store.save("/a.rb", summary(uri: "file:///a.rb", content_hash: "a"))
        store.save("/b.rb", summary(uri: "file:///b.rb", content_hash: "b"))
        store.save("/c.rb", summary(uri: "file:///c.rb", content_hash: "c"))
        store.save("/d.rb", summary(uri: "file:///d.rb", content_hash: "d"))

        # Filesystem mtime resolution (as coarse as 1s on some
        # filesystems) can't be relied on to distinguish four saves that
        # all happened within the same test -- back-date the older
        # entries explicitly so pruning has an unambiguous "oldest" to
        # pick, matching what real usage (files touched minutes/hours
        # apart) would naturally already have.
        %w[a b c].each_with_index do |letter, i|
          File.utime(Time.now - (10 - i), Time.now - (10 - i), File.join(cache_dir, "#{Digest::SHA256.hexdigest("/#{letter}.rb")}.cache"))
        end

        store.send(:prune_if_over_bound)

        expect(store.load("/a.rb")).to be_nil # oldest, pruned
        expect(store.load("/d.rb")).not_to be_nil # newest, kept
        expect(Dir.glob(File.join(cache_dir, "*.cache")).size).to eq(3)
      end
    end

    it "does not prune anything while at or under max_entries" do
      Dir.mktmpdir do |cache_dir|
        store = described_class.new(cache_dir: cache_dir, max_entries: 10)
        store.save("/a.rb", summary)
        store.send(:prune_if_over_bound)

        expect(store.load("/a.rb")).not_to be_nil
      end
    end
  end

  # `#clear` was removed in 0.2.2 and this is the example that covered it.
  # It had no caller in `lib/` or `scripts/` -- only this block -- and what
  # it did was `FileUtils.rm_rf` a path handed to the constructor, with
  # every error swallowed: the same shape as the sweep that emptied
  # `/Applications`, differing only in that nobody had yet aimed it wrong.
  # Keeping it would also have meant carving an exception into
  # `spec/meta/cache_removal_containment_spec.rb` for dead code, which
  # weakens that guard for the live code it exists to protect.
  #
  # If a "clear this workspace's cache" command is ever wanted, it wants a
  # method written for that caller, not this one re-attached.
  # Every component of the workspace digest -- a Ruby upgrade, a `bundle
  # install`, an RBS change, and now an OvalLSP release -- mints a *new*
  # generation directory and abandons the old one. Nothing ever removed
  # the abandoned ones: `DEFAULT_MAX_ENTRIES` prunes entries within one
  # directory and knows nothing about its siblings. Measured on a
  # developer machine before this: 28,643 directories, 2.8 GB.
  #
  # Adding the version to the key makes that unbounded growth a *release
  # cadence*, which is why the sweep lands with it rather than after it.
  # Pruning has to know a *generation* from a *workspace*, and the flat
  # layout could not: `Cache::Key.workspace_digest` folds the workspace
  # into the same digest as Ruby, Prism, `Gemfile.lock` and the OvalLSP
  # version, so every project was a sibling directory in one root,
  # indistinguishable from an abandoned generation of this one. Keeping
  # the eight most recently *written* siblings therefore deleted the warm
  # cache of the ninth project -- possibly one open in another window,
  # since a directory's mtime advances on write and not on read.
  #
  # So the layout nests: `<root>/<workspace>/<generation>`. Everything
  # pruned within a workspace belongs to that workspace, and the only
  # thing removed at the root is a workspace that no longer exists on
  # disk, which is a fact rather than a guess.
  describe ".prune_generations" do
    def generation(scope, name, age_days)
      dir = File.join(scope, name)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "e.cache"), "x")
      time = Time.now - (age_days * 24 * 60 * 60)
      File.utime(time, time, dir)
      dir
    end

    # `.mark_workspace` now runs *before* the generation directory is
    # created, so on a first launch there is nothing to write into. It
    # makes the directory itself; without that the write fails ENOENT into
    # the method's own rescue, the scope stays unmarked, and any other
    # window's sweep reads it as a pre-0.2.1 generation and removes it.
    it "creates the scope directory it is marking" do
      Dir.mktmpdir do |root|
        scope = File.join(root, "never-created")

        described_class.mark_workspace(scope, "/some/workspace")

        expect(File.file?(File.join(scope, described_class::WORKSPACE_MARKER))).to be(true)
      end
    end

    def scope_for(root, name, workspace_path)
      dir = File.join(root, name)
      FileUtils.mkdir_p(dir)
      described_class.mark_workspace(dir, workspace_path)
      dir
    end

    # How long ago this workspace was last *opened*. `.mark_workspace`
    # rewrites the marker on every launch, so its mtime is that; the scope
    # directory's own mtime is something else entirely (it advances when a
    # generation is minted), which is the distinction the two examples
    # below exist to hold apart.
    def last_opened(scope, days_ago)
      marker = File.join(scope, Ovallsp::Cache::Store::WORKSPACE_MARKER)
      time = Time.now - (days_ago * 24 * 60 * 60)
      File.utime(time, time, marker)
    end

    it "keeps the current generation however old it looks" do
      Dir.mktmpdir do |root|
        scope = scope_for(root, "w1", root)
        current = generation(scope, "current", 400)

        described_class.prune_generations(cache_root: root, current: current, keep: 1)

        expect(Dir.exist?(current)).to be(true)
      end
    end

    it "removes the least recently used generations of this workspace beyond the bound" do
      Dir.mktmpdir do |root|
        scope = scope_for(root, "w1", root)
        current = generation(scope, "current", 0)
        recent = generation(scope, "recent", 1)
        old = generation(scope, "old", 30)

        described_class.prune_generations(cache_root: root, current: current, keep: 2)

        expect(Dir.exist?(current)).to be(true)
        expect(Dir.exist?(recent)).to be(true)
        expect(Dir.exist?(old)).to be(false)
      end
    end

    # The finding this layout exists for.
    it "never removes another workspace's cache, however many there are" do
      Dir.mktmpdir do |root|
        Dir.mktmpdir do |other_workspace|
          mine = scope_for(root, "mine", root)
          theirs = scope_for(root, "theirs", other_workspace)
          generation(theirs, "warm", 90)
          current = generation(mine, "current", 0)

          described_class.prune_generations(cache_root: root, current: current, keep: 1)

          expect(Dir.exist?(File.join(theirs, "warm"))).to be(true)
        end
      end
    end

    # A missing directory is not proof the project is gone -- an unmounted
    # volume and a network share that is briefly away look exactly like a
    # deleted one -- so the scope is held for a grace period first. Aged
    # past it here, because what is being pinned is that it *is* removed
    # eventually, not that it survives.
    it "removes a workspace whose directory has been gone for longer than the grace period" do
      Dir.mktmpdir do |root|
        gone = File.join(root, "..", "ovallsp-vanished-#{Process.pid}")
        FileUtils.mkdir_p(gone)
        vanished = scope_for(root, "vanished", gone)
        generation(vanished, "g", 1)
        last_opened(vanished, 31)
        FileUtils.remove_entry(gone)
        current = generation(scope_for(root, "mine", root), "current", 0)

        described_class.prune_generations(cache_root: root, current: current, keep: 8)

        expect(Dir.exist?(vanished)).to be(false)
      end
    end

    # A scope another window created a moment ago and has not marked yet
    # looks exactly like a pre-0.2.1 flat generation. Removing it costs
    # that window its whole cache for the session, and its own marker
    # write then fails into a directory that is gone.
    #
    # Aged in opposite directions, like the absent-workspace pair: this
    # one is brand new and must survive, the one below is old and must
    # not. A fixture where both are the same age cannot tell a grace from
    # no grace.
    it "keeps an unmarked directory that was created moments ago" do
      Dir.mktmpdir do |root|
        racing = File.join(root, "another-window")
        FileUtils.mkdir_p(racing)
        current = generation(scope_for(root, "mine", root), "current", 0)

        described_class.prune_generations(cache_root: root, current: current, keep: 8)

        expect(Dir.exist?(racing)).to be(true)
      end
    end

    # And half an hour later it is still kept, which is what stops the
    # constant being set to anything positive. The window it covers is two
    # syscalls wide; the value is an hour because a *pre-0.2.1* generation
    # is the other thing this branch removes, and nothing has written one
    # since 0.2.1 shipped.
    it "keeps an unmarked directory half an hour old" do
      Dir.mktmpdir do |root|
        racing = File.join(root, "another-window")
        FileUtils.mkdir_p(racing)
        aged = Time.now - (30 * 60)
        File.utime(aged, aged, racing)
        current = generation(scope_for(root, "mine", root), "current", 0)

        described_class.prune_generations(cache_root: root, current: current, keep: 8)

        expect(Dir.exist?(racing)).to be(true)
      end
    end

    # Pre-0.2.1 generations sat directly in the root and can never be read
    # again -- the version in the key guarantees a miss -- so they are the
    # 2.8 GB that was measured and nothing else will ever reclaim them.
    it "removes a flat pre-0.2.1 generation directory" do
      Dir.mktmpdir do |root|
        legacy = File.join(root, "0123abc")
        FileUtils.mkdir_p(legacy)
        File.write(File.join(legacy, "e.cache"), "x")
        # Two days, an absolute figure rather than
        # `UNMARKED_SCOPE_GRACE + 60`. Aging relative to the constant makes
        # *any* positive value pass, which is the defect round 33 found for
        # `ABSENT_WORKSPACE_GRACE` and round 36 found here: setting this one
        # to one second left all 1,936 examples green.
        aged = Time.now - (2 * 24 * 60 * 60)
        File.utime(aged, aged, legacy)
        current = generation(scope_for(root, "mine", root), "current", 0)

        described_class.prune_generations(cache_root: root, current: current, keep: 8)

        expect(Dir.exist?(legacy)).to be(false)
      end
    end

    it "keeps a workspace that has only just become unreachable" do
      Dir.mktmpdir do |root|
        gone = File.join(root, "..", "ovallsp-unmounted-#{Process.pid}")
        FileUtils.mkdir_p(gone)
        away = scope_for(root, "away", gone)
        generation(away, "g", 1)
        FileUtils.remove_entry(gone)
        current = generation(scope_for(root, "mine", root), "current", 0)

        described_class.prune_generations(cache_root: root, current: current, keep: 8)

        expect(Dir.exist?(away)).to be(true)
      end
    end

    # The grace itself, not just its two boundaries. Both examples around
    # this one write the marker at *now*, so any positive value satisfies
    # them — round 33 set the constant to one second, which is the
    # pre-0.2.2 behaviour this release exists to change, and the file's
    # eighteen examples stayed green. Twenty-nine days is a length no
    # accidental value reaches.
    it "keeps a workspace that has been unreachable for four weeks" do
      Dir.mktmpdir do |root|
        gone = File.join(root, "..", "ovallsp-fourweeks-#{Process.pid}")
        FileUtils.mkdir_p(gone)
        away = scope_for(root, "away", gone)
        generation(away, "g", 1)
        last_opened(away, 29)
        FileUtils.remove_entry(gone)
        current = generation(scope_for(root, "mine", root), "current", 0)

        described_class.prune_generations(cache_root: root, current: current, keep: 8)

        expect(Dir.exist?(away)).to be(true)
      end
    end

    # The case the grace was written for, and the one it did not cover
    # until 0.2.2: a project on an external drive, opened this morning, on
    # a toolchain that has not changed in three months. The scope
    # directory's mtime is 90 days old because that is when its last
    # generation was minted; the *workspace* went away minutes ago. Aging
    # the two in opposite directions is what makes this example able to
    # fail -- reading either mtime alone answers a different question, and
    # only one of them is "has anyone opened this project lately".
    it "keeps a workspace opened today whose cache key last changed months ago" do
      Dir.mktmpdir do |root|
        gone = File.join(root, "..", "ovallsp-external-#{Process.pid}")
        FileUtils.mkdir_p(gone)
        away = scope_for(root, "away", gone)
        generation(away, "g", 90)
        stale = Time.now - (90 * 24 * 60 * 60)
        File.utime(stale, stale, away)
        last_opened(away, 0)
        FileUtils.remove_entry(gone)
        current = generation(scope_for(root, "mine", root), "current", 0)

        described_class.prune_generations(cache_root: root, current: current, keep: 8)

        expect(Dir.exist?(away)).to be(true)
      end
    end

    # `current` names a generation *inside* the unreadable root, which is
    # the only shape a caller can actually produce: Server#build_cache_store
    # derives `cache_dir` from `cache_root`. It used to read
    # `cache_root: "/nonexistent-cache-root", current: "/x"`, and that pair
    # cannot occur -- but it did reach `prune_generations_of("/", ...)`,
    # which is the sweep the example below now pins.
    it "leaves a root it cannot read alone rather than raising" do
      Dir.mktmpdir do |outside|
        root = File.join(outside, "nonexistent-cache-root")

        expect { described_class.prune_generations(cache_root: root, current: File.join(root, "w", "gen"), keep: 2) }
          .not_to raise_error
      end
    end

    # The defect this containment exists for, and the reason it is checked
    # where the removal happens rather than only at the entry point.
    #
    # `prune_generations_of` sweeps whatever directory it is handed, and it
    # was handed `File.dirname(current)`. A `current` outside `cache_root`
    # therefore aimed the sweep at a directory that has nothing to do with
    # this cache: with the old `current: "/x"` above, that directory was
    # `/`, and the sweep removed every top-level directory on the machine
    # except the most recently modified one -- `/Applications` first, and
    # `/Users` next had `remove_entry` not raised on a protected path
    # partway through. Nothing raised out of `.prune_generations`, because
    # it swallows every error, so this suite stayed green across a week of
    # deleting the developer's installed applications.
    it "sweeps nothing outside cache_root, whatever `current` points at" do
      Dir.mktmpdir do |outside|
        bystanders = (1..5).map do |i|
          File.join(outside, "bystander#{i}").tap { |dir| FileUtils.mkdir_p(dir) }
        end

        described_class.prune_generations(cache_root: File.join(outside, "cache-root"), current: File.join(outside, "x"),
                                          keep: 2)

        expect(bystanders.reject { |dir| Dir.exist?(dir) }).to be_empty
      end
    end

    it "removes nothing when the bound is not reached" do
      Dir.mktmpdir do |root|
        scope = scope_for(root, "mine", root)
        current = generation(scope, "current", 0)
        other = generation(scope, "other", 5)

        described_class.prune_generations(cache_root: root, current: current, keep: 8)

        expect(Dir.exist?(other)).to be(true)
      end
    end
  end
end
