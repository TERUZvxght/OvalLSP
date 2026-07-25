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
end
