# frozen_string_literal: true

require_relative "../support/workspace_identity_report"

require "stringio"
require "tmpdir"
require "fileutils"

# Core never read `rootUri` -- `grep -rn "rootUri" core/lib` found
# nothing -- and defaulted `workspace_root:` to `Dir.pwd`. The extension
# spawns Core with `cwd: folder.uri.fsPath`, and a child process started
# with its cwd on a symlink reports the **resolved** path. So the
# workspace pass built every uri under the real path while every
# editor-driven message used the symlink path.
#
# Driven end to end by 0.2.7's review round: the same file appears twice
# in the Problems panel, and the resolved-path copy shows errors on lines
# that no longer exist. Fixing them, saving and closing the tab all leave
# it, because nothing publishes to that uri again. Go-to-definition
# returns the real path too, so following it opens a second tab of the
# same file. `024.98`.
#
# A symlinked checkout is ordinary: `/tmp` on macOS, git worktrees,
# `~/src` pointing at a volume.
#
# 037's C8: the editor's `rootUri` is what the user sees and what every
# editor-driven message carries, so it is the root -- not something Core
# infers from its own cwd.
RSpec.describe "Ovallsp::Server and a workspace reached through a symlink" do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  # `initialize` reaches `build_cache_store`, which marks a workspace
  # scope and starts `Cache::Store.prune_generations` -- the function
  # docs/CODE_DISCIPLINE.md's "Code that deletes" section is entirely about.
  # Without this the ordinary unit suite writes permanent scope
  # directories into the developer's own `~/.cache/ovallsp` and sweeps it:
  # a review round measured three new directories per run of this file,
  # in a cache that had reached 4,322. `server_cache_sweep_spec.rb`
  # already knew to do this; this file did not, and every spec that
  # dispatches a real `initialize` has the same gap.
  around do |example|
    Dir.mktmpdir do |cache_home|
      previous = ENV.fetch("XDG_CACHE_HOME", nil)
      ENV["XDG_CACHE_HOME"] = cache_home
      begin
        example.run
      ensure
        ENV["XDG_CACHE_HOME"] = previous
      end
    end
  end

  around do |example|
    Dir.mktmpdir do |parent|
      @parent = parent
      @real = File.join(parent, "real")
      @link = File.join(parent, "link")
      FileUtils.mkdir_p(File.join(@real, "app"))
      File.write(File.join(@real, "app", "widget.rb"), "class Widget\nend\n")
      File.symlink(@real, @link)
      example.run
    end
  end


# 024.275: two of the examples below failed once in a full-suite run
# and have never failed since, and *both runs that recorded a message
# were runs that passed* -- so the value the assertion actually saw has
# never been seen. The entry's instruction is to capture it on the next
# reproduction, which has stood unexecuted for two releases because it
# addresses whoever happens to be watching.
#
# Attached to the assertion instead. A reproduction now records itself:
# what was expected, what was got, the load the machine was under, and
# for each path whether it exists, is a directory, is a symlink, and
# where it points -- which is what tells the entry's two readings apart.
def expect_root(server, to_be:)
  got = server.instance_variable_get(:@workspace_root)
  expect(got).to eq(to_be),
                 "workspace root is not the one the editor named." +
                 WorkspaceIdentityReport.for(expected: to_be, got: got,
                                             paths: { real: @real, link: @link })
end

  # **Every server this file starts is stopped before its tmpdir goes.**
  #
  # `initialize` starts the cold index on a background thread, and four
  # examples here dispatch it directly rather than through `#run`, so
  # nothing processed an `exit` and nothing joined those threads. The
  # `around` block then removed the cache tmpdir underneath a thread
  # still writing into it, and teardown failed with
  # `Errno::ENOTEMPTY: Directory not empty @ dir_s_rmdir`. It surfaced on
  # the Ruby 4.0 job, which schedules differently -- the race is not
  # 4.0's, only its timing was.
  #
  # Registered here rather than at each example, because the next
  # `dispatch` written in this file would have the same race and no
  # reason to think about it.
  def started(server)
    (@servers ||= []) << server
    server
  end

  after do
    Array(@servers).each { |server| server.send(:shutdown_background_tasks) }
  rescue StandardError
    # Contained: this is teardown. A server that cannot be stopped has
    # already told the example whatever it had to say, and the tmpdir
    # removal is what fails loudly if it mattered.
    nil
  end

  def server_started_from(cwd, root_uri:)
    output = StringIO.new
    input = frame(jsonrpc: "2.0", id: 1, method: "initialize",
                  params: root_uri ? { rootUri: Ovallsp::UriUtil.from_path(root_uri) } : {})
    server = Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger, workspace_root: cwd)
    started(server)
    server.run
    server
  end

# **Adopting the editor's root built a second signature environment
# and left the first one wired in.** `#adopt_client_workspace_root`
# assigned `@signatures` a freshly loaded `Environment`, while
# `AnalysisStack` -- and through it the local inferencer, the method
# resolver's callers and, since a core class stopped being reinterpretable
# by a gem, the hierarchy index -- went on holding the one built from
# the process's own cwd. Two environments in one server, and which one
# answered depended on which collaborator was asked.
#
# The reload path already had this right: it calls `#load` on the
# environment in place, precisely so that every holder sees it. This
# is the same call at the other site.
#
# The control is the first expectation: the server's own reference
# *does* know the name, so the signature file is real and loadable and
# the second expectation is about who can see it rather than about
# whether there was anything to see.
it "reloads the environment the analysis stack holds rather than building a second one beside it" do
  FileUtils.mkdir_p(File.join(@real, "sig"))
  File.write(File.join(@real, "sig", "probe.rbs"), "class SigOnlyProbe\n  def go: () -> void\nend\n")
  # Started from a directory carrying no signatures of its own, so
  # knowing this name can only have come from adopting the root.
  server = server_started_from(@parent, root_uri: @link)

  expect(server.instance_variable_get(:@signatures).declares?("SigOnlyProbe")).to be(true)
  expect(server.instance_variable_get(:@analysis).signatures.declares?("SigOnlyProbe")).to be(true)
