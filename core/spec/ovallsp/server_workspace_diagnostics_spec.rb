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

  def build_server(root)
    Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger, workspace_root: root)
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
