# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe "Ovallsp::Server textDocument/references (Task 014)" do
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

  it "finds every call to a method, resolved through its receiver's type" do
    source = "class Widget\n  def build\n  end\nend\n\nw1 = Widget.new\nw1.build\nw2 = Widget.new\nw2.build\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 1, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    lines = result.map { |loc| loc[:range][:start][:line] }
    expect(lines).to contain_exactly(6, 8)
  end

  it "finds a local variable's references, and does not confuse it with a same-named local in a different method" do
    source = "def a\n  x = 1\n  x\nend\n\ndef b\n  x = 2\n  x\nend\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 2, character: 2 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    lines = result.map { |loc| loc[:range][:start][:line] }
    expect(lines).to contain_exactly(1, 2) # only scope `a`'s `x`, never scope `b`'s
  end

  it "finds references across multiple files" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\nend\n") +
      did_open("file:///user.rb", "Widget.new.build\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 1, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result.map { |loc| loc[:uri] }).to contain_exactly("file:///user.rb")
  end

  it "re-resolves an earlier callsite when its declaration is indexed later" do
    input =
      did_open("file:///user.rb", "Widget.new.build\n") +
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 1, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result].map { |loc| loc[:uri] }).to contain_exactly("file:///user.rb")
  end

  it "removes a file's references once it's closed and reverted, or deleted" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\nend\n") +
      did_open("file:///user.rb", "Widget.new.build\n") +
      frame(jsonrpc: "2.0", method: "textDocument/didClose", params: { textDocument: { uri: "file:///user.rb" } }) +
      frame(
        jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles",
        params: { changes: [{ uri: "file:///user.rb", type: 3 }] } # 3 = Deleted
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 1, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq([])
  end

  it "keeps an open buffer authoritative when a disk deletion notification arrives" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\nend\n") +
      did_open("file:///user.rb", "Widget.new.build\n") +
      frame(
        jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles",
        params: { changes: [{ uri: "file:///user.rb", type: 3 }] }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 1, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result].map { |entry| entry[:uri] }).to eq(["file:///user.rb"])
  end

  it "returns [] for a position with no reference candidate under the cursor" do
    input =
      did_open("file:///a.rb", "  \n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 1 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq([])
  end

  it "rebuilds references when a signature changes the receiver type" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      signature_path = File.join(root, "sig", "factory.rbs")
      File.write(signature_path, "class Widget\nend\nclass Gadget\nend\nclass Factory\n  def item: () -> Widget\nend\n")
      server = Ovallsp::Server.new(
        input: StringIO.new(""), output: output, logger: logger, workspace_root: root
      )
      sources = {
        "file:///types.rb" => "class Widget\n  def build; end\nend\nclass Gadget\n  def build; end\nend\nclass Factory\n  def item; end\nend\n",
        "file:///user.rb" => "Factory.new.item.build\n"
      }
      sources.each do |uri, text|
        document = server.instance_variable_get(:@document_store).open(
          uri: uri, text: text, version: 1, language_id: "ruby"
        )
        server.send(:reindex, document)
      end
      widget_params = {
        textDocument: { uri: "file:///types.rb" }, position: { line: 1, character: 6 }
      }
      gadget_params = {
        textDocument: { uri: "file:///types.rb" }, position: { line: 4, character: 6 }
      }
      expect(server.send(:references_result, widget_params).map { |entry| entry[:uri] }).to eq(["file:///user.rb"])

      File.write(signature_path, "class Widget\nend\nclass Gadget\nend\nclass Factory\n  def item: () -> Gadget\nend\n")
      server.send(
        :handle_did_change_watched_files,
        { changes: [{ uri: Ovallsp::UriUtil.from_path(signature_path), type: 2 }] }
      )

      expect(server.send(:references_result, widget_params)).to be_empty
      expect(server.send(:references_result, gadget_params).map { |entry| entry[:uri] }).to eq(["file:///user.rb"])
    end
  end

  # Deliberately white-box, because the contract it pins has no smaller
  # end-to-end expression: `refresh_models`/`refresh_routes` do NOT call
  # `mark_reference_index_dirty`, precisely because they run off the
  # dispatch thread; they rely on this generation vector noticing their
  # commit on the next query instead. Only the signature source is
  # covered by the spec above, so three of the six entries could be
  # deleted with the whole suite still green -- and a model refresh that
  # retargets an association would then serve references resolved
  # against the old model forever.
  it "counts a model, route or observation change as a reason to rebuild references" do
    server = build_server("")
    generation_of = -> { server.send(:reference_semantic_generation) }

    before_model = generation_of.call
    server.instance_variable_get(:@model_registry).register_from_agent_response(
      "User", { tableName: "users", partial: false, columns: [], associations: [] }
    )
    expect(generation_of.call).not_to eq(before_model)

    before_routes = generation_of.call
    server.instance_variable_get(:@route_registry).replace([])
    expect(generation_of.call).not_to eq(before_routes)

    before_observations = generation_of.call
    server.instance_variable_get(:@observation_store).replace_run([])
    expect(generation_of.call).not_to eq(before_observations)
  end

  # Resolution runs *outside* the state lock, so a model/route/signature
  # commit can land while it is in flight. The dirty token alone does not
  # notice that: those refreshes deliberately never touch it. Without the
  # commit-side generation compare, the build resolved against the old
  # semantics would be installed and then marked current, so the stale
  # references would survive until something else dirtied the index.
  it "discards a reference build whose semantic inputs changed while it was resolving" do
    server = build_server("")
    document = server.instance_variable_get(:@document_store).open(
      uri: "file:///user.rb", text: "Widget.new.build\n", version: 1, language_id: "ruby"
    )
    server.send(:reindex, document)

    resolver = server.instance_variable_get(:@reference_resolver)
    passes = 0
    allow(resolver).to receive(:resolve).and_wrap_original do |original, *args, **kwargs|
      passes += 1
      if passes == 1
        # A model refresh commits mid-resolution, once.
        server.instance_variable_get(:@model_registry).register_from_agent_response(
          "User", { tableName: "users", partial: false, columns: [], associations: [] }
        )
      end
      original.call(*args, **kwargs)
    end

    server.send(:ensure_reference_index_current)

    expect(passes).to be >= 2
  end

  it "clears a URI's old reference contribution when rebuilding that URI fails" do
    server = build_server("")
    {
      "file:///widget.rb" => "class Widget\n  def build\n  end\nend\n",
      "file:///user.rb" => "Widget.new.build\n"
    }.each do |uri, text|
      document = server.instance_variable_get(:@document_store).open(
        uri: uri, text: text, version: 1, language_id: "ruby"
      )
      server.send(:reindex, document)
    end
    params = {
      textDocument: { uri: "file:///widget.rb" }, position: { line: 1, character: 6 }
    }
    expect(server.send(:references_result, params)).not_to be_empty

    resolver = server.instance_variable_get(:@reference_resolver)
    allow(resolver).to receive(:resolve).and_raise("resolver failed")
    server.send(:mark_reference_index_dirty)

    expect(server.send(:references_result, params)).to be_empty
  end
end
