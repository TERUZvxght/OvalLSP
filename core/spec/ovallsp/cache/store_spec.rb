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

  describe "#clear" do
    it "removes every previously saved entry" do
      Dir.mktmpdir do |cache_dir|
        store = described_class.new(cache_dir: cache_dir)
        store.save("/a.rb", summary)

        store.clear

        expect(store.load("/a.rb")).to be_nil
      end
    end
  end
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

    def scope_for(root, name, workspace_path)
      dir = File.join(root, name)
      FileUtils.mkdir_p(dir)
      described_class.mark_workspace(dir, workspace_path)
      dir
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

    it "removes a workspace whose directory no longer exists" do
      Dir.mktmpdir do |root|
        gone = File.join(root, "..", "ovallsp-vanished-#{Process.pid}")
        FileUtils.mkdir_p(gone)
        vanished = scope_for(root, "vanished", gone)
        generation(vanished, "g", 1)
        FileUtils.remove_entry(gone)
        current = generation(scope_for(root, "mine", root), "current", 0)

        described_class.prune_generations(cache_root: root, current: current, keep: 8)

        expect(Dir.exist?(vanished)).to be(false)
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
        current = generation(scope_for(root, "mine", root), "current", 0)

        described_class.prune_generations(cache_root: root, current: current, keep: 8)

        expect(Dir.exist?(legacy)).to be(false)
      end
    end

    it "leaves a root it cannot read alone rather than raising" do
      expect { described_class.prune_generations(cache_root: "/nonexistent-cache-root", current: "/x", keep: 2) }
        .not_to raise_error
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
