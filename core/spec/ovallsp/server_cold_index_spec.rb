# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe "Ovallsp::Server cold index (Task 008.5)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def write(root, relative_path, content)
    full = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  def wait_until(timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield

      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
  end

  # Wait on the cold index *finishing*, not on a wall clock.
  #
  # `wait_until`'s three seconds is a bound on how long a *hang* is
  # allowed to take, and it is right for the examples that assert
  # something must eventually stop being true. It is the wrong instrument
  # for "the cold index has run": that answer depends on the machine, and
  # `#cold_indexes_references…` failed once on a loaded one and passed six
  # times alone immediately afterwards. A test whose result depends on how
  # busy the machine is measures the machine.
  #
  # `BackgroundTasks#track_thread` holds the cold-index thread, so joining
  # it is the deterministic wait. The same reach is already made by
  # `server_rails_invalidation_spec.rb`.
  def join_cold_index(server, timeout: 60)
    threads = server.instance_variable_get(:@background_tasks).instance_variable_get(:@threads)
    threads.each { |t| t.join(timeout) }
  end

  it "resolves a view opened before its controller has ever been opened (the Task 008 cold-index gap)" do
    Dir.mktmpdir do |root|
      write(root, "app/controllers/users_controller.rb", <<~RUBY)
        class UsersController
          def show
            @user = User.find(params[:id])
          end
        end
      RUBY
      view_path = write(root, "app/views/users/show.html.erb", "<p><%= @user %></p>\n")

      model_registry = Ovallsp::Models::ModelRegistry.new
      model_registry.register_from_agent_response(
        "User", { tableName: "users", partial: false, columns: [], associations: [] }
      )

      view_uri = Ovallsp::UriUtil.from_path(view_path)
      view_text = File.read(view_path)

      server = Ovallsp::Server.new(
        input: StringIO.new(""), output: output, logger: logger,
        model_registry: model_registry, workspace_root: root
      )

      # Simulates what `initialize` triggers, without needing a full
      # protocol round trip for this test: cold-indexing runs on a
      # background thread, so poll rather than assume timing.
      server.send(:start_cold_index)
      controller_symbol = Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::UsersController",
                                                                     discriminator: nil)
      indexed = wait_until { !server.instance_variable_get(:@workspace_index).declarations(controller_symbol).empty? }
      expect(indexed).to be(true), "expected cold indexing to discover UsersController without it ever being opened"

      # The view itself is opened normally — only the *controller* relies
      # on cold indexing, matching the actual Task 008 gap.
      server.instance_variable_get(:@document_store).open(
        uri: view_uri, text: view_text, version: 1, language_id: "erb"
      )

      result = server.send(:explain_type_result,
                            { textDocument: { uri: view_uri }, position: { line: 0, character: 8 } })

      expect(result).to eq(type: "User")
    end
  end

  # `expect(elapsed).to be < 1.0` was the bound until 0.2.6, and every
  # attempt to repair it as a measurement failed, which is the finding:
  #
  # - it flaked. The run takes ~0.55s here and nearly all of that is
  #   loading signatures during `initialize`, so the margin was 1.8x and
  #   a loaded machine crossed it;
  # - it could not fail for what it claimed. Cold-indexing 120 two-line
  #   files takes ~50ms, so calling `ColdIndexer` inline also comes in
  #   under a second -- measured, and the example passed;
  # - it timed the wrong event. `server.run` returns after `exit`, which
  #   joins the background tasks, so its duration always included the
  #   indexing whether or not a client ever waited for it;
  # - and timing the *reply* instead, over a pipe, with the indexing
  #   deliberately slowed by two seconds, still could not fail -- because
  #   `dispatch` calls `respond` **before** `start_cold_index`. The reply
  #   is early by ordering, not by threading.
  #
  # That last point is the property worth pinning, and it needs no clock:
  # by the time indexing begins, the reply is already written. Moving
  # `start_cold_index` above `respond` fails this; nothing about machine
  # load can.
  it "writes the initialize reply before it begins indexing the workspace" do
    Dir.mktmpdir do |root|
      write(root, "app/models/widget.rb", "class Widget\nend\n")
      output_when_indexing_began = nil
      allow_any_instance_of(Ovallsp::ColdIndexer).to receive(:run) do
        output_when_indexing_began = output.string.dup
        Ovallsp::ColdIndexer::Result.new(seen_uris: [], complete: true)
      end

      input =
        frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)
      Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger, workspace_root: root).run

      expect(output_when_indexing_began).to include(%("id":1))
    end
  end

  it "cold-indexes references and Rails generated-method facts, not only declarations" do
    Dir.mktmpdir do |root|
      write(root, "app/models/widget.rb", <<~RUBY)
        class Widget
          scope :active, -> { where(active: true) }
          def build
          end
        end
      RUBY
      write(root, "app/services/widget_user.rb", "Widget.new.build\n")

      server = Ovallsp::Server.new(
        input: StringIO.new(""), output: output, logger: logger, workspace_root: root
      )
      server.send(:start_cold_index)
      join_cold_index(server)

      build_symbol = Ovallsp::Index::SymbolId.new(
        kind: :instance_method, owner: "::Widget", name: "build", discriminator: nil
      )
      scope_symbol = Ovallsp::Index::SymbolId.new(
        kind: :singleton_method, owner: "::Widget", name: "active", discriminator: nil
      )
      reference_index = server.instance_variable_get(:@reference_index)
      generated_index = server.instance_variable_get(:@generated_method_index)

      expect(generated_index.fact_for(scope_symbol)).not_to be_nil
      server.send(:ensure_reference_index_current)
      expect(reference_index.references(build_symbol)).not_to be_empty
    end
  end

  # Regression: the post-cold-index sweep removed every indexed disk URI
  # ColdIndexer had not visited, treating "not visited" as "deleted".
  # ColdIndexer skips vendor/ (DEFAULT_EXCLUDED_DIRS), but the client's
  # file watcher has no such exclusion and indexes through
  # `reindex_from_disk` -- so a live, on-disk file reachable only through
  # the wider path was purged on every re-index, came back when touched,
  # and was purged again.
  it "keeps a watcher-indexed file that Cold Index deliberately skips, while it still exists on disk" do
    Dir.mktmpdir do |root|
      write(root, "app/models/widget.rb", "class Widget\nend\n")
      # Inside an excluded directory: ColdIndexer will never visit this.
      vendored = write(root, "vendor/engines/billing/app/models/invoice.rb", "class Invoice\nend\n")

      server = Ovallsp::Server.new(
        input: StringIO.new(""), output: output, logger: logger, workspace_root: root
      )
      server.send(:start_cold_index)

      invoice = Ovallsp::Index::SymbolId.new(
        kind: :class, owner: nil, name: "::Invoice", discriminator: nil
      )
      workspace_index = server.instance_variable_get(:@workspace_index)
      expect(wait_until { !workspace_index.declarations(invoice).empty? }).to be(false),
        "sanity: ColdIndexer is expected to skip vendor/"

      # The watcher reports it, exactly as VS Code's own glob would.
      server.send(:reindex_from_disk, "file://#{vendored}")
      expect(workspace_index.declarations(invoice)).not_to be_empty

      # A second cold index (e.g. "OvalLSP: Re-index Workspace") must not
      # evict it: the file is still right there on disk.
      server.send(:start_cold_index)
      expect(wait_until { workspace_index.declarations(invoice).empty? }).to be(false)
      expect(File.file?(vendored)).to be(true)
      expect(workspace_index.declarations(invoice)).not_to be_empty
    end
  end

  it "does not let a late Cold Index callback overwrite buffer-side semantic state" do
    server = Ovallsp::Server.new(
      input: StringIO.new(""), output: output, logger: logger, workspace_root: Dir.pwd
    )
    uri = "file:///race.rb"
    parser = Ovallsp::ParserService.new
    buffer_document = Ovallsp::TextDocument.new(
      uri: uri, text: "class BufferVersion\nend\n", version: 1, language_id: "ruby"
    )
    disk_document = Ovallsp::TextDocument.new(
      uri: uri, text: "class DiskVersion\nend\n", version: nil, language_id: "ruby"
    )
    buffer_summary = parser.summarize(buffer_document)
    disk_summary = parser.summarize(disk_document).with(
      source: :disk, read_sequence: server.instance_variable_get(:@workspace_index).next_read_sequence
    )

    expect(server.send(:apply_file_summary, buffer_summary)).to be(true)
    expect(server.send(:apply_cold_summary, uri, disk_document, disk_summary)).to be(false)

    stored = server.instance_variable_get(:@file_summaries).fetch(uri)
    expect(stored.content_hash).to eq(buffer_summary.content_hash)
  end
end
