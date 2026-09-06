# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "stringio"

# **Two entrances to the same index, and only one of them had a
# boundary.**
#
# `ColdIndexer#index_file` resolves a path and refuses one that leaves the
# workspace root -- Task 008.6 wrote that, for both a symlinked directory
# and a symlinked file. The watcher path never learned it:
# `Server#reindex_from_disk` checks `File.file?(path)`, which *follows*
# the link, and then reads it. So a `linked.rb` inside the workspace
# pointing at a file outside was refused at startup and accepted on the
# very next change notification.
#
# This is not a demonstration of a leak to the network or of anything
# being executed. What it establishes is that **which files may enter the
# static index was decided differently by each entrance** -- and an
# untrusted workspace runs the static path, so an ordinary watcher
# notification must not read as permission for an arbitrary path. Found by
# the 2026-09-05 critical review, R11.
#
# `Index::WorkspaceBoundary` is the single rule now; `ColdIndexer`
# delegates to it and this path asks it.
RSpec.describe Ovallsp::Server, "the file boundary on the watcher path" do
  let(:output) { StringIO.new }
  let(:logger) { Ovallsp::Logger.new(io: StringIO.new) }

  def frame(payload)
    body = JSON.generate(payload)
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def run_with(root, changes)
    input = frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
            frame(jsonrpc: "2.0", method: "initialized", params: {}) +
            frame(jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles", params: { changes: changes }) +
            frame(jsonrpc: "2.0", id: 2, method: "workspace/symbol", params: { query: "" }) +
            frame(jsonrpc: "2.0", method: "exit", params: nil)

    server = described_class.new(input: StringIO.new(input), output: output, logger: logger, workspace_root: root)
    server.run
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    begin
      loop { messages << reader.read_message }
    rescue Ovallsp::IO::FramedReader::EOF
      nil
    end
    messages.find { |m| m[:id] == 2 }&.dig(:result).to_a.map { |s| s[:name] }
  end

  around do |example|
    Dir.mktmpdir("ovallsp-inside-") do |workspace|
      Dir.mktmpdir("ovallsp-outside-") do |outside|
        @workspace = File.realpath(workspace)
        @outside = File.realpath(outside)
        example.run
      end
    end
  end

  it "does not index a workspace path that resolves outside the root" do
    File.write(File.join(@outside, "secret.rb"), "class ShouldNeverBeIndexed\nend\n")
    File.symlink(File.join(@outside, "secret.rb"), File.join(@workspace, "linked.rb"))

    names = run_with(@workspace, [{ uri: Ovallsp::UriUtil.from_path(File.join(@workspace, "linked.rb")), type: 2 }])

    expect(names).not_to include("ShouldNeverBeIndexed")
  end

  # **The control**, and the reason this is not "the watcher indexes
  # nothing": an ordinary file in the workspace still arrives through the
  # same notification and is indexed.
  it "still indexes an ordinary file in the workspace" do
    File.write(File.join(@workspace, "widget.rb"), "class OrdinaryWidget\nend\n")

    names = run_with(@workspace, [{ uri: Ovallsp::UriUtil.from_path(File.join(@workspace, "widget.rb")), type: 2 }])

    expect(names).to include("OrdinaryWidget")
  end

  # A link that stays inside the workspace is ordinary too -- the rule is
  # about leaving the root, not about links.
  it "still indexes a link that stays inside the workspace" do
    FileUtils.mkdir_p(File.join(@workspace, "lib"))
    File.write(File.join(@workspace, "lib", "real.rb"), "class LinkedInside\nend\n")
    File.symlink(File.join(@workspace, "lib", "real.rb"), File.join(@workspace, "alias.rb"))

    names = run_with(@workspace, [{ uri: Ovallsp::UriUtil.from_path(File.join(@workspace, "alias.rb")), type: 2 }])

    expect(names).to include("LinkedInside")
  end

  # With no workspace root there is no boundary to enforce, and refusing
  # everything would make a rootless session index nothing at all.
  it "indexes anything when the session has no workspace root" do
    File.write(File.join(@outside, "rootless.rb"), "class Rootless\nend\n")

    names = run_with(nil, [{ uri: Ovallsp::UriUtil.from_path(File.join(@outside, "rootless.rb")), type: 2 }])

    expect(names).to include("Rootless")
  end
end
