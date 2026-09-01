# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# What every Core launch pays before it answers anything.
#
# `#prune_workspaces` runs on each launch and calls `.tighten_tree` on
# **every scope in the cache root** — and `#tighten_tree` globs
# `**/*` under each. Its own comment says "the cost is a handful of
# chmods per launch and not a full tree walk", and that is true of one
# scope and false of the sweep that calls it once per scope.
#
# Measured on the author's real cache: 26,397 scopes, 282,805 entries,
# **8.58 seconds** — paid on every start, before the first keystroke can
# be answered. A cache grows one scope per workspace per generation, so
# this gets worse the longer the extension is used.
#
# Counted rather than timed: `no_wall_clock_thresholds_spec` exists
# because a timing assertion measures the machine. The number that
# matters is how many paths the sweep touches.
RSpec.describe "what a launch pays to the cache sweep" do
  # One scope per workspace per generation, each holding a few entries —
  # the shape a real cache root has.
  def build_cache(root, scopes:, entries_per_scope:)
    scopes.times do |i|
      scope = File.join(root, "workspaces", format("scope-%04d", i))
      FileUtils.mkdir_p(scope)
      File.write(File.join(scope, ".ovallsp-workspace"), "/some/workspace/#{i}")
      entries_per_scope.times { |j| File.write(File.join(scope, "entry-#{j}.bin"), "x") }
    end
  end

  def paths_touched(root)
    touched = 0
    allow(Ovallsp::Cache::Store).to receive(:tighten).and_wrap_original do |original, *args|
      touched += 1
      original.call(*args)
    end
    Ovallsp::Cache::Store.prune_workspaces(root, File.join(root, "workspaces", "scope-0000", "x"))
    touched
  end

  # **The second launch, not the first.** The first still walks every
  # scope on the machine -- that is the guarantee the walk exists for,
  # and 0.2.5's modes have to reach a project that is never opened.
  # What was wrong is that the *second* launch walked it again, and so
  # did every launch after.
  it "does not walk every scope again on the next launch" do
    Dir.mktmpdir do |root|
      build_cache(root, scopes: 40, entries_per_scope: 5)
      Ovallsp::Cache::Store.prune_workspaces(root, File.join(root, "workspaces", "scope-0000", "x"))

      touched = paths_touched(root)

      # 40 scopes x (1 scope dir + 2 markers + 5 entries) = 320 before
      # the fix, on every launch. After it, only the scope being opened.
      expect(touched).to be < 100,
                         "the sweep touched #{touched} paths across 40 scopes; on a real cache " \
                         "(26,397 scopes, 282,805 entries) that measured 8.58 seconds per launch"
    end
  end

  # The guarantee the sweep exists for, which the fix must not lose.
  it "still tightens the scope being opened" do
    Dir.mktmpdir do |root|
      build_cache(root, scopes: 3, entries_per_scope: 2)
      scope = File.join(root, "workspaces", "scope-0000")
      entry = File.join(scope, "entry-0.bin")
      File.chmod(0o644, entry)
      File.chmod(0o755, scope)

      Ovallsp::Cache::Store.prune_workspaces(root, File.join(scope, "x"))

      expect(format("%o", File.stat(scope).mode & 0o777)).to eq("700")
      expect(format("%o", File.stat(entry).mode & 0o777)).to eq("600")
    end
  end

  # **The marker must not touch the scope's mtime.** Pruning ages an
  # abandoned scope by that mtime, so a file written into every scope on
  # the first launch made all of them look freshly used and nothing was
  # ever pruned again -- a cache that only grows, which is a worse
  # failure than the walk this change removes.
  #
  # Found by `store_spec`'s pre-0.2.1 example, which ages a directory by
  # two days and expects it gone. Pinned here as well, next to the
  # change that caused it, because that example is about pruning and
  # would not tell the next reader why.
  it "leaves the scope's mtime alone while marking it" do
    Dir.mktmpdir do |root|
      build_cache(root, scopes: 2, entries_per_scope: 1)
      scope = File.join(root, "workspaces", "scope-0001")
      aged = Time.now - (2 * 24 * 60 * 60)
      File.utime(aged, aged, scope)

      Ovallsp::Cache::Store.prune_workspaces(root, File.join(root, "workspaces", "scope-0000", "x"))

      expect(File.mtime(scope).to_i).to eq(aged.to_i),
                                        "marking the scope reset its mtime, so pruning will never age it out"
    end
  end
end
