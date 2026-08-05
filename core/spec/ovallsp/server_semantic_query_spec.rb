# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe "Ovallsp::Server semantic query integration (Task 013)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Ovallsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger)
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def did_open(uri, text)
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: "ruby" } }
    )
  end

  it "completes a receiver's members after `receiver.`, sourced from the workspace index" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\n  def burn\n  end\nend\nWidget.new.b\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/completion",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 6, character: 12 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    labels = sent_messages.first[:result][:items].map { |item| item[:label] }
    expect(labels).to include("build", "burn")
  end

  it "completes stdlib members via RBS when the receiver has no source declaration" do
    input =
      did_open("file:///a.rb", "x = \"hi\"\nx.upc\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/completion",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 1, character: 5 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    labels = sent_messages.first[:result][:items].map { |item| item[:label] }
    expect(labels).to include("upcase")
  end

  it "resolves textDocument/definition for a receiver-qualified call to its source declaration, ahead of the lexical fallback" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\nend\n\nWidget.new.build\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 5, character: 13 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result).to eq([{ uri: "file:///widget.rb", range: { start: { line: 1, character: 2 }, end: { line: 2, character: 5 } } }])
  end

  it "offers signature help for an ordinary method call using its source declaration's parameters" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build(name, count)\n  end\nend\n\nWidget.new.build(\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/signatureHelp",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 5, character: 18 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    signature = sent_messages.first[:result][:signatures].first
    expect(signature[:label]).to eq("build(name, count)")
  end

  # A signature help popup that lists parameters but never says which one
  # you are typing bolds the first one for the whole call, which is
  # actively misleading past the first comma -- the editor is asserting
  # something, and after `,` the assertion is wrong. The index is the
  # count of top-level commas between the call's `(` and the cursor:
  # commas nested inside another call's arguments, inside an array or
  # hash literal, or inside a string are not argument separators of this
  # call.
  describe "which parameter the cursor is on" do
    def active_parameter_for(argument_text)
      source = "class Widget\n  def build(name, count)\n  end\nend\n\nWidget.new.build(#{argument_text}\n"
      input =
        did_open("file:///widget.rb", source) +
        frame(
          jsonrpc: "2.0", id: 1, method: "textDocument/signatureHelp",
          params: { textDocument: { uri: "file:///widget.rb" },
                    position: { line: 5, character: 17 + argument_text.length } }
        ) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      build_server(input).run
      sent_messages.first[:result][:activeParameter]
    end

    it "is the first before any comma" do
      expect(active_parameter_for("")).to eq(0)
    end

    it "advances with each argument written" do
      expect(active_parameter_for('"a", ')).to eq(1)
    end

    it "ignores a comma belonging to a nested call" do
      expect(active_parameter_for("compute(1, 2)")).to eq(0)
    end

    it "ignores a comma inside an array literal" do
      expect(active_parameter_for("[1, 2], ")).to eq(1)
    end

    it "ignores a comma inside a hash literal" do
      expect(active_parameter_for("{ a: 1, b: 2 }")).to eq(0)
    end

    it "ignores a comma inside a string" do
      expect(active_parameter_for('"a, b"')).to eq(0)
    end
  end

  # Wiring MethodAnalyzer's return-type inference into LocalInferencer
  # (the Finding-1 fix above) needs its own cache invalidation: without
  # it, editing a method's body would keep hovering its *stale* return
  # type indefinitely, since MethodSummaryStore caches by SymbolId and
  # nothing else would ever tell it the body changed.
  it "reflects an edited method body's new return type on the next hover, not a stale cached one" do
    source = "class Widget\n  def build\n    1\n  end\nend\n\nWidget.new.build\n"
    input =
      did_open("file:///widget.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 6, character: 13 } }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didChange",
        params: {
          textDocument: { uri: "file:///widget.rb", version: 2 },
          contentChanges: [{ text: "class Widget\n  def build\n    \"str\"\n  end\nend\n\nWidget.new.build\n" }]
        }
      ) +
      frame(
        jsonrpc: "2.0", id: 2, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 6, character: 13 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    messages = sent_messages
    before_type = messages.find { |m| m[:id] == 1 }[:result][:type]
    after_type = messages.find { |m| m[:id] == 2 }[:result][:type]

    expect(before_type).to eq("Integer")
    expect(after_type).to eq("String")
  end

  # A follow-up review of the Finding-1 fix (MethodAnalyzer wiring) found
  # its cache invalidation only covered files that Server itself had
  # already reindexed at least once (didOpen/didChange/disk re-read) --
  # a file that was only ever Cold-Indexed (never opened, so its *first*
  # Server-side touch is an external disk edit) could get a method
  # summary cached against it (from some other open file's call chain)
  # and then never see that summary invalidated when the file changed on
  # disk, because the invalidation trigger lived in a Server-side shadow
  # hash Cold Index never wrote to. The fix derives "previous
  # declarations" from WorkspaceIndex itself (the one place every
  # populate path -- including Cold Index -- already writes through)
  # instead of a separately-maintained cache.
  it "invalidates a cached method summary for a file that was only ever cold-indexed, once it changes on disk" do
    Dir.mktmpdir do |root|
      b_path = File.join(root, "b.rb")
      File.write(b_path, "class B\n  def foo\n    1\n  end\nend\n")
      b_uri = Ovallsp::UriUtil.from_path(b_path)

      server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger, workspace_root: root)

      # Cold Index runs on a background thread and is the *only* thing
      # that has ever indexed b.rb at this point -- it never goes through
      # #reindex/#reindex_from_disk.
      server.send(:start_cold_index)
      b_symbol = Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::B", discriminator: nil)
      indexed = wait_until { !server.instance_variable_get(:@workspace_index).declarations(b_symbol).empty? }
      raise "cold index never picked up b.rb" unless indexed

      a_uri = "file:///a.rb"
      server.instance_variable_get(:@document_store).open(uri: a_uri, text: "B.new.foo\n", version: 1, language_id: "ruby")

      before = server.send(:explain_type_result, { textDocument: { uri: a_uri }, position: { line: 0, character: 7 } })
      expect(before).to eq(type: "Integer") # cached MethodAnalyzer summary for B#foo now exists

      File.write(b_path, "class B\n  def foo\n    \"str\"\n  end\nend\n")
      server.send(:handle_did_change_watched_files, { changes: [{ uri: b_uri, type: 2 }] }) # 2 = Changed

      after = server.send(:explain_type_result, { textDocument: { uri: a_uri }, position: { line: 0, character: 7 } })
      expect(after).to eq(type: "String")
    end
  end

  def wait_until(timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
  end

  it "reloads project RBS signatures after a watched .rbs change" do
    Dir.mktmpdir do |root|
      sig_dir = File.join(root, "sig")
      FileUtils.mkdir_p(sig_dir)
      signature_path = File.join(sig_dir, "widget.rbs")
      File.write(signature_path, "class Widget\n  def value: () -> String\nend\n")
      server = Ovallsp::Server.new(
        input: StringIO.new(""), output: output, logger: logger, workspace_root: root
      )
      signatures = server.instance_variable_get(:@signatures)
      symbol_id = Ovallsp::Index::SymbolId.new(
        kind: :instance_method, owner: "::Widget", name: "value", discriminator: nil
      )
      expect(signatures.method_signatures(symbol_id).overloads.first.return_type.to_s).to eq("String")
      generation = signatures.generation

      File.write(signature_path, "class Widget\n  def value: () -> Integer\nend\n")
      server.send(
        :handle_did_change_watched_files,
        { changes: [{ uri: Ovallsp::UriUtil.from_path(signature_path), type: 2 }] }
      )

      expect(signatures.generation).to be > generation
      expect(signatures.method_signatures(symbol_id).overloads.first.return_type.to_s).to eq("Integer")
    end
  end

  it "reloads project RBI signatures after a watched .rbi change" do
    Dir.mktmpdir do |root|
      rbi_dir = File.join(root, "sorbet", "rbi")
      FileUtils.mkdir_p(rbi_dir)
      signature_path = File.join(rbi_dir, "widget.rbi")
      File.write(signature_path, "class Widget\n  sig { returns(String) }\n  def value; end\nend\n")
      server = Ovallsp::Server.new(
        input: StringIO.new(""), output: output, logger: logger, workspace_root: root
      )
      signatures = server.instance_variable_get(:@signatures)
      symbol_id = Ovallsp::Index::SymbolId.new(
        kind: :instance_method, owner: "::Widget", name: "value", discriminator: nil
      )
      expect(signatures.method_signatures(symbol_id).overloads.first.return_type.to_s).to eq("String")

      File.write(signature_path, "class Widget\n  sig { returns(Integer) }\n  def value; end\nend\n")
      server.send(
        :handle_did_change_watched_files,
        { changes: [{ uri: Ovallsp::UriUtil.from_path(signature_path), type: 2 }] }
      )

      expect(signatures.method_signatures(symbol_id).overloads.first.return_type.to_s).to eq("Integer")
    end
  end
end
