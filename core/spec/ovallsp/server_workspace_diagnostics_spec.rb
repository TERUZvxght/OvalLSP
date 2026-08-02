# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

# Diagnostics for files nobody has opened (0.2.0).
#
# Before this, `publish_diagnostics` was wired only into the didOpen/
# didChange path, on the reasoning that there is no client-side buffer to
# attach the notification to. That is not how LSP works -- a client shows
# a `publishDiagnostics` for any URI, opened or not, in the Problems
# panel -- and the consequence was that an error three directories away
# stayed invisible until someone happened to look at it.
RSpec.describe "Ovallsp::Server diagnostics for files that are not open (0.2.0)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def write(root, relative_path, content)
    full = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  def wait_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
  end

  def published
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.select { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def diagnostics_for(uri)
    published.select { |m| m[:params][:uri] == uri }.last&.dig(:params, :diagnostics)
  end

  # Every server built here starts background threads (cold index, and
  # now the workspace diagnostics pass). Left running, they read files and
  # write output *during later examples* -- which is how they were first
  # noticed: an unrelated spec that counts open file descriptors before
  # and after a call started failing, because this suite's threads were
  # still opening files inside it.
  after { @servers&.each { |server| server.instance_variable_get(:@background_tasks).shutdown } }

  def build_server(root)
    server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger, workspace_root: root)
    (@servers ||= []) << server
    server
  end

  # `totally_bogus_method` on a workspace-declared class with a fully
  # known ancestry is exactly what the unknown-method check reports; the
  # point here is only that it is reported for a file nobody opened.
  def workspace_with_a_mistake(root)
    write(root, "app/models/widget.rb", "class Widget\n  def build\n  end\nend\n")
    write(root, "app/services/widget_user.rb", "Widget.new.totally_bogus_method\n")
  end

  it "reports a mistake in a file that was never opened" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      user_uri = Ovallsp::UriUtil.from_path(File.join(root, "app/services/widget_user.rb"))
      server = build_server(root)

      server.send(:start_cold_index)
      found = wait_until { !(diagnostics_for(user_uri) || []).empty? }

      expect(found).to be(true), "expected a diagnostic for a file nobody opened"
      expect(diagnostics_for(user_uri).first[:message]).to include("totally_bogus_method")
    end
  end

  # The pass visits `.erb` too -- `WorkspaceDiagnostics#language_id_for`
  # exists for exactly that. So the one check that only fires for views,
  # the unassigned `@ivar` read (0.2.0, 024.R6), is the one this path can
  # silently omit: `Engine#unassigned_ivar_findings` returns [] unless the
  # context carries `assigned_ivars`, and a context built without it looks
  # like a view whose controller could not be enumerated rather than like
  # a bug.
  it "reports an unassigned @ivar in a view nobody opened" do
    Dir.mktmpdir do |root|
      write(root, "app/controllers/users_controller.rb", <<~RUBY)
        class UsersController
          def show
            @user = User.find(params[:id])
          end
        end
      RUBY
      write(root, "app/views/users/show.html.erb", "<%= @usr.name %>\n")
      view_uri = Ovallsp::UriUtil.from_path(File.join(root, "app/views/users/show.html.erb"))
      server = build_server(root)

      server.send(:start_cold_index)
      found = wait_until do
        (diagnostics_for(view_uri) || []).any? { |d| d[:code] == "unassigned-ivar" }
      end

      expect(found).to be(true), "expected an unassigned-ivar diagnostic for a view nobody opened"
      expect(diagnostics_for(view_uri).find { |d| d[:code] == "unassigned-ivar" }[:message]).to include("@usr")
    end
  end

  # Before 0.2.0 a file nobody opened had no diagnostics, so there was
  # nothing to clear when it went away. Now there is: `git checkout` to a
  # branch without the file, or a rename -- which VS Code sends as a
  # delete plus a create, so the new path is reported and the old one is
  # stranded. Nothing else ever publishes for that URI again, and the
  # Problems panel keeps a finding about a file that does not exist.
  it "clears the diagnostics of an unopened file that is deleted" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      user_path = File.join(root, "app/services/widget_user.rb")
      user_uri = Ovallsp::UriUtil.from_path(user_path)
      server = build_server(root)

      server.send(:start_cold_index)
      wait_until { !(diagnostics_for(user_uri) || []).empty? }
      File.delete(user_path)
      server.send(:handle_did_change_watched_files, changes: [{ uri: user_uri, type: 3 }])

      expect(wait_until { diagnostics_for(user_uri) == [] }).to be(true),
             "a deleted file's diagnostics were never cleared"
    end
  end

  # `apply_file_summary` answers false when the summary changes nothing --
  # an unchanged content hash, or a disk read that lost a race with a
  # newer one. Re-analysing then is pure cost on a path a `git checkout`
  # can fire a hundred times, and it republishes an answer already on
  # screen.
  it "does not re-analyse a watched file whose content did not change" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      user_uri = Ovallsp::UriUtil.from_path(File.join(root, "app/services/widget_user.rb"))
      server = build_server(root)

      server.send(:start_cold_index)
      wait_until { !(diagnostics_for(user_uri) || []).empty? }
      before = published.count { |m| m[:params][:uri] == user_uri }
      server.send(:reindex_from_disk, user_uri)
      sleep 0.2

      expect(published.count { |m| m[:params][:uri] == user_uri }).to eq(before)
    end
  end

  # The buffer path drains pending ancestry questions in an `ensure`;
  # the workspace path raised them and never asked. A receiver the check
  # defers on in an unopened file was answered only if an open buffer
  # happened to trigger a drain later.
  it "asks the Runtime Agent about ancestries the workspace pass deferred on" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      server = build_server(root)
      asked = 0
      allow(server).to receive(:answer_pending_ancestry_questions).and_wrap_original do |original|
        asked += 1
        original.call
      end

      server.send(:start_cold_index)
      wait_until { asked.positive? }

      expect(asked).to be_positive
    end
  end

  # Activation has to happen *before* the check runs, or the check does
  # not defer: it decides whether a receiver it cannot judge statically is
  # worth asking the Agent about, and a non-activated registry means it
  # answers from static knowledge alone -- a false "has no method named"
  # on every unopened file, which is what 024.R5 exists to prevent. The
  # buffer path says so in a comment; the workspace path had the call and
  # nothing that noticed its removal.
  #
  # Asserted on the source rather than the behaviour, deliberately. The
  # difference only appears with a live Agent answering, which this suite
  # has no way to stand up -- and a fixture that cannot distinguish the
  # two candidate behaviours is not a test of them. What this does catch
  # is the line going away.
  it "activates the ancestry registry before analysing an unopened file" do
    source = File.read(File.expand_path("../../lib/ovallsp/server.rb", __dir__), encoding: "UTF-8")
    body = source[/    def workspace_findings_for.*?\n    end\n/m]

    expect(body).not_to be_nil, "workspace_findings_for has been renamed"
    expect(body).to include("@ancestry_registry.activate!")
  end

  # `close` and not `begin_pass`: a pass is *started* from another
  # background thread (the cold index, on completion), so a plain
  # invalidation at shutdown can be undone a moment later by a fresh,
  # valid pass -- which the join then has to kill instead of joining.
  it "refuses later passes at shutdown rather than only invalidating the current one" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      server = build_server(root)
      diagnostics = server.instance_variable_get(:@workspace_diagnostics)

      server.send(:shutdown_background_tasks)

      expect(diagnostics.closed?).to be(true)
      expect(diagnostics.current?(diagnostics.begin_pass)).to be(false)
    end
  end

  # The pass stops at a cap, so *which* files it reaches is part of the
  # answer -- and `uris_by_source` is Hash insertion order, which
  # `replace_file` moves a file to the end of whenever its content
  # changes. Without an order of its own, saving one file changes which
  # files past the cap are never reported, and the documented "always the
  # same tail" is false in both halves.
  it "walks the workspace in a stable order, whatever the index's own is" do
    Dir.mktmpdir do |root|
      %w[e d c b a].each { |name| write(root, "app/models/#{name}.rb", "class #{name.upcase}\nend\n") }
      server = build_server(root)
      walked = []
      allow(server.instance_variable_get(:@workspace_diagnostics)).to receive(:run)
        .and_wrap_original do |original, uris, generation|
          walked = uris
          original.call(uris, generation)
        end

      server.send(:start_cold_index)
      wait_until { walked.any? }

      expect(walked).to eq(walked.sort)
    end
  end

  it "publishes nothing for a file that has no mistakes" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      widget_uri = Ovallsp::UriUtil.from_path(File.join(root, "app/models/widget.rb"))
      user_uri = Ovallsp::UriUtil.from_path(File.join(root, "app/services/widget_user.rb"))
      server = build_server(root)

      server.send(:start_cold_index)
      wait_until { !(diagnostics_for(user_uri) || []).empty? }

      expect(diagnostics_for(widget_uri)).to eq([]).or be_nil
    end
  end

  # An open buffer's diagnostics belong to the didOpen/didChange path,
  # which knows the buffer's version and its unsaved content. A
  # workspace pass reading the same file from disk would answer about
  # text the user is not looking at, and would race the buffer path for
  # the last word on that URI.
  it "does not answer for a file the client has open, whose buffer may differ from disk" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      user_path = File.join(root, "app/services/widget_user.rb")
      user_uri = Ovallsp::UriUtil.from_path(user_path)
      server = build_server(root)

      # Opened with the mistake already fixed, so a disk-sourced answer
      # is distinguishable from a buffer-sourced one.
      server.instance_variable_get(:@document_store).open(
        uri: user_uri, text: "Widget.new.build\n", version: 7, language_id: "ruby"
      )

      server.send(:start_cold_index)
      wait_until { server.instance_variable_get(:@cold_indexing) == false }
      sleep 0.2

      expect(diagnostics_for(user_uri)).to be_nil
    end
  end

  it "re-reports a file after it changes on disk while still unopened" do
    Dir.mktmpdir do |root|
      write(root, "app/models/widget.rb", "class Widget\n  def build\n  end\nend\n")
      user_path = write(root, "app/services/widget_user.rb", "Widget.new.build\n")
      user_uri = Ovallsp::UriUtil.from_path(user_path)
      server = build_server(root)

      server.send(:start_cold_index)
      wait_until { server.instance_variable_get(:@cold_indexing) == false }

      File.write(user_path, "Widget.new.totally_bogus_method\n")
      server.send(:reindex_from_disk, user_uri)

      expect(wait_until { !(diagnostics_for(user_uri) || []).empty? }).to be(true)
      expect(diagnostics_for(user_uri).first[:message]).to include("totally_bogus_method")
    end
  end

  it "clears a file's diagnostics once the mistake is corrected on disk" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      user_path = File.join(root, "app/services/widget_user.rb")
      user_uri = Ovallsp::UriUtil.from_path(user_path)
      server = build_server(root)

      server.send(:start_cold_index)
      wait_until { !(diagnostics_for(user_uri) || []).empty? }

      File.write(user_path, "Widget.new.build\n")
      server.send(:reindex_from_disk, user_uri)

      expect(wait_until { (diagnostics_for(user_uri) || [:unset]).empty? }).to be(true)
    end
  end

  # Every caller of `republish_open_diagnostics` is a moment when the
  # answers changed workspace-wide -- the Runtime Agent becoming ready is
  # the one that matters, since the unknown-method check defers rather
  # than guesses without one. Refreshing only the open buffers there
  # leaves every other file reporting what was true before the Agent
  # arrived.
  it "re-reports unopened files when something changes the answers workspace-wide" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      user_uri = Ovallsp::UriUtil.from_path(File.join(root, "app/services/widget_user.rb"))
      server = build_server(root)

      server.send(:start_cold_index)
      wait_until { !(diagnostics_for(user_uri) || []).empty? }

      output.truncate(0)
      output.rewind
      server.send(:republish_open_diagnostics)

      expect(wait_until { !(diagnostics_for(user_uri) || []).empty? }).to be(true)
    end
  end

  # The pass runs on a background thread precisely so that it cannot do
  # this, and "initialize returns immediately" is the property the cold
  # index itself was already built to preserve.
  it "does not delay the response to initialize" do
    Dir.mktmpdir do |root|
      write(root, "app/models/widget.rb", "class Widget\n  def build\n  end\nend\n")
      120.times { |i| write(root, "app/services/user_#{i}.rb", "Widget.new.totally_bogus_method\n") }

      frame = lambda do |hash|
        json = JSON.generate(hash)
        "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
      end
      input = frame.call(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
              frame.call(jsonrpc: "2.0", method: "exit", params: nil)

      server = Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger, workspace_root: root)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      server.run
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(elapsed).to be < 1.0
    end
  end
end
