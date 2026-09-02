# frozen_string_literal: true

require "stringio"

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
end
