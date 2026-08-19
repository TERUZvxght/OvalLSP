# frozen_string_literal: true

require "tmpdir"

# 0.2.5 made the cache owner-only, and an attack round found the claim
# larger than the change: only the scope being *opened* was tightened, so
# every other project's pre-0.2.5 scope kept 0755 directories and 0644
# entries indefinitely -- with method bodies in them, per PRIVACY.md. On
# a machine with ten projects, opening one made one of ten private.
#
# The sweep already walks every sibling scope on every launch to decide
# what to remove, so it is the one place that sees them all, and it costs
# a chmod per scope once.
RSpec.describe "Ovallsp::Cache::Store tightens caches it did not create" do
  def mode_of(path) = File.stat(path).mode & 0o777

  def legacy_scope(root, name, workspace)
    dir = File.join(root, name)
    FileUtils.mkdir_p(File.join(dir, "generation"))
    File.write(File.join(dir, Ovallsp::Cache::Store::WORKSPACE_MARKER), "#{workspace}\n")
    File.write(File.join(dir, "generation", "abc.cache"), "x")
    [dir, File.join(dir, "generation"), File.join(dir, "generation", "abc.cache")]
  end

  it "tightens another project's scope while sweeping, not only the one being opened" do
    Dir.mktmpdir do |root|
      other, other_gen, other_entry = legacy_scope(root, "other", root)
      [other, other_gen].each { |d| File.chmod(0o755, d) }
      File.chmod(0o644, other_entry)

      mine = File.join(root, "mine")
      Ovallsp::Cache::Store.mark_workspace(mine, root)
      current = File.join(mine, "generation")
      Ovallsp::Cache::Store.new(cache_dir: current)

      Ovallsp::Cache::Store.prune_generations(cache_root: root, current: current)

      expect(mode_of(other)).to eq(0o700)
      expect(mode_of(other_gen)).to eq(0o700)
      expect(mode_of(other_entry)).to eq(0o600)
    end
  end

  # The sweep must not start deleting things in order to tighten them,
  # and a scope it is holding under the absent-workspace grace is still a
  # scope whose contents are readable.
  it "tightens a scope it is deliberately keeping" do
    Dir.mktmpdir do |root|
      gone = File.join(root, "vanished-workspace")
      FileUtils.mkdir_p(gone)
      other, other_gen, = legacy_scope(root, "other", gone)
      FileUtils.remove_entry(gone)
      [other, other_gen].each { |d| File.chmod(0o755, d) }

      mine = File.join(root, "mine")
      Ovallsp::Cache::Store.mark_workspace(mine, root)
      current = File.join(mine, "generation")
      Ovallsp::Cache::Store.new(cache_dir: current)

      Ovallsp::Cache::Store.prune_generations(cache_root: root, current: current)

      expect(Dir.exist?(other)).to be(true)
      expect(mode_of(other)).to eq(0o700)
    end
  end
end
