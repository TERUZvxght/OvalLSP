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
      server.send(:handle_did_change_watched_files, changes: [{ uri: user_uri, type: 2 }])
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

  # The unknown-method check defers rather than guesses only once there
  # is an Agent to defer *to*. Before the bootstrap settles it falls back
  # to the static reading, which is wrong for every class whose ancestry
  # runs into a gem -- and until 0.2.0 that reading reached a user only
  # if they opened the file. Publishing it for the whole project at
  # startup, and correcting it a boot later, is a Problems panel full of
  # findings about working code.
  it "waits for the Runtime Agent's bootstrap to settle before the first pass" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      server = build_server(root)
      server.instance_variable_set(:@agent_bootstrap_pending, true)
      started = 0
      allow(server.instance_variable_get(:@workspace_diagnostics)).to receive(:run)
        .and_wrap_original do |original, uris, generation|
          started += 1
          original.call(uris, generation)
        end

      server.send(:start_cold_index)
      wait_until { server.instance_variable_get(:@cold_indexing) == false }
      sleep 0.2

      expect(started).to eq(0)
    end
  end

  # A batch of changed files is its own bounded piece of work, not a new
  # workspace pass. Taking a generation for it superseded the pass that
  # was running -- and, unlike every other caller that supersedes one,
  # this one did not start a replacement, so the rest of the workspace
  # was never analysed. One `git pull` during the first pass ended it.
  it "does not end the workspace pass when a watched file changes" do
    Dir.mktmpdir do |root|
      write(root, "app/models/widget.rb", "class Widget\n  def build\n  end\nend\n")
      8.times { |i| write(root, "app/services/s#{i}_user.rb", "Widget.new.totally_bogus_x\n") }
      other = write(root, "app/services/trigger.rb", "class Trigger\nend\n")
      server = build_server(root)
      # Held inside the first file, so the change lands while the pass is
      # genuinely running. Without the gate the pass finishes before the
      # notification arrives and the fixture cannot fail.
      gate = Queue.new
      entered = Queue.new
      first = true
      allow(server.instance_variable_get(:@workspace_diagnostics)).to receive(:publish_for)
        .and_wrap_original do |original, uri|
          if first
            first = false
            entered << true
            gate.pop
          end
          original.call(uri)
        end

      server.send(:start_cold_index)
      entered.pop
      File.write(other, "class Trigger\n  def go\n  end\nend\n")
      server.send(:handle_did_change_watched_files,
                  changes: [{ uri: Ovallsp::UriUtil.from_path(other), type: 2 }])
      gate << true

      reported = wait_until do
        8.times.all? do |i|
          uri = Ovallsp::UriUtil.from_path(File.join(root, "app/services/s#{i}_user.rb"))
          !(diagnostics_for(uri) || []).empty?
        end
      end
      expect(reported).to be(true), "the workspace pass stopped when an unrelated file changed"
    end
  end

  # A batch is a batch: every example that drives this handler passes one
  # changed file, so nothing exercised the loop the batching exists for.
  # A `git pull` naming three files must re-diagnose three.
  it "re-analyses every file a batch names, not the first" do
    Dir.mktmpdir do |root|
      write(root, "app/models/widget.rb", "class Widget\n  def build\n  end\nend\n")
      paths = 3.times.map { |i| write(root, "app/services/s#{i}.rb", "class S#{i}\nend\n") }
      server = build_server(root)
      server.send(:start_cold_index)
      wait_until { server.instance_variable_get(:@cold_indexing) == false }
      paths.each { |path| File.write(path, "Widget.new.totally_bogus_x\n") }

      server.send(:handle_did_change_watched_files,
                  changes: paths.map { |p| { uri: Ovallsp::UriUtil.from_path(p), type: 2 } })

      reported = wait_until do
        paths.all? { |p| !(diagnostics_for(Ovallsp::UriUtil.from_path(p)) || []).empty? }
      end
      expect(reported).to be(true), "only part of the batch was re-analysed"
    end
  end

  # The rescue's value would otherwise be the logger's, which is truthy
  # for a real IO -- so a file that failed to reindex was reported as
  # applied and queued for an analysis that fails too.
  it "reports a failed reindex as not applied" do
    Dir.mktmpdir do |root|
      path = write(root, "app/models/widget.rb", "class Widget\nend\n")
      server = build_server(root)
      allow(server.instance_variable_get(:@parser_service)).to receive(:summarize).and_raise("boom")

      expect(server.send(:reindex_from_disk, Ovallsp::UriUtil.from_path(path))).to be(false)
    end
  end

  # Closing a buffer analyses one file; it must not take the generation a
  # workspace pass is identified by. The same decision at
  # `analyze_changed_files_later` is pinned above; this one is the other
  # caller of the same rule.
  it "does not end the workspace pass when a buffer is closed" do
    Dir.mktmpdir do |root|
      write(root, "app/models/widget.rb", "class Widget\n  def build\n  end\nend\n")
      6.times { |i| write(root, "app/services/s#{i}.rb", "Widget.new.totally_bogus_x\n") }
      other = write(root, "app/services/open_one.rb", "class OpenOne\nend\n")
      server = build_server(root)
      gate = Queue.new
      entered = Queue.new
      first = true
      allow(server.instance_variable_get(:@workspace_diagnostics)).to receive(:publish_for)
        .and_wrap_original do |original, uri|
          if first
            first = false
            entered << true
            gate.pop
          end
          original.call(uri)
        end

      server.send(:handle_did_open, textDocument: { uri: Ovallsp::UriUtil.from_path(other), version: 1,
                                                    languageId: "ruby", text: File.read(other) })
      server.send(:start_cold_index)
      entered.pop
      server.send(:handle_did_close, textDocument: { uri: Ovallsp::UriUtil.from_path(other) })
      gate << true

      reported = wait_until do
        6.times.all? do |i|
          uri = Ovallsp::UriUtil.from_path(File.join(root, "app/services/s#{i}.rb"))
          !(diagnostics_for(uri) || []).empty?
        end
      end
      expect(reported).to be(true), "the workspace pass stopped when a buffer was closed"
    end
  end

  # The pass drains the ancestry questions each file raises, and an
  # installed answer republishes -- which restarted the pass from file 0.
  # It terminates, because an answered name is never re-asked, but the
  # redundant work grows with the workspace: 5x on 30 files, 9x on 150,
  # every restart re-taking the index mutex the request path needs.
  it "does not restart itself for an answer its own pass produced" do
    Dir.mktmpdir do |root|
      12.times do |i|
        write(root, "app/models/m#{i}.rb", "class Base#{i}\nend\n\nclass Thing#{i} < Base#{i}\nend\n")
      end
      server = build_server(root)
      passes = 0
      allow(server.instance_variable_get(:@workspace_diagnostics)).to receive(:run)
        .and_wrap_original do |original, uris, generation|
          passes += 1
          original.call(uris, generation)
        end

      drivers = 0
      allow(server).to receive(:drive_workspace_passes).and_wrap_original do |original|
        drivers += 1
        original.call
      end

      server.send(:start_cold_index)
      wait_until { server.instance_variable_get(:@cold_indexing) == false }
      5.times { server.send(:republish_open_diagnostics) }
      sleep 0.3

      expect(passes).to be <= 2
      # And one driver, not one per request: the loop bounds the passes
      # either way, but without the guard each call spawns its own thread.
      expect(drivers).to be <= 2
    end
  end

  # Closing a buffer clears its diagnostics -- the buffer path owned them
  # -- and something has to give them back from disk. Without the
  # republish the file's findings vanish from the Problems panel with
  # nothing restoring them, which is the regression 0.2.0 exists to
  # prevent, one didClose away.
  it "restores a closed file's diagnostics from disk" do
    Dir.mktmpdir do |root|
      workspace_with_a_mistake(root)
      path = File.join(root, "app/services/widget_user.rb")
      uri = Ovallsp::UriUtil.from_path(path)
      server = build_server(root)
      server.send(:start_cold_index)
      wait_until { server.instance_variable_get(:@cold_indexing) == false }
      server.send(:handle_did_open, textDocument: { uri: uri, version: 1, languageId: "ruby",
                                                    text: File.read(path) })

      server.send(:handle_did_close, textDocument: { uri: uri })

      expect(wait_until { !(diagnostics_for(uri) || []).empty? }).to be(true),
             "closing the buffer left the file with no diagnostics"
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
      server.send(:handle_did_change_watched_files, changes: [{ uri: user_uri, type: 2 }])

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
      server.send(:handle_did_change_watched_files, changes: [{ uri: user_uri, type: 2 }])

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
  #
  # `expect(elapsed).to be < 1.0` until 0.2.6, and it was the same defect
  # as `server_cold_index_spec`'s: it flaked under load, and it could not
  # fail for what it claimed -- `server.run` returns after `exit`, which
  # joins the background tasks, so the number always included the pass
  # whether or not a client ever waited for it.
  #
  # An ordering assertion was tried next and could not fail either: the
  # pass is started from the cold index's own completion hook, so it never
  # ran on the dispatch thread in the first place and reordering
  # `dispatch` changed nothing. Recorded because that is two
  # can't-fail assertions in a row about one property, and the second was
  # written while fixing the first.
  #
  # What is actually true, and is the whole reason this cannot delay a
  # reply: the pass runs on a thread that is not the one serving requests.
  # Making `#drive_workspace_passes` run inline fails this.
  #
  # Two wall-clock thresholds of one shape in one release is what
  # `core/spec/meta/no_wall_clock_thresholds_spec.rb` exists to stop, per
  # CLAUDE.md's rule about the same place twice.
  it "runs the pass on a thread other than the one serving requests" do
    Dir.mktmpdir do |root|
      write(root, "app/models/widget.rb", "class Widget\n  def build\n  end\nend\n")
      write(root, "app/services/user.rb", "Widget.new.totally_bogus_method\n")

      server = build_server(root)
      dispatch_thread = Thread.current
      pass_thread = nil
      allow(server).to receive(:drive_workspace_passes).and_wrap_original do |original, *args|
        pass_thread = Thread.current
        original.call(*args)
      end

      server.send(:start_workspace_diagnostics)
      expect(wait_until { !pass_thread.nil? }).to be(true)

      expect(pass_thread).not_to be(dispatch_thread)
    end
  end
end
