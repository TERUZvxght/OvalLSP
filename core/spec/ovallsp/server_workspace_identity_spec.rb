# frozen_string_literal: true

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

  around do |example|
    Dir.mktmpdir do |parent|
      @real = File.join(parent, "real")
      @link = File.join(parent, "link")
      FileUtils.mkdir_p(File.join(@real, "app"))
      File.write(File.join(@real, "app", "widget.rb"), "class Widget\nend\n")
      File.symlink(@real, @link)
      example.run
    end
  end

  def server_started_from(cwd, root_uri:)
    output = StringIO.new
    input = frame(jsonrpc: "2.0", id: 1, method: "initialize",
                  params: root_uri ? { rootUri: Ovallsp::UriUtil.from_path(root_uri) } : {})
    server = Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger, workspace_root: cwd)
    server.run
    server
  end

  it "takes the root the editor named, not the one its own cwd resolves to" do
    server = server_started_from(@real, root_uri: @link)

    expect(server.instance_variable_get(:@workspace_root)).to eq(@link)
  end

  # The consequence, stated as the property: a file under the workspace
  # has one uri, and it is the one the editor will use when it opens it.
  it "builds a file's uri under the root the editor named" do
    server = server_started_from(@real, root_uri: @link)
    root = server.instance_variable_get(:@workspace_root)

    expect(Ovallsp::UriUtil.from_path(File.join(root, "app/widget.rb")))
      .to eq(Ovallsp::UriUtil.from_path(File.join(@link, "app/widget.rb")))
  end

  # The control: with no `rootUri` -- a client that does not send one, or
  # a direct stdio session -- the cwd is still the root, which is the
  # behaviour every existing caller relies on.
  it "keeps using its own cwd when the client names no root" do
    server = server_started_from(@real, root_uri: nil)

    expect(server.instance_variable_get(:@workspace_root)).to eq(@real)
  end
end