end

  it "takes the root the editor named, not the one its own cwd resolves to" do
    server = server_started_from(@real, root_uri: @link)

    expect_root(server, to_be: @link)
  end

  # The consequence, stated as the property a user meets: the diagnostics
  # for a file arrive under the uri the editor uses for it, so the
  # Problems panel lists it once.
  #
  # **The first version of this example could not fail**: it read
  # `@workspace_root` back out of the server and compared
  # `UriUtil.from_path(root/"app/widget.rb")` with
  # `UriUtil.from_path(@link/"app/widget.rb")` -- given the example above
  # it, `x == x`, a pure function applied to both sides of an equality
  # already asserted. It never asked anything to build a uri. Found by a
  # review round.
  it "publishes a file's diagnostics under the uri the editor uses" do
    File.write(File.join(@real, "app", "widget.rb"), "class Widget\nend\nWidget.new.definitely_not_here\n")
    output = StringIO.new
    server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger, workspace_root: @real)
    started(server)
    # `dispatch` rather than `run`: `run` returns at EOF and shuts the
    # background tasks down, so the pass this example is about would never
    # get to publish.
    server.send(:dispatch, { method: "initialize", id: 1,
                             params: { rootUri: Ovallsp::UriUtil.from_path(@link) } })
    server.send(:start_cold_index)
    server.send(:start_workspace_diagnostics)

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
    published = []
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      published = published_uris(output)
      break unless published.empty?

      sleep 0.05
    end
    server.shutdown_background_tasks if server.respond_to?(:shutdown_background_tasks)

    expect(published).to all(start_with(Ovallsp::UriUtil.from_path(@link)))
    expect(published).not_to be_empty
  end

  def published_uris(output)
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    uris = []
    begin
      loop do
        message = reader.read_message
        uris << message[:params][:uri] if message[:method] == "textDocument/publishDiagnostics"
      end
    rescue Ovallsp::IO::FramedReader::EOF, Ovallsp::IO::FramedReader::ProtocolError
      nil
    end
    uris
  end

  # The control: with no `rootUri` -- a client that does not send one, or
  # a direct stdio session -- the cwd is still the root, which is the
  # behaviour every existing caller relies on.
  it "keeps using its own cwd when the client names no root" do
    server = server_started_from(@real, root_uri: nil)

    expect_root(server, to_be: @real)
  end

  # `workspaceFolders` is what a client may send instead: `rootUri` is
  # deprecated in the specification, and a client sending folders often
  # sends `rootUri: null` alongside them.
  it "takes the first workspace folder when the client sends no rootUri" do
    output = StringIO.new
    server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger, workspace_root: @real)
    started(server)
    server.send(:dispatch, { method: "initialize", id: 1,
                             params: { rootUri: nil,
                                       workspaceFolders: [{ uri: Ovallsp::UriUtil.from_path(@link), name: "w" }] } })

    expect_root(server, to_be: @link)
  end

  # The absent root is **inside this example's own tmpdir**, not a
  # fabricated path at `/`. The previous form was `/nonexistent-<pid>`,
  # which is the shape docs/CODE_DISCIPLINE.md's `/Applications` rule names: a path
  # chosen to be obviously fake is chosen without looking at what is
  # actually there, and it made this example's verdict depend on the
  # state of the machine's root directory. Nothing here deletes, so it
  # was never that incident's hazard -- but 024.275 is a failure that
  # came and went with machine load, and an assertion answered from
  # outside the fixture is one candidate fewer once it is answered from
  # inside it.
  #
  # And a root the client names that is not there is refused rather than
  # adopted: an editor can send a folder that has since been deleted, and
  # indexing nothing is worse than indexing the cwd.
  it "keeps its own cwd when the named root does not exist" do
    output = StringIO.new
    server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger, workspace_root: @real)
    started(server)
    server.send(:dispatch, { method: "initialize", id: 1,
                             params: { rootUri: Ovallsp::UriUtil.from_path(File.join(@parent, "gone")) } })

    expect_root(server, to_be: @real)
  end

  # The signature environment is built in the constructor, from the cwd,
  # before any message arrives -- so moving the root without rebuilding it
  # left the index following `rootUri` while `sig/` followed the cwd. For
  # a symlinked workspace both name the same files; for a client that
  # spawns from the editor's own directory they do not.
  #
  # **The generation, not the object.** This asserted `not_to equal(before)`
  # -- that adoption produced a *different* environment -- which is a fact
  # about how the reload was written rather than the property named above,
  # and it turned out to be the wrong one of the two: replacing the object
  # is exactly what left `AnalysisStack` holding the old one. A load bumps
  # the generation, so this says the environment was rebuilt without saying
  # anything about which object carries it.
  it "rebuilds the signature environment when the root moves" do
    output = StringIO.new
    server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger, workspace_root: @real)
    started(server)
    before = server.instance_variable_get(:@signatures).generation

    server.send(:dispatch, { method: "initialize", id: 1,
                             params: { rootUri: Ovallsp::UriUtil.from_path(@link) } })

    expect(server.instance_variable_get(:@signatures).generation).to be > before
  end
end

