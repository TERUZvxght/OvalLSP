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

  # The scan that finds which call the cursor is inside. `activeParameter`
  # -- which parameter within it -- was built on the same tokens during
  # 0.2.1's review loop and is deferred to 0.3.0 with its capability row;
  # what stays is the scan itself, which fixes a 0.2.0 regression where a
  # call that had already closed before the cursor won.
  describe "which call the cursor is inside" do
    # The cursor is at the end of the written text, wherever that lands --
    # `argument_text` may span lines, and a call left open across a line
    # break is the ordinary case for signature help.
    def signature_help_for(argument_text)
      source = "class Widget\n  def build(name, count)\n  end\nend\n\nWidget.new.build(#{argument_text}\n"
      lines = source.lines
      line = lines.length - 1
      input =
        did_open("file:///widget.rb", source) +
        frame(
          jsonrpc: "2.0", id: 1, method: "textDocument/signatureHelp",
          params: { textDocument: { uri: "file:///widget.rb" },
                    position: { line: line, character: lines[line].chomp.length } }
        ) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      build_server(input).run
      sent_messages.first[:result]
    end

    def signature_labels_for(argument_text)
      signature_help_for(argument_text).fetch(:signatures).map { |signature| signature[:label] }
    end

    # The scan that *finds* the call and the scan that counts commas
    # inside it are two questions about the same text, and 0.2.1 shipped
    # them as two scanners that disagreed about what a paren is: the
    # comma count skipped string literals, the call scan did not. So an
    # unpaired paren in a string -- `"smile :("`, `sprintf("%d)", x)`, a
    # half-typed one -- made the popup vanish, and an unpaired `(` inside
    # a nested call's argument made it answer with the *inner* call, which
    # is the wrong answer where 0.2.0 had silence.
    it "finds the call when an earlier argument holds an unpaired paren in a string" do
      expect(signature_labels_for('"Destroy (permanently", 2')).to include("build(name, count)")
    end

    it "finds the call when an earlier argument holds an unpaired close paren in a string" do
      expect(signature_labels_for('"a)b", 2')).to include("build(name, count)")
    end

    it "does not answer with an inner call because of a paren inside its string argument" do
      expect(signature_labels_for('label("x(") , 2')).to include("build(name, count)")
    end

    it "ignores a paren in a trailing comment" do
      expect(signature_labels_for("1, # (not a call\n    2")).to include("build(name, count)")
    end

    it "does not treat a `(` inside a `%w` literal as opening a call" do
      expect(signature_labels_for("%w[a (b], 2")).to include("build(name, count)")
    end

    # A budget rather than a benchmark: the number below is three orders
    # of magnitude above what this costs and still catches the regression
    # it exists for.
    #
    # 0.2.1 made the backward scan stop at the first *unmatched* `(`,
    # which is correct and removed the early exit -- with the parens
    # before the cursor balanced there is nothing to stop at, so the loop
    # ran to offset 0. It asked a per-character mask about each character
    # on the way, and `text[idx]` on a string Ruby has classed as
    # multibyte is not constant time. Measured on a 603 KB file with one
    # Japanese comment in it: **8.0 seconds** to answer that there is no
    # signature, on a single-threaded server, with completion and
    # diagnostics queued behind it. Reachable by pressing the signature
    # help shortcut anywhere the parens happen to balance.
    it "answers a position with no enclosing call quickly, on a large file with a multibyte character in it" do
      body = (1..8000).map { |i| "  def m#{i}(a, b)\n    x = a + b\n    x\n  end\n" }.join
      source = "class Big\n  # 日本語のコメント\n#{body}end\n"
      document = Ovallsp::TextDocument.new(uri: "file:///big.rb", text: source, version: 1, language_id: "ruby")
      server = Ovallsp::Server.allocate
      position = { line: source.lines.length - 2, character: 4 }
      server.send(:enclosing_call_name_range, document, position)

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      3.times { server.send(:enclosing_call_name_range, document, position) }
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed) / 3

      # perf-guard: this runs on every hover, so a re-scan per call would be felt
      expect(elapsed).to be < 1.0, "#{(elapsed * 1000).round} ms per call to answer that there is no enclosing call"
    end

    # The *cold* half of the same cost, which the example above cannot
    # see: its cache is keyed on the document version, so an editor pays
    # this on every keystroke. Prism reports byte offsets and these scans
    # count characters, and converting each with `byteslice(0, n).length`
    # is O(offsets x filesize) -- 13 seconds on a 530 KB file with one
    # Japanese comment in it, four times worse with every doubling, while
    # its ASCII twin cost 21 ms.
    it "converts a multibyte file's token offsets in one pass, not one pass per token" do
      body = (1..3000).map { |i| "  def m#{i}(a, b)\n    x = a + b\n    x\n  end\n" }.join
      source = "class Big\n  # 日本語のコメント\n#{body}end\n"
      server = Ovallsp::Server.allocate

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      server.send(:compute_structural_tokens, source)
      server.send(:compute_non_code_spans, source)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed

      # perf-guard: one pass over a large file, not one per token
      expect(elapsed).to be < 2.0, "#{(elapsed * 1000).round} ms to index a #{source.bytesize / 1024} KB file once"
    end

    it "still finds the call after a parenthesised argument" do
      expect(signature_labels_for("(1 + 2), ")).to include("build(name, count)")
    end

    # `puts (1)` -- a space before the parenthesis -- opens with a token
    # of its own and closes with the same one a call's argument list
    # does, so an opener the call scan ignored left that pair unbalanced
    # and the popup vanished for the rest of the line.
    it "still finds the call after an argument written with a space before its parenthesis" do
      expect(signature_labels_for("puts (1), ")).to include("build(name, count)")
    end

    # An *unmatched* opener -- the cursor inside a literal whose call is
    # still open -- drove the depth negative, so the scan kept walking
    # past the real call and out into earlier lines. Two things came of
    # it: `alpha([1, |2], 3)` answered nothing where 0.2.0 answered, and
    # a cursor inside a literal with no enclosing call at all re-balanced
    # against an earlier statement and answered with a call it is nowhere
    # near. Depth cannot go below zero: there is no such thing as being
    # more closed than closed.
    it "finds the call when the cursor is inside an unclosed argument literal" do
      expect(signature_labels_for("[1, ")).to include("build(name, count)")
    end

    it "finds the call when the cursor is inside an unclosed hash argument" do
      expect(signature_labels_for("{ a: 1, ")).to include("build(name, count)")
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

  # `024.88`. `QueryService#members_of` decides `conditional` correctly --
  # true for exactly the members present on one branch of a union and not
  # the other, and it sorts them after the ones on both. The completion
  # response then threw that away: every item carried the same four keys
  # and nothing told `upcase` from `succ`.
  #
  # Ruby, run rather than reasoned about:
  #
  #   $ ruby -e '
  #   p [1.respond_to?(:upcase), "s".respond_to?(:even?), "s".respond_to?(:upcase)]
  #   '
  #   # => [false, false, true]
  #   # ruby 3.4.10
  #
  # So accepting `upcase` on `cond ? "s" : 1` raises NoMethodError on one
  # branch, and the list gave the user nothing to see that with.
  describe "completion on a union receiver" do
    def union_items
      input =
        did_open("file:///u.rb", "cond = [true, false].sample\nx = cond ? \"s\" : 1\nx.\n") +
        frame(
          jsonrpc: "2.0", id: 1, method: "textDocument/completion",
          params: { textDocument: { uri: "file:///u.rb" }, position: { line: 2, character: 2 } }
        ) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      build_server(input).run
      sent_messages.first[:result][:items]
    end

    it "marks a member that only one branch of the union has" do
      item = union_items.find { |i| i[:label] == "upcase" }

      expect(item).to include(sortText: a_string_starting_with("1"))
    end

    it "does not mark a member both branches have" do
      item = union_items.find { |i| i[:label] == "succ" }

      expect(item[:sortText]).to start_with("0")
    end

    # The distinguishing pair. Without both, the examples above would
    # pass on a server that marked everything, or nothing, and on one
    # that offered no items at all.
    it "offers both kinds, and orders the ones every branch has first" do
      items = union_items
      labels = items.map { |i| i[:label] }

      aggregate_failures do
        expect(labels).to include("upcase", "succ")
        expect(items.map { |i| i[:sortText].to_s[0] }.uniq.sort).to eq(%w[0 1])
        expect(items.each_cons(2).all? { |a, b| a[:sortText].to_s <= b[:sortText].to_s }).to be(true)
      end
    end
  end
end
