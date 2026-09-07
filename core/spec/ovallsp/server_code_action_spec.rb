# frozen_string_literal: true

require "stringio"
require "open3"

# 0.3.0's `textDocument/codeAction`. Every example drives the real
# server: it publishes the diagnostics, hands the published diagnostic
# straight back in the code-action context the way a client does, and
# then *applies* the edit and checks what the file now says. Asserting
# that the result parses is not enough -- two of the defects here left a
# file that parses and does not run.
RSpec.describe "Ovallsp::Server textDocument/codeAction" do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def messages_from(output)
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    all = []
    loop { all << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    all
  end

  # Publish diagnostics for `source`, then ask for the actions offered
  # against each one. Returns `[[title, edit_changes], ...]`.
  def actions(source, uri: "file:///a.rb", diagnostic_overrides: {})
    published = drive(source, uri: uri) { [] }
    published.map { |d| d.merge(diagnostic_overrides) }.flat_map do |diagnostic|
      drive(source, uri: uri) do |_|
        [frame(jsonrpc: "2.0", id: 2, method: "textDocument/codeAction",
               params: { textDocument: { uri: uri }, range: diagnostic[:range],
                         context: { diagnostics: [diagnostic] } })]
      end
    end
  end

  # Runs one server. With no follow-up frames it returns the published
  # diagnostics; with them, the result of the last request.
  def drive(source, uri: "file:///a.rb")
    output = StringIO.new
    follow_up = yield(nil)
    input =
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: uri, text: source, version: 1, languageId: "ruby" } }) +
      follow_up.join +
      frame(jsonrpc: "2.0", method: "exit", params: nil)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run

    all = messages_from(output)
    if follow_up.empty?
      all.select { |m| m[:method] == "textDocument/publishDiagnostics" }
         .flat_map { |m| Array(m.dig(:params, :diagnostics)) }
    else
      Array(all.find { |m| m[:id] == 2 }&.[](:result))
    end
  end

  def apply(source, edit, uri: "file:///a.rb")
    changes = edit[:edit][:changes][uri.to_sym]
    lines = source.lines
    changes.sort_by { |e| [-e[:range][:start][:line], -e[:range][:start][:character]] }.each do |change|
      from = change[:range][:start]
      to = change[:range][:end]
      if from[:line] == to[:line]
        lines[from[:line]] = lines[from[:line]].dup
        lines[from[:line]][from[:character]...to[:character]] = change[:newText]
      else
        head = lines[from[:line]][0...from[:character]]
        tail = lines[to[:line]][to[:character]..]
        lines[from[:line]..to[:line]] = ["#{head}#{change[:newText]}#{tail}"]
      end
    end
    lines.join
  end

  describe "auto-require" do
    let(:root) { example_tmpdir("ovallsp-auto-require") }
    let(:uri) { Ovallsp::UriUtil.from_path(File.join(root, "example.rb")) }
    let(:output) { StringIO.new }
    let(:server) { Ovallsp::Server.new(input: StringIO.new, output: output, logger: logger, workspace_root: root) }

    after { server.send(:shutdown_background_tasks) }

    def start_auto_require(document_changes: true, wait_for_index: true)
      # Join the real cold index, so the request observes all on-disk
      # declarations without a timing-dependent sleep or a fabricated index.
      allow(server).to receive(:start_cold_index).and_wrap_original do |original|
        @cold_thread = original.call
        @cold_thread&.join if wait_for_index
      end
      server.send(:dispatch, jsonrpc: "2.0", id: 1, method: "initialize", params: {
        rootUri: Ovallsp::UriUtil.from_path(root),
        capabilities: { workspace: { workspaceEdit: { documentChanges: document_changes } } }
      })
    end

    def open_for_auto_require(source, language_id: "ruby")
      server.send(:dispatch, method: "textDocument/didOpen", params: {
        textDocument: { uri: uri, text: source, version: 7, languageId: language_id }
      })
    end

    def auto_require_actions(range: { start: { line: 0, character: 0 }, end: { line: 100, character: 0 } },
                             diagnostics: [], only: nil)
      context = { diagnostics: diagnostics }
      context[:only] = only unless only.nil?
      server.send(:dispatch, jsonrpc: "2.0", id: 2, method: "textDocument/codeAction", params: {
        textDocument: { uri: uri }, range: range, context: context
      })
      answer = messages_from(output).reverse.find { |m| m[:id] == 2 }
      expect(answer).not_to have_key(:error)
      answer.fetch(:result)
    end

    def apply_auto_require(source, action)
      change = action.fetch(:edit).fetch(:documentChanges).fetch(0)
      expect(change.fetch(:textDocument)).to eq(uri: uri, version: 7)
      document = Ovallsp::TextDocument.new(uri: uri, text: source, version: 7, language_id: "ruby")
      change.fetch(:edits).each do |edit|
        document = document.with_incremental_change(range: edit.fetch(:range), new_text: edit.fetch(:newText), version: 8)
      end
      document.text
    end

    {
      "json" => ['puts JSON.generate({a: 1})', "{\"a\":1}\n"],
      "uri" => ['puts URI.parse("https://example.test").host', "example.test\n"],
      "pathname" => ['puts Pathname.new("a").to_s', "a\n"]
    }.each do |path, (expression, expected)|
      it "offers #{path} without a diagnostic and the versioned edit runs in isolated Ruby" do
        source = "#{expression}\n"
        start_auto_require
        open_for_auto_require(source)
        diagnostics = messages_from(output).select { |m| m[:method] == "textDocument/publishDiagnostics" }
        expect(diagnostics.flat_map { |m| m.dig(:params, :diagnostics) }).to be_empty
        _out, error, status = Open3.capture3(TestEnvironment.clean_env, RbConfig.ruby, "-e", source, chdir: root)
        expect(status.success?).to be(false)
        expect(error).to include("uninitialized constant")

        offered = auto_require_actions
        expect(offered.map { |a| [a[:title], a[:kind]] }).to eq([["Add require '#{path}'", "quickfix"]])
        expect(offered.first).not_to have_key(:isPreferred)
        fixed = apply_auto_require(source, offered.first)
        expect(Prism.parse(fixed).errors).to be_empty
        out, error, status = Open3.capture3(TestEnvironment.clean_env, RbConfig.ruby, "-e", fixed, chdir: root)
        expect(status.success?).to be(true), error
        expect(out).to eq(expected)

        server.send(:dispatch, method: "textDocument/didChange", params: {
          textDocument: { uri: uri, version: 8 }, contentChanges: [{ text: fixed }]
        })
        expect(auto_require_actions).to eq([])
      end
    end

    it "uses a cursor range, deduplicates references and preserves CRLF and magic headers" do
      source = "#!/usr/bin/env ruby\r\n# encoding: UTF-8\r\n# frozen_string_literal: true\r\nputs ::JSON.generate('日本語😀'); JSON\r\n"
      start_auto_require
      open_for_auto_require(source)
      range = { start: { line: 3, character: 9 }, end: { line: 3, character: 9 } }
      offered = auto_require_actions(range: range, only: ["quickfix"])
      expect(offered.length).to eq(1)
      fixed = apply_auto_require(source, offered.first)
      expect(fixed).to eq(source.sub("puts", "require \"json\"\r\nputs"))
      expect(auto_require_actions.length).to eq(1)
    end

    it "selects a current reference from a diagnostic range and ignores its message" do
      start_auto_require
      open_for_auto_require("JSON\n")
      diagnostic = { source: "ovallsp", code: "unresolved-constant", message: "Missing URI",
                     range: { start: { line: 0, character: 0 }, end: { line: 0, character: 4 } } }
      outside = { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } }
      expect(auto_require_actions(range: outside, diagnostics: [diagnostic]).map { |a| a[:title] })
        .to eq(["Add require 'json'"])
      open_for_auto_require("nil\n")
      expect(auto_require_actions(range: outside, diagnostics: [diagnostic])).to eq([])
    end

    {
      "a double-quoted require" => "require \"json\"\nJSON\n",
      "a parenthesized require" => "require('json')\nJSON\n",
      "a Kernel require" => "Kernel.require 'json'\nJSON\n",
      "a dynamic require" => "require ENV.fetch('LIB')\nJSON\n",
      "a conditional require" => "require 'json' if false\nJSON\n",
      "an unrelated conditional require" => "require 'uri' if false\nJSON\n",
      "autoload" => "autoload :JSON, 'custom_json'\nJSON\n",
      "a late require" => "puts JSON.generate(1)\nrequire 'uri'\n",
      "a require inside a method" => "def f\n  require 'uri'\nend\nJSON\n",
      "a require-looking line inside a heredoc" => "text = <<~TEXT\nrequire 'zlib'\nTEXT\nJSON\n",
      "a constant assignment" => "JSON = Object.new\nJSON\n",
      "a class declaration" => "class JSON; end\nJSON\n",
      "a foreign qualified constant" => "Other::JSON\n",
      "a nested bare constant" => "module Other; JSON; end\n",
      "a string" => "'JSON'\n",
      "a comment" => "# JSON\n",
      "broken syntax" => "JSON.\n",
      "a BEGIN hook" => "BEGIN { JSON }\n",
      "an empty document" => ""
    }.each do |reason, source|
      it "declines for #{reason}" do
        start_auto_require
        open_for_auto_require(source)
        expect(auto_require_actions).to eq([])
      end
    end

    it "does not treat a require in a comment as an existing require" do
      start_auto_require
      source = "# require 'json'\nJSON"
      open_for_auto_require(source)
      fixed = apply_auto_require(source, auto_require_actions.fetch(0))
      expect(fixed).to eq("require \"json\"\n#{source}")
    end

    it "inserts beside leading static requires before executing any code" do
      start_auto_require
      source = "require 'uri'\nputs JSON.generate(1)\n"
      open_for_auto_require(source)
      fixed = apply_auto_require(source, auto_require_actions.fetch(0))
      expect(fixed).to eq("require \"json\"\n#{source}")
    end

    it "declines when another workspace file declares the same constant" do
      File.write(File.join(root, "custom.rb"), "module Other; JSON = Object.new; end\n")
      start_auto_require
      open_for_auto_require("JSON\n")
      expect(auto_require_actions).to eq([])
    end

    it "waits for the cold index to finish before proposing an import" do
      entered = Queue.new
      resume = Queue.new
      allow(Ovallsp::ColdIndexer).to receive(:new).and_wrap_original do |original, **options|
        original.call(**options).tap do |indexer|
          allow(indexer).to receive(:run).and_wrap_original do |run|
            entered << true
            resume.pop
            run.call
          end
        end
      end
      start_auto_require(wait_for_index: false)
      entered.pop
      open_for_auto_require("JSON\n")
      expect(auto_require_actions).to eq([])
      resume << true
      @cold_thread.join
      expect(auto_require_actions.map { |a| a[:title] }).to eq(["Add require 'json'"])
    ensure
      resume << true
    end

    it "declines after an incomplete cold index" do
      File.write(File.join(root, "unreadable.rb"), "JSON = Object.new\n")
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(File.join(root, "unreadable.rb"), encoding: Encoding::UTF_8).and_raise(Errno::EACCES)
      expect(logger).to receive(:error).with(/cold index: failed to index .*unreadable\.rb: Errno::EACCES/)
      start_auto_require
      open_for_auto_require("JSON\n")
      expect(auto_require_actions).to eq([])
    end

    it "declines while an Agent is starting" do
      start_auto_require
      open_for_auto_require("JSON\n")
      server.instance_variable_set(:@agent_bootstrap_pending, true)
      expect(auto_require_actions).to eq([])
    end

    it "does not reuse a summary for a different document version" do
      start_auto_require
      open_for_auto_require("JSON\n")
      server.instance_variable_get(:@document_store).change(uri: uri, version: 8, changes: [{ text: "nil\n" }])
      expect(auto_require_actions).to eq([])
    end

    it "declines for a document outside the workspace" do
      start_auto_require
      other_uri = Ovallsp::UriUtil.from_path(File.join(example_tmpdir("ovallsp-auto-require-other"), "example.rb"))
      allow(self).to receive(:uri).and_return(other_uri)
      open_for_auto_require("JSON\n")
      expect(auto_require_actions).to eq([])
    end

    it "declines when the client cannot apply versioned document changes" do
      start_auto_require(document_changes: false)
      open_for_auto_require("JSON\n")
      expect(auto_require_actions).to eq([])
    end

    it "honours context.only and the selected range" do
      start_auto_require
      open_for_auto_require("JSON\nURI\n")
      expect(auto_require_actions(only: ["refactor"])).to eq([])
      expect(auto_require_actions(only: ["quickfix.other"])).to eq([])
      expect(auto_require_actions(only: [""]).length).to eq(2)
      range = { start: { line: 1, character: 1 }, end: { line: 1, character: 1 } }
      expect(auto_require_actions(range: range).map { |a| a[:title] }).to eq(["Add require 'uri'"])
    end

    it "declines for an ERB document" do
      start_auto_require
      open_for_auto_require("JSON\n", language_id: "erb")
      expect(auto_require_actions).to eq([])
    end

    %w[Gemfile gems.rb .ruby-version .tool-versions mise.toml].each do |marker|
      it "declines when #{marker} leaves the plain Ruby environment unproven" do
        File.write(File.join(root, marker), "")
        start_auto_require
        open_for_auto_require("JSON\n")
        expect(auto_require_actions).to eq([])
      end
    end

    %w[bin/rails config/environment.rb].each do |marker|
      it "declines for an incomplete Rails workspace with #{marker}" do
        path = File.join(root, marker)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "")
        start_auto_require
        open_for_auto_require("JSON\n")
        expect(auto_require_actions).to eq([])
      end
    end

    context "in a real Rails app", :real_rails do
      extend RealRailsFixture
      let(:root) { self.class.workspace }

      before do
        skip "Rails/sqlite3 not available as local gems" unless self.class.available?
      end

      it "declines with no Agent without executing or loading anything" do
        start_auto_require
        open_for_auto_require("JSON\n")
        expect(Ovallsp::RailsBootstrap).not_to receive(:start)
        expect(Open3).not_to receive(:capture3)
        expect(auto_require_actions).to eq([])
      end

      it "declines for a loaded constant with a real ready Agent and after it stops" do
        manager = Ovallsp::RailsBootstrap.start(root: root, logger: logger,
          route_registry: Ovallsp::Routes::RouteRegistry.new, model_registry: Ovallsp::Models::ModelRegistry.new)
        expect(manager.ready?).to be(true)
        expect(manager.fetch_ancestors(["JSON"]).fetch(:classes).fetch(:JSON)).to have_key(:ancestors)
        start_auto_require
        open_for_auto_require("JSON\n")
        # Finish unrelated diagnostics before observing just CodeAction's
        # effect on the independently booted, still-ready real Agent.
        server.send(:shutdown_background_tasks)
        server.instance_variable_set(:@agent_manager, manager)
        expect(manager).not_to receive(:fetch_ancestors)
        expect(manager).not_to receive(:fetch_gem_index)
        expect(Ovallsp::RailsBootstrap).not_to receive(:start)
        expect(auto_require_actions).to eq([])
        manager.stop
        expect(auto_require_actions).to eq([])
      ensure
        manager&.stop
      end
    end
  end

  # Whether the applied file really defines the method, which is the
  # property the fix claims. `Prism.parse(...).success?` cannot see it:
  # a `def` inserted after the class's `end` parses perfectly.
  def defines?(applied, klass, method)
    sandbox = ::Module.new
    sandbox.module_eval(applied)
    sandbox.const_get(klass).instance_methods(false).include?(method)
  end

  # **A diagnostic this server did not publish still reached the
  # dispatch**, which switches on `code` alone. Another extension's
  # diagnostic that happens to carry one of these three codes was
  # offered an edit computed from *this* engine's model of the file.
  it "ignores a diagnostic from another source that reuses one of these codes" do
    source = "def two(a, b)\n  [a, b]\nend\ntwo(1, 2, 3)\n"

    mine = actions(source)
    # Only the source differs: the code and the message are this
    # server's own, so nothing but the source check can refuse it.
    foreign = actions(source, diagnostic_overrides: { source: "rubocop" })

    # CONTROL: this server's own diagnostic is still acted on.
    expect(mine.map { |a| a[:title] }).to eq(["Remove 1 surplus argument"])
    expect(foreign).to be_empty
  end

  # **`takes 1..2 arguments` states a *range*, and the pattern captured
  # the first number in it** -- the minimum. So the fix computed for
  # `def mix(a, b = 1)` called with three arguments deleted back to one,
  # silently discarding the legal value for `b`.
  it "keeps an optional argument the callee accepts" do
    source = "def mix(a, b = 1)\n  [a, b]\nend\nmix(1, 2, 3)\n"

    offered = actions(source)

    expect(offered.map { |a| a[:title] }).to eq(["Remove 1 surplus argument"])
    expect(apply(source, offered.first)).to eq("def mix(a, b = 1)\n  [a, b]\nend\nmix(1, 2)\n")
  end

  # **A zero-maximum callee made `locations[keep - 1]` mean
  # `locations[-1]`** -- the *last* argument -- so `from` equalled `to`
  # and the offered fix was an empty deletion at a point. Clicking it
  # changed nothing and the diagnostic stayed.
  it "deletes the arguments to a method that takes none" do
    source = "def none\nend\nnone(1, 2)\n"

    offered = actions(source)

    expect(offered.map { |a| a[:title] }).to eq(["Remove 2 surplus arguments"])
    applied = apply(source, offered.first)
    expect(applied).to eq("def none\nend\nnone()\n")
    expect(Prism.parse(applied)).to be_success
  end

  # **The heredoc guard asked whether the deleted span *opens* one, never
  # whether it closes one.** With the marker among the arguments being
  # kept and the surplus argument below the terminator, the deleted span
  # holds no `<<` at all, so the fix went ahead, ate the body and the
  # terminator, and handed back a file that does not parse.
  it "refuses when the deletion would cross a heredoc's body, and still fixes a plain call" do
    crossing = "def takes_one(a)\n  a\nend\ntakes_one(<<~SQL,\n  select 1\nSQL\n  2)\n"
    plain = "def takes_one(a)\n  a\nend\ntakes_one(1, 2, 3)\n"

    # CONTROL, the ordinary shape: still fixed, and the result parses.
    control = actions(plain)
    expect(control.map { |a| a[:title] }).to eq(["Remove 2 surplus arguments"])
    expect(Prism.parse(apply(plain, control.first))).to be_success

    expect(actions(crossing)).to be_empty
  end

  # **The `def` was inserted at the class's start line plus one**, which
  # is only the body's first line when the class is written across
  # lines. A one-line class put the `def` after its own `end` -- and the
  # result *parses*, which is why the E2E assertion could not see it.
  it "defines the method on a one-line class, not after its `end`" do
    one_line = "class OneLiner < Object; def known; end; end\nOneLiner.new.missing\n"
    multi = "class MultiLine\n  def known; end\nend\nMultiLine.new.missing\n"

    offered = actions(one_line)
    expect(offered.map { |a| a[:title] }).to eq(["Define `missing` in OneLiner"])
    expect(defines?(apply(one_line, offered.first), :OneLiner, :missing)).to be(true)

    # CONTROL: the shape that already worked must keep working.
    control = actions(multi)
    expect(defines?(apply(multi, control.first), :MultiLine, :missing)).to be(true)
  end

  # A class whose header runs across lines had the `def` inserted
  # *inside the header*, between `class Wide <` and its superclass. That
  # parses too, and then raises `TypeError` on load.
  it "defines the method below a header written across lines" do
    source = "class Wide <\n    Object\n  def known; end\nend\nWide.new.missing\n"

    offered = actions(source)

    expect(offered.map { |a| a[:title] }).to eq(["Define `missing` in Wide"])
    expect(defines?(apply(source, offered.first), :Wide, :missing)).to be(true)
  end

  # **The inserted `def` took no parameters**, so applying the fix for a
  # call with arguments immediately produced the next diagnostic --
  # whose own fix was the empty deletion above. Two clicks, no change.
  it "gives the inserted `def` the parameters the call passes" do
    source = "class Arity\n  def go\n    Arity.new.absent(1, 2)\n  end\nend\n"

    offered = actions(source).select { |a| a[:title].start_with?("Define") }
    applied = apply(source, offered.first)

    expect(applied).to include("def absent(arg1, arg2)")
    # CONTROL: applying the fix must leave no diagnostic behind, which
    # is the property a zero-arity `def` failed.
    expect(drive(applied) { [] }.map { |d| d[:code] }).to be_empty
  end

  # **A quick fix must not offer to write into vendored gem source.**
  # The insertion target is the *owner's* declaring file, which for a
  # class defined in a gem is a read-only path inside the bundle -- so
  # one click offered to edit somebody else's installed gem.
  it "offers no definition when the class is declared inside an installed gem" do
    gem_uri = "file:///home/dev/.gem/ruby/3.4.0/gems/foo-1.0/lib/foo.rb"
    klass = "class Vendored\n  def known; end\nend\n"
    call = "Vendored.new.missing\n"

    output = StringIO.new
    input =
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: gem_uri, text: klass, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: "file:///a.rb", text: call, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run
    diagnostic = messages_from(output)
                 .select { |m| m[:method] == "textDocument/publishDiagnostics" && m.dig(:params, :uri) == "file:///a.rb" }
                 .flat_map { |m| Array(m.dig(:params, :diagnostics)) }.first

    ask = lambda do |owner_uri|
      out = StringIO.new
      Ovallsp::Server.new(
        input: StringIO.new(
          frame(jsonrpc: "2.0", method: "textDocument/didOpen",
                params: { textDocument: { uri: owner_uri, text: klass, version: 1, languageId: "ruby" } }) +
          frame(jsonrpc: "2.0", method: "textDocument/didOpen",
                params: { textDocument: { uri: "file:///a.rb", text: call, version: 1, languageId: "ruby" } }) +
          frame(jsonrpc: "2.0", id: 2, method: "textDocument/codeAction",
                params: { textDocument: { uri: "file:///a.rb" }, range: diagnostic[:range],
                          context: { diagnostics: [diagnostic] } }) +
          frame(jsonrpc: "2.0", method: "exit", params: nil)
        ), output: out, logger: logger
      ).run
      Array(messages_from(out).find { |m| m[:id] == 2 }&.[](:result)).map { |a| a[:title] }
    end

    # CONTROL: the identical shape with the class in the workspace.
    expect(ask.call("file:///lib/vendored.rb")).to eq(["Define `missing` in Vendored"])
    expect(ask.call(gem_uri)).to be_empty
  end

  # The comment above the insertion says "at the indentation its body
  # uses"; two spaces were hardcoded, so a class nested in a module got
  # its new `def` at the wrong depth.
  it "indents the inserted `def` to the class it is inserted into" do
    source = "module Ns\n  class Baz\n    def known; end\n  end\nend\nNs::Baz.new.whatever\n"

    offered = actions(source).select { |a| a[:title].start_with?("Define") }

    expect(apply(source, offered.first))
      .to eq("module Ns\n  class Baz\n    def known; end\n    def whatever\n    end\n  end\nend\nNs::Baz.new.whatever\n")
  end

  # **A class made by assignment has no `end` to insert before, and the
  # fix inserted there anyway.**
  #
  # `#insertion_for` aims at `range.end.character - 3`, which is exactly
  # where a one-line class's `end` sits. The last three characters of
  # `Widget = Class.new(Base)` are `se)`, so one click produced:
  #
  #     Widget = Class.new(Badef missing_thing
  #     end
  #     se)
  #
  # -- source the user did not write and Ruby cannot parse, and it lands
  # in the *declaring* file, which need not be the file the diagnostic
  # was reported on.
  #
  # `024.82` is why this is indexed as a class at all: `A = Class.new(B)`
  # creates a class as surely as `class A < B` does. The diagnostic is
  # right; only the fix was wrong. The rule that tells them apart is that
  # a keyword class's location starts at `class`, strictly before its
  # name, and an assignment's starts at the name itself.
  {
    "with a parent" => "class Base\nend\nWidget = Class.new(Base)\nWidget.new.missing_thing\n",
    "with none" => "Widget = Class.new\nWidget.new.missing_thing\n",
    "across lines" => "class Base\nend\nWidget = Class.new(\n  Base\n)\nWidget.new.missing_thing\n"
  }.each do |label, source|
    it "offers no definition fix for a class made by assignment #{label}" do
      offered = actions(source).select { |a| a[:title].to_s.start_with?("Define") }

      expect(offered).to be_empty,
                         "offered #{offered.map { |a| a[:title] }.inspect}, and applying it does not parse"
    end
  end

  # CONTROL. Without it, a fix that stopped being offered at all would
  # pass every example above. The keyword form must keep working, and the
  # result must still parse -- two of this file's earlier defects left a
  # file that parsed and did not run, so parsing alone is not the test.
  it "still offers it for the keyword form, and the result parses" do
    source = "class Widget\n  def real; end\nend\nWidget.new.missing_thing\n"

    offered = actions(source).select { |a| a[:title].to_s.start_with?("Define") }

    expect(offered.length).to eq(1)
    expect(apply(source, offered.first))
      .to eq("class Widget\n  def real; end\n  def missing_thing\n  end\nend\nWidget.new.missing_thing\n")
  end
end
