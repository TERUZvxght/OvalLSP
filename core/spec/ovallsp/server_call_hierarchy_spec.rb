# frozen_string_literal: true

require "stringio"

# 0.3.0's `textDocument/prepareCallHierarchy` and its two follow-ups.
RSpec.describe "Ovallsp::Server call hierarchy" do
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
    all.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  # Opens every file, prepares at `at`, then asks for `direction`.
  # Returns `[prepared_item, [[callee_or_caller_name, uri, range], ...]]`.
  def hierarchy(files, uri:, at:, direction: :outgoing, route_registry: Ovallsp::Routes::RouteRegistry.new)
    output = StringIO.new
    opens = files.map do |(file_uri, text)|
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: file_uri, text: text, version: 1, languageId: "ruby" } })
    end
    server = Ovallsp::Server.new(
      input: StringIO.new(opens.join +
        frame(jsonrpc: "2.0", id: 1, method: "textDocument/prepareCallHierarchy",
              params: { textDocument: { uri: uri }, position: at }) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)),
      output: output, logger: logger, route_registry: route_registry
    )
    server.run
    item = Array(messages_from(output).find { |m| m[:id] == 1 }&.[](:result)).first
    return [nil, []] unless item

    follow_up = StringIO.new
    method = direction == :outgoing ? "callHierarchy/outgoingCalls" : "callHierarchy/incomingCalls"
    Ovallsp::Server.new(
      input: StringIO.new(opens.join +
        frame(jsonrpc: "2.0", id: 2, method: method, params: { item: item }) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)),
      output: follow_up, logger: logger, route_registry: route_registry
    ).run
    calls = Array(messages_from(follow_up).find { |m| m[:id] == 2 }&.[](:result)).map do |call|
      side = call[:to] || call[:from]
      [side[:name], side[:uri], side[:range][:start][:line], call[:fromRanges].map { |r| r[:start][:line] }]
    end
    [item, calls]
  end

  # A method, and a method it calls, so `outgoingCalls` has an answer.
  # `let` rather than a constant: a constant assigned inside a
  # `describe` block lands on `Object`, and a second spec file using
  # the same word silently redefines it for both.
  let(:widget) { "class Widget\n  def build\n    other\n  end\n\n  def other\n  end\nend\n" }

  # **A prepare at a *call site* built the item out of the calling
  # file**, because the declaration was looked for in the request's own
  # summary only. The item then asserted that `Widget#build` lives in
  # `caller.rb` at the call, and `outgoingCalls` -- which reads the
  # method's body out of `item[:uri]` -- found no declaration there and
  # answered "no outgoing calls" for a method that has one.
  it "points a prepare at a call site to the file the method is declared in" do
    files = [["file:///widget.rb", widget], ["file:///caller.rb", "Widget.new.build\n"]]

    at_call, from_call = hierarchy(files, uri: "file:///caller.rb", at: { line: 0, character: 11 })
    # CONTROL: preparing on the `def` itself, which already worked.
    at_def, from_def = hierarchy(files, uri: "file:///widget.rb", at: { line: 1, character: 6 })

    expect(at_def[:uri]).to eq("file:///widget.rb")
    expect(from_def.map(&:first)).to eq(["other"])

    expect(at_call[:uri]).to eq("file:///widget.rb")
    expect(from_call.map(&:first)).to eq(["other"])
  end

  let(:nested) do
    "class C\n  def outer\n    def inner\n      helper\n    end\n  end\n\n" \
      "  def plain\n    helper\n  end\n\n  def helper\n  end\nend\n"
  end

  # **The two directions disagreed about one call.** Outgoing used plain
  # containment, so a call written inside a nested `def` was credited to
  # the enclosing method; incoming used `#enclosing_callable`'s
  # innermost rule and credited the same call to the nested one.
  it "credits a call inside a nested `def` to the nested method, in both directions" do
    files = [["file:///n.rb", nested]]

    _, outer = hierarchy(files, uri: "file:///n.rb", at: { line: 1, character: 6 })
    # CONTROL: the sibling that really does call `helper`.
    _, plain = hierarchy(files, uri: "file:///n.rb", at: { line: 7, character: 6 })
    _, callers = hierarchy(files, uri: "file:///n.rb", at: { line: 11, character: 6 }, direction: :incoming)

    expect(plain.map { |c| [c.first, c.last] }).to eq([["helper", [8]]])
    expect(outer).to be_empty
    expect(callers.map { |c| [c.first, c.last] }).to contain_exactly(["inner", [3]], ["plain", [8]])
  end

  # `#enclosing_callable` broke its containment tie on line count alone,
  # so two `def`s written on one line tied and the *first* declaration
  # won -- crediting the call to the method that did not make it.
  it "credits a call to the innermost `def` when both are on one line" do
    one_line = [["file:///o.rb", "class C\n  def outer; def inner; helper; end; end\n  def helper; end\nend\n"]]

    _, callers = hierarchy(one_line, uri: "file:///o.rb", at: { line: 2, character: 6 }, direction: :incoming)

    expect(callers.map(&:first)).to eq(["inner"])
  end

  # **A callee with no workspace declaration was given the *caller's*
  # file at line 0.** A route helper resolves to a `:route_helper`
  # symbol, which is not a method and has no declaration, so the item
  # named the route stem, pointed at the top of the calling file, and
  # offered a jump to somewhere that is not the method. Section 0 ranks
  # no jump above a wrong one.
  it "omits a callee it cannot name a declaration for, and keeps the one it can" do
    files = [["file:///r.rb", "class C\n  def create\n    user_path(1)\n    helper\n  end\n\n  def helper\n  end\nend\n"]]
    registry = Ovallsp::Routes::RouteRegistry.from_route_facts(
      [{ name: "user", verb: "GET", pathTemplate: "/users/:id", requiredParts: ["id"], optionalParts: [],
         defaults: { controller: "users", action: "show" }, sourceLocation: nil, routeSet: "main_app" }]
    )

    _, calls = hierarchy(files, uri: "file:///r.rb", at: { line: 1, character: 6 }, route_registry: registry)

    # CONTROL: the real method in the same answer keeps its declaration.
    expect(calls).to eq([["helper", "file:///r.rb", 6, [3]]])
  end
end
