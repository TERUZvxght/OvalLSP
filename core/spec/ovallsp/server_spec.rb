# frozen_string_literal: true

require "stringio"

RSpec.describe Ovallsp::Server do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    described_class.new(input: StringIO.new(input_string), output: output, logger: logger)
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  it "completes the initialize handshake and reports hover/shutdown/exit results" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", method: "initialized", params: {}) +
      frame(
        jsonrpc: "2.0", id: 2, method: "textDocument/hover",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 0 } }
      ) +
      frame(jsonrpc: "2.0", id: 3, method: "shutdown", params: nil) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    exit_code = build_server(input).run

    expect(exit_code).to eq(0)

    messages = sent_messages
    expect(messages[0]).to include(id: 1)
    expect(messages[0][:result][:capabilities][:hoverProvider]).to eq(true)
    expect(messages[1]).to include(id: 2)
    # A document that was never opened has nothing to hover -- an empty,
    # non-committal result rather than a guess (Task 013).
    expect(messages[1][:result][:contents][:value]).to eq("")
    expect(messages[2]).to include(id: 3, result: nil)
  end

  it "reports ovallspInfo (Task 023.2's Extension/Core version handshake) alongside serverInfo on initialize" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "shutdown", params: nil) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    info = sent_messages[0][:result][:ovallspInfo]
    expect(info[:coreVersion]).to eq(Ovallsp::VERSION)
    expect(info[:protocol]).to eq(
      current: Ovallsp::ProtocolVersion::CURRENT,
      minimumClient: Ovallsp::ProtocolVersion::MINIMUM_CLIENT,
      maximumClient: Ovallsp::ProtocolVersion::MAXIMUM_CLIENT,
      minimumServer: Ovallsp::ProtocolVersion::MINIMUM_SERVER,
      maximumServer: Ovallsp::ProtocolVersion::MAXIMUM_SERVER
    )
    expect(info[:ruby]).to eq(engine: RUBY_ENGINE, version: RUBY_VERSION, platform: RUBY_PLATFORM)
    # No PLATFORM_MANIFEST.json in a dev checkout (this spec's own working
    # directory is never a packaged VSIX) -- `build` must be nil, not a
    # hash of missing/nil sub-fields, so a client can tell "no manifest at
    # all" apart from "manifest present but incomplete".
    expect(info[:build]).to be_nil
  end

  it "answers textDocument/hover with the inferred type, plus origin/definition for a receiver-qualified call (Task 013)" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: {
          textDocument: { uri: "file:///widget.rb", text: "class Widget\n  def build\n  end\nend\n\nWidget.new.build\n",
                           version: 1, languageId: "ruby" }
        }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/hover",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 5, character: 13 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    value = sent_messages.first[:result][:contents][:value]
    expect(value).to include("Origin: source declaration")
    expect(value).to include("Defined: file:///widget.rb:2")
  end

  it "tracks document versions through didOpen/didChange" do
    document_store = nil
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "a = 1\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didChange",
        params: {
          textDocument: { uri: "file:///a.rb", version: 2 },
          contentChanges: [{ text: "a = 2\n" }]
        }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    server = build_server(input)
    server.instance_variable_get(:@document_store).tap { |store| document_store = store }
    server.run

    doc = document_store.fetch(uri: "file:///a.rb")
    expect(doc.text).to eq("a = 2\n")
    expect(doc.version).to eq(2)
  end

  it "answers textDocument/documentSymbol with a hierarchical result after didOpen" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file:///user.rb",
            text: "class User\n  def name\n  end\nend\n",
            version: 1,
            languageId: "ruby"
          }
        }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///user.rb" } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result.size).to eq(1)
    expect(result.first[:name]).to eq("User")
    expect(result.first[:children].first[:name]).to eq("name")
  end

  it "returns an empty documentSymbol result for a uri that was never opened" do
    input =
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///missing.rb" } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq([])
  end

  it "returns MethodNotFound for an unknown request instead of crashing" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "textDocument/thisMethodDoesNotExist", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    messages = sent_messages
    expect(messages[0][:error]).to include(code: -32601)
    expect(messages[1]).to include(id: 2)
  end

  it "logs and continues after a notification handler raises" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didChange",
        params: {
          textDocument: { uri: "file:///missing.rb", version: 2 },
          contentChanges: [{ text: "x" }]
        }
      ) +
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect { build_server(input).run }.not_to raise_error
    expect(logger).to have_received(:error)

    messages = sent_messages
    expect(messages[0]).to include(id: 1)
  end

  it "exits with status 1 when exit arrives without a prior shutdown" do
    input = frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect(build_server(input).run).to eq(1)
  end

  it "resolves textDocument/definition for an identifier by lexical name" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file:///user.rb",
            text: "class User\nend\n",
            version: 1,
            languageId: "ruby"
          }
        }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file:///app.rb",
            text: "User.new\n",
            version: 1,
            languageId: "ruby"
          }
        }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///app.rb" }, position: { line: 0, character: 1 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result).to eq([{ uri: "file:///user.rb", range: { start: { line: 0, character: 0 }, end: { line: 1, character: 3 } } }])
  end

  # The receiverless path answers "where does a call with no receiver
  # go", and the thing that tells it a call has no receiver is the text
  # to the left of the word. Without that check the path also runs for
  # `something.article_params`, where it asks the *enclosing* class for a
  # method of that name -- so a call on a receiver whose type is unknown
  # jumps into the file you are already in, at a method that has nothing
  # to do with it. Silence is the correct answer here; a confident wrong
  # jump is worse than none.
  it "does not answer textDocument/definition from the enclosing class for a call on an untyped receiver" do
    source = "class ArticlesController\n  def create\n    thing.article_params\n  end\n\n  def article_params\n  end\nend\n"
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///articles_controller.rb", text: source, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///articles_controller.rb" }, position: { line: 2, character: 12 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq([])
  end

  it "returns [] for textDocument/definition when no word is under the cursor" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "  \n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 1 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq([])
  end

  it "answers workspace/symbol with matches across all open files" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///user.rb", text: "class User\nend\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "workspace/symbol",
        params: { query: "Us" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result).to contain_exactly(a_hash_including(name: "User", kind: 5))
  end

  it "keeps an open buffer's workspace index contribution on a Deleted watched-file notification" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///user.rb", text: "class User\nend\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles",
        params: { changes: [{ uri: "file:///user.rb", type: 3 }] }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "workspace/symbol",
        params: { query: "User" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to contain_exactly(a_hash_including(name: "User", kind: 5))
  end

  it "answers the custom ovallsp/explainType request with the inferred type" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "user = User.new\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 1 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "User")
  end

  # Task 013's QueryContext existed (matching the design doc's required
  # interface) but was never actually constructed or consulted anywhere
  # -- a follow-up review of Tasks 009-013 flagged it as orphaned. These
  # exercise the fix directly: Server now builds one per hover/explainType
  # request and checks it for staleness afterward.
  # Every read request answers from several indexes at once (workspace,
  # hierarchy, references, generated methods, model registry, signature
  # environment). Off this lock, a Cold Index callback or a model refresh
  # can commit between two of those reads inside a single request, so
  # hover and completion at the same position can be answered from
  # different index states. The pairing is exactly what the LSP client
  # then shows as an inconsistent type.
  describe "read requests answer from one index snapshot" do
    {
      "textDocument/hover" => :hover_result,
      "textDocument/documentSymbol" => :document_symbol_result,
      "textDocument/definition" => :definition_result,
      "workspace/symbol" => :workspace_symbol_result,
      "ovallsp/explainType" => :explain_type_result,
      "textDocument/completion" => :completion_result,
      "textDocument/signatureHelp" => :signature_help_result,
      "textDocument/references" => :references_result,
      "textDocument/prepareRename" => :prepare_rename_result,
      "textDocument/rename" => :rename_result,
      "ovallsp/showTypeEvidence" => :show_type_evidence_result
    }.each do |lsp_method, result_method|
      it "holds the index lock for the whole of #{lsp_method}" do
        input =
          frame(
            jsonrpc: "2.0", id: 1, method: lsp_method,
            params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 0 }, query: "" }
          ) +
          frame(jsonrpc: "2.0", method: "exit", params: nil)
        server = build_server(input)
        held = nil
        allow(server).to receive(result_method) do |*|
          held = server.instance_variable_get(:@index_mutation_mutex).owned?
          nil
        end

        server.run

        expect(held).to be(true)
      end
    end
  end

  # `rbs_collection.lock.yaml` decides *which* gem RBS get loaded, so it
  # belongs in the fingerprint that decides whether the on-disk summary
  # cache is still valid. Dropping it means `rbs collection update` can
  # change every gem signature while nothing under sig/ or sorbet/rbi/
  # moves, leaving the cache from the previous signature set in use.
  describe "#rbs_digest" do
    def digest_for(root)
      described_class.new(
        input: StringIO.new(""), output: output, logger: logger, workspace_root: root
      ).send(:rbs_digest)
    end

    it "fingerprints the RBS collection lockfile even when the workspace has no sig/ directory" do
      Dir.mktmpdir do |root|
        lockfile = File.join(root, "rbs_collection.lock.yaml")
        File.write(lockfile, "gems: []\n")

        expect(digest_for(root)).not_to be_nil
      end
    end

    it "changes when the RBS collection lockfile changes" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "sig"))
        File.write(File.join(root, "sig", "a.rbs"), "class A\nend\n")
        lockfile = File.join(root, "rbs_collection.lock.yaml")
        File.write(lockfile, "gems: []\n")
        before = digest_for(root)

        File.write(lockfile, "gems:\n  - name: activesupport\n")
        FileUtils.touch(lockfile, mtime: Time.now + 2)

        expect(digest_for(root)).not_to eq(before)
      end
    end
  end

  describe "QueryContext wiring (Task 013 review fix)" do
    let(:server) { build_server("") }

    it "#build_query_context captures the current workspace/signature generations" do
      query_context = server.send(:build_query_context, "file:///a.rb", { line: 0, character: 0 })

      expect(query_context.workspace_generation).to eq(server.instance_variable_get(:@workspace_index).generation)
      expect(query_context.signature_generation).to eq(server.instance_variable_get(:@signatures).generation)
    end

    it "#warn_if_stale logs a warning when the workspace generation moved on since the context was built" do
      query_context = server.send(:build_query_context, "file:///a.rb", { line: 0, character: 0 })
      allow(server.instance_variable_get(:@workspace_index)).to receive(:generation).and_return(
        query_context.workspace_generation + 1
      )

      expect(logger).to receive(:warn).with(a_string_matching(/became stale/))
      server.send(:warn_if_stale, query_context)
    end

    it "#warn_if_stale does not log when nothing has changed" do
      query_context = server.send(:build_query_context, "file:///a.rb", { line: 0, character: 0 })

      expect(logger).not_to receive(:warn)
      server.send(:warn_if_stale, query_context)
    end
  end
end
