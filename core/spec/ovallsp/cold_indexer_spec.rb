# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Ovallsp::ColdIndexer do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:parser_service) { Ovallsp::ParserService.new }
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:document_store) { Ovallsp::DocumentStore.new }

  def write(dir, relative_path, content)
    full = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  def run_indexer(root)
    described_class.new(
      root: root, parser_service: parser_service, workspace_index: workspace_index,
      document_store: document_store, logger: logger
    ).run
  end

  def class_declared?(name)
    !workspace_index.find_by_simple_name(name).empty?
  end

  it "indexes .rb files nested under the workspace root" do
    Dir.mktmpdir do |dir|
      write(dir, "app/models/user.rb", "class User\nend\n")
      write(dir, "app/controllers/posts_controller.rb", "class PostsController\nend\n")

      run_indexer(dir)

      expect(class_declared?("User")).to be(true)
      expect(class_declared?("PostsController")).to be(true)
    end
  end

  it "indexes .rake files" do
    Dir.mktmpdir do |dir|
      write(dir, "lib/tasks/thing.rake", "class RakeHelper\nend\n")

      run_indexer(dir)

      expect(class_declared?("RakeHelper")).to be(true)
    end
  end

  it "extracts Ruby regions from .erb files rather than feeding raw HTML+ERB to Prism" do
    Dir.mktmpdir do |dir|
      write(dir, "app/views/users/show.html.erb", "<h1><%= @user.name %></h1>\n<% ClassInErb = 1 %>\n")

      expect { run_indexer(dir) }.not_to raise_error
      expect(class_declared?("ClassInErb")).to be(true)
    end
  end

  %w[.git node_modules vendor/bundle tmp log coverage public/assets storage].each do |excluded|
    it "does not descend into #{excluded}" do
      Dir.mktmpdir do |dir|
        write(dir, "#{excluded}/should_not_be_indexed.rb", "class ShouldNotBeIndexed\nend\n")
        write(dir, "app/models/user.rb", "class User\nend\n")

        run_indexer(dir)

        expect(class_declared?("ShouldNotBeIndexed")).to be(false)
        expect(class_declared?("User")).to be(true)
      end
    end
  end

  it "does not overwrite an already-open document's contribution with stale on-disk content" do
    Dir.mktmpdir do |dir|
      path = write(dir, "app/models/user.rb", "class User\nend\n")
      uri = Ovallsp::UriUtil.from_path(path)

      # An editor has unsaved edits: the buffer says "Renamed", the disk
      # still says "User".
      document_store.open(uri: uri, text: "class Renamed\nend\n", version: 1, language_id: "ruby")
      workspace_index.replace_file(parser_service.summarize(document_store.fetch(uri: uri)))

      run_indexer(dir)

      expect(class_declared?("Renamed")).to be(true)
      expect(class_declared?("User")).to be(false)
    end
  end

  # Task 008.6: the previous test only covers a buffer opened *before*
  # Cold Index ever looks at the file, where its own "skip if already
  # open" check is enough. The real race is narrower and worse: a didOpen
  # landing in the window between that check and the disk-read's
  # #replace_file call — Cold Index already decided "not open" and is
  # mid-flight reading/parsing the (soon to be stale) disk content when
  # the buffer opens. This reproduces exactly that interleaving by
  # triggering the didOpen as a side effect of DocumentStore#fetch's
  # first (pre-read) call inside Cold Index's own check — the guarantee
  # must hold structurally (in WorkspaceIndex#replace_file), not just
  # because Cold Index happened to check first
  # (docs/design/tasks/008.6-agent-and-index-hardening.md).
  it "does not lose a didOpen that lands in the race window between Cold Index's open-check and its disk write" do
    Dir.mktmpdir do |dir|
      path = write(dir, "app/models/user.rb", "class User\nend\n")
      uri = Ovallsp::UriUtil.from_path(path)
      opened = false

      allow(document_store).to receive(:fetch).and_wrap_original do |original, **kwargs|
        if kwargs[:uri] == uri && !opened
          opened = true
          # Simulates textDocument/didOpen arriving on the transport
          # thread right after Cold Index's check observed "not open",
          # but before Cold Index's own disk-read summary reaches
          # WorkspaceIndex#replace_file. Returning nil here (rather than
          # delegating to the now-true `original.call`) is what actually
          # reproduces the race: Cold Index's check itself must still see
          # "not open" so it proceeds to read+parse+replace_file with
          # disk content, racing the buffer that opened in between.
          document_store.open(uri: uri, text: "class OpenedDuringColdIndex\nend\n", version: 1, language_id: "ruby")
          workspace_index.replace_file(parser_service.summarize(document_store.fetch(uri: uri)))
          next nil
        end
        original.call(**kwargs)
      end

      run_indexer(dir)

      expect(class_declared?("OpenedDuringColdIndex")).to be(true)
      expect(class_declared?("User")).to be(false)
    end
  end

  it "avoids an infinite loop on a symlink cycle" do
    Dir.mktmpdir do |dir|
      write(dir, "app/models/user.rb", "class User\nend\n")
      FileUtils.mkdir_p(File.join(dir, "app", "cyclic"))
      File.symlink(dir, File.join(dir, "app", "cyclic", "back_to_root"))

      expect { run_indexer(dir) }.not_to raise_error
      expect(class_declared?("User")).to be(true)
    end
  end

  it "does not follow a symlink that points outside the workspace root" do
    Dir.mktmpdir do |workspace|
      Dir.mktmpdir do |outside|
        write(outside, "secret.rb", "class ShouldNeverBeIndexed\nend\n")
        write(workspace, "app/models/user.rb", "class User\nend\n")
        File.symlink(outside, File.join(workspace, "app", "escape_hatch"))

        run_indexer(workspace)

        expect(class_declared?("ShouldNeverBeIndexed")).to be(false)
        expect(class_declared?("User")).to be(true)
      end
    end
  end

  # Task 008.6: the previous test only covers a symlinked *directory*
  # escaping the workspace root -- #index_file itself only used realpath
  # for dedup, never as a boundary check, so a symlinked *file* pointing
  # outside the root (reached via a perfectly ordinary, non-symlinked
  # directory) was read and indexed regardless of where it actually
  # pointed.
  it "does not follow a symlink *file* that points outside the workspace root" do
    Dir.mktmpdir do |workspace|
      Dir.mktmpdir do |outside|
        secret = write(outside, "secret.rb", "class ShouldNeverBeIndexed\nend\n")
        write(workspace, "app/models/user.rb", "class User\nend\n")
        FileUtils.mkdir_p(File.join(workspace, "app", "models"))
        File.symlink(secret, File.join(workspace, "app", "models", "leaked.rb"))

        run_indexer(workspace)

        expect(class_declared?("ShouldNeverBeIndexed")).to be(false)
        expect(class_declared?("User")).to be(true)
      end
    end
  end

  it "does not index the same file twice when reached via two symlinked paths" do
    Dir.mktmpdir do |dir|
      write(dir, "app/models/user.rb", "class User\nend\n")
      File.symlink(File.join(dir, "app"), File.join(dir, "app_alias"))

      run_indexer(dir)

      symbol_id = Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::User", discriminator: nil)
      expect(workspace_index.declarations(symbol_id).size).to eq(1)
    end
  end

  it "reads non-ASCII file content as UTF-8 rather than the process's default external encoding" do
    Dir.mktmpdir do |dir|
      write(dir, "app/models/user.rb", <<~RUBY)
        # 日本語コメントです — em dash and emoji: 😀
        class User
        end
      RUBY

      expect { run_indexer(dir) }.not_to raise_error
      expect(class_declared?("User")).to be(true)
      expect(logger).not_to have_received(:error)
    end
  end

  it "logs and continues rather than crashing when a file can't be read" do
    Dir.mktmpdir do |dir|
      write(dir, "app/models/user.rb", "class User\nend\n")
      write(dir, "app/models/broken.rb", "class Broken\n") # unterminated, but Prism tolerates this gracefully

      expect { run_indexer(dir) }.not_to raise_error
      expect(class_declared?("User")).to be(true)
    end
  end

  it "reports an incomplete scan when a directory cannot be traversed" do
    Dir.mktmpdir do |dir|
      blocked = File.join(dir, "blocked")
      FileUtils.mkdir_p(blocked)
      result = nil
      allow(Dir).to receive(:each_child).and_wrap_original do |original, path, &block|
        raise Errno::EACCES, path if path == blocked

        original.call(path, &block)
      end

      described_class.new(
        root: dir, parser_service: parser_service, workspace_index: workspace_index,
        document_store: document_store, logger: logger, on_complete: ->(value) { result = value }
      ).run

      expect(result.complete).to be(false)
    end
  end

  # `seen_uris` is what the Server's deletion sweep subtracts from what it
  # has indexed, so a file missing from this set reads as "deleted from
  # disk" and gets evicted even though it is right there. That is the
  # watcher-vs-cold-index flapping this Result was introduced to end, so
  # the set has to include every file actually visited -- including one
  # whose summary went out through `on_summary` and one already open in a
  # buffer, both of which return early.
  it "reports every visited file in seen_uris, including ones handled by on_summary" do
    Dir.mktmpdir do |dir|
      scanned = write(dir, "scanned.rb", "class Scanned\nend\n")
      handed_off = write(dir, "handed_off.rb", "class HandedOff\nend\n")
      result = nil

      described_class.new(
        root: dir, parser_service: parser_service, workspace_index: workspace_index,
        document_store: document_store, logger: logger,
        on_summary: ->(_uri, _document, _summary) { nil },
        on_complete: ->(value) { result = value }
      ).run

      expect(result.seen_uris).to include(
        Ovallsp::UriUtil.from_path(scanned), Ovallsp::UriUtil.from_path(handed_off)
      )
    end
  end

  it "reports an incomplete scan when a candidate file cannot be inspected" do
    Dir.mktmpdir do |dir|
      path = write(dir, "blocked.rb", "class Blocked\nend\n")
      result = nil
      allow(File).to receive(:realpath).and_wrap_original do |original, candidate|
        raise Errno::EACCES, candidate if candidate == path

        original.call(candidate)
      end

      described_class.new(
        root: dir, parser_service: parser_service, workspace_index: workspace_index,
        document_store: document_store, logger: logger, on_complete: ->(value) { result = value }
      ).run

      expect(result.complete).to be(false)
    end
  end

  describe "persistent cache (Task 021)" do
    def run_indexer_with_cache(root, cache_store)
      described_class.new(
        root: root, parser_service: parser_service, workspace_index: workspace_index,
        document_store: document_store, logger: logger, cache_store: cache_store
      ).run
    end

    it "produces the same declarations on a warm (cached) run as on the cold run that populated the cache" do
      Dir.mktmpdir do |dir|
        Dir.mktmpdir do |cache_dir|
          write(dir, "app/models/user.rb", "class User\n  def name\n  end\nend\n")
          cache_store = Ovallsp::Cache::Store.new(cache_dir: cache_dir)

          run_indexer_with_cache(dir, cache_store)
          cold_declarations = workspace_index.find_by_simple_name("User")

          warm_workspace_index = Ovallsp::WorkspaceIndex.new
          warm_document_store = Ovallsp::DocumentStore.new
          described_class.new(
            root: dir, parser_service: parser_service, workspace_index: warm_workspace_index,
            document_store: warm_document_store, logger: logger, cache_store: cache_store
          ).run
          warm_declarations = warm_workspace_index.find_by_simple_name("User")

          expect(warm_declarations).to eq(cold_declarations)
        end
      end
    end

    it "does not re-parse a file whose content hasn't changed since it was cached" do
      Dir.mktmpdir do |dir|
        Dir.mktmpdir do |cache_dir|
          write(dir, "app/models/user.rb", "class User\nend\n")
          cache_store = Ovallsp::Cache::Store.new(cache_dir: cache_dir)
          run_indexer_with_cache(dir, cache_store)

          allow(parser_service).to receive(:summarize).and_call_original
          run_indexer_with_cache(dir, cache_store)

          expect(parser_service).not_to have_received(:summarize)
        end
      end
    end

    it "re-parses (and re-caches) a file whose content changed since it was cached" do
      Dir.mktmpdir do |dir|
        Dir.mktmpdir do |cache_dir|
          write(dir, "app/models/user.rb", "class User\nend\n")
          cache_store = Ovallsp::Cache::Store.new(cache_dir: cache_dir)
          run_indexer_with_cache(dir, cache_store)

          write(dir, "app/models/user.rb", "class User\n  class Renamed\n  end\nend\n")
          run_indexer_with_cache(dir, cache_store)

          expect(class_declared?("Renamed")).to be(true)
        end
      end
    end

    it "never persists an open document's content -- Cold Index already skips indexing an open uri at all" do
      Dir.mktmpdir do |dir|
        Dir.mktmpdir do |cache_dir|
          path = write(dir, "app/models/user.rb", "class User\nend\n")
          uri = Ovallsp::UriUtil.from_path(path)
          document_store.open(uri: uri, text: "class User\n  # unsaved edit\nend\n", version: 1, language_id: "ruby")
          cache_store = Ovallsp::Cache::Store.new(cache_dir: cache_dir)

          run_indexer_with_cache(dir, cache_store)

          expect(cache_store.load(path)).to be_nil
        end
      end
    end

    it "recovers from a corrupted cache entry by re-parsing, without raising" do
      Dir.mktmpdir do |dir|
        Dir.mktmpdir do |cache_dir|
          write(dir, "app/models/user.rb", "class User\nend\n")
          cache_store = Ovallsp::Cache::Store.new(cache_dir: cache_dir)
          run_indexer_with_cache(dir, cache_store)
          Dir.glob(File.join(cache_dir, "*.cache")).each { |f| File.write(f, "corrupted") }

          fresh_workspace_index = Ovallsp::WorkspaceIndex.new
          expect do
            described_class.new(
              root: dir, parser_service: parser_service, workspace_index: fresh_workspace_index,
              document_store: Ovallsp::DocumentStore.new, logger: logger, cache_store: cache_store
            ).run
          end.not_to raise_error

          expect(fresh_workspace_index.find_by_simple_name("User")).not_to be_empty
        end
      end
    end
  end
end
