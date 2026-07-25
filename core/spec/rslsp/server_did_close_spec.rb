# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe "Rslsp::Server didClose index consistency (Task 008.5)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def sent_messages(io)
    io.rewind
    reader = Rslsp::IO::FramedReader.new(io)
    messages = []
    loop { messages << reader.read_message }
  rescue Rslsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def run_server(input_string, workspace_root: Dir.mktmpdir)
    server = Rslsp::Server.new(
      input: StringIO.new(input_string), output: output, logger: logger, workspace_root: workspace_root
    )
    server.run
  end

  def open(uri, text)
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: "ruby" } }
    )
  end

  def close(uri)
    frame(jsonrpc: "2.0", method: "textDocument/didClose", params: { textDocument: { uri: uri } })
  end

  def workspace_symbol_query(id, query)
    frame(jsonrpc: "2.0", id: id, method: "workspace/symbol", params: { query: query })
  end

  it "falls back to disk content after closing unsaved edits to an existing file" do
    Dir.mktmpdir do |root|
      path = File.join(root, "user.rb")
      File.write(path, "class User\nend\n")
      uri = Rslsp::UriUtil.from_path(path)

      input =
        open(uri, "class RenamedWhileEditing\nend\n") +
        close(uri) +
        workspace_symbol_query(1, "Renamed") +
        workspace_symbol_query(2, "User") +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      run_server(input, workspace_root: root)

      messages = sent_messages(output)
      expect(messages[0][:result]).to eq([]) # the unsaved rename is gone
      expect(messages[1][:result].map { |s| s[:name] }).to include("User") # disk truth is back
    end
  end

  it "removes a brand-new unsaved file entirely once closed" do
    Dir.mktmpdir do |root|
      uri = Rslsp::UriUtil.from_path(File.join(root, "never_saved.rb"))

      input =
        open(uri, "class NeverSaved\nend\n") +
        close(uri) +
        workspace_symbol_query(1, "NeverSaved") +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      run_server(input, workspace_root: root)

      expect(sent_messages(output).first[:result]).to eq([])
    end
  end

  it "removes the index entry when the file was deleted from disk before closing" do
    Dir.mktmpdir do |root|
      path = File.join(root, "temp_model.rb")
      File.write(path, "class TempModel\nend\n")
      uri = Rslsp::UriUtil.from_path(path)

      input =
        open(uri, "class TempModel\nend\n") +
        frame(jsonrpc: "2.0", method: "textDocument/didChange",
              params: { textDocument: { uri: uri, version: 2 }, contentChanges: [{ text: "class TempModel\nend\n" }] }) +
        close(uri) +
        workspace_symbol_query(1, "TempModel") +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      # Delete the file between didChange and didClose, simulating the
      # user deleting it via the OS/another tool while still editing.
      File.delete(path)

      run_server(input, workspace_root: root)

      expect(sent_messages(output).first[:result]).to eq([])
    end
  end

  it "no longer offers a closed-and-reverted class for definition lookup" do
    Dir.mktmpdir do |root|
      path = File.join(root, "user.rb")
      File.write(path, "class User\nend\n")
      uri = Rslsp::UriUtil.from_path(path)
      other_uri = Rslsp::UriUtil.from_path(File.join(root, "other.rb"))

      input =
        open(uri, "class RenamedWhileEditing\nend\n") +
        close(uri) +
        open(other_uri, "RenamedWhileEditing\n") +
        frame(jsonrpc: "2.0", id: 1, method: "textDocument/definition",
              params: { textDocument: { uri: other_uri }, position: { line: 0, character: 1 } }) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      run_server(input, workspace_root: root)

      expect(sent_messages(output).first[:result]).to eq([])
    end
  end

  it "does not offer a closed-and-reverted class for completion (documentSymbol on a fresh open)" do
    Dir.mktmpdir do |root|
      path = File.join(root, "user.rb")
      File.write(path, "class User\nend\n")
      uri = Rslsp::UriUtil.from_path(path)

      input =
        open(uri, "class RenamedWhileEditing\nend\n") +
        close(uri) +
        open(uri, "class User\nend\n") +
        frame(jsonrpc: "2.0", id: 1, method: "textDocument/documentSymbol",
              params: { textDocument: { uri: uri } }) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      run_server(input, workspace_root: root)

      names = sent_messages(output).first[:result].map { |s| s[:name] }
      expect(names).to eq(["User"])
    end
  end
end
