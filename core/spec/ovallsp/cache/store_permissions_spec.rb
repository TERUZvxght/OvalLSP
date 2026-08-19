# frozen_string_literal: true

require "tmpdir"

# `vscode/PRIVACY.md` says the cache holds method bodies from the user's
# own source, verbatim. It was created with `FileUtils.mkdir_p` and no
# mode, so it took the process umask -- 0755 in practice, world-readable.
# On any shared or multi-account machine that hands one user's source to
# every other one.
#
# The inconsistency is what dates it: `Observation::Runner` already
# writes its temporary evidence through `Tempfile`, which is owner-only,
# so the project's own standard for this data is stricter than what the
# long-lived copy of it got.
#
# Nothing about this is in section 0. It is axis A -- what shipping a
# product to other people makes you responsible for -- and it is done for
# that reason alone.
RSpec.describe "Ovallsp::Cache::Store directory permissions" do
  def summary
    Ovallsp::Index::FileSummary.new(uri: "file:///a.rb", content_hash: "abc", document_version: nil,
                                    declarations: [], diagnostics: [])
  end

  def mode_of(path) = File.stat(path).mode & 0o777

  it "creates the generation directory owner-only" do
    Dir.mktmpdir do |root|
      cache_dir = File.join(root, "scope", "generation")

      Ovallsp::Cache::Store.new(cache_dir: cache_dir)

      expect(mode_of(cache_dir)).to eq(0o700)
    end
  end

  it "creates the workspace scope directory owner-only" do
    Dir.mktmpdir do |root|
      scope = File.join(root, "scope")

      Ovallsp::Cache::Store.mark_workspace(scope, "/some/workspace")

      expect(mode_of(scope)).to eq(0o700)
    end
  end

  # The entries themselves, not only the directory that holds them. A
  # 0700 directory already denies traversal, but a file written 0644
  # inside it becomes readable the moment the directory's mode is
  # loosened by anything else -- and the marker records a real path from
  # the user's machine.
  it "writes cache entries and the workspace marker owner-only" do
    Dir.mktmpdir do |root|
      scope = File.join(root, "scope")
      cache_dir = File.join(scope, "generation")
      Ovallsp::Cache::Store.mark_workspace(scope, "/some/workspace")
      store = Ovallsp::Cache::Store.new(cache_dir: cache_dir)
      store.save("/a.rb", summary)

      entry = Dir.glob(File.join(cache_dir, "*.cache")).first
      marker = File.join(scope, Ovallsp::Cache::Store::WORKSPACE_MARKER)

      expect(mode_of(marker)).to eq(0o600)
      expect(mode_of(entry)).to eq(0o600)
    end
  end
end
