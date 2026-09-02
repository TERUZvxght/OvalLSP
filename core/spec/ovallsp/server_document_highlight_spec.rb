# frozen_string_literal: true

require "stringio"

# 0.3.0's `textDocument/documentHighlight` -- the occurrences of the
# symbol under the cursor, in this file only.
RSpec.describe "Ovallsp::Server textDocument/documentHighlight" do
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

  # `[line, start character, kind]` per highlight.
  def highlights(source, at:, route_registry: Ovallsp::Routes::RouteRegistry.new)
    output = StringIO.new
    input =
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: "file:///d.rb", text: source, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", id: 1, method: "textDocument/documentHighlight",
            params: { textDocument: { uri: "file:///d.rb" }, position: at }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger,
                        route_registry: route_registry).run

    Array(messages_from(output).find { |m| m[:id] == 1 }&.[](:result))
      .map { |h| [h[:range][:start][:line], h[:range][:start][:character], h[:kind]] }
      .sort
  end

  # `let` rather than a constant: a constant assigned inside a
  # `describe` block lands on `Object`, where another spec file using
  # the same word silently redefines it for both.
  let(:namespaced) do
    <<~RUBY
    module Api
      class Widget
      end

      class Factory
        def make
          Widget.new
        end
      end
    end

    class Plain
    end

    Plain.new
  RUBY
  end

  # **The needle was the symbol's *qualified* name and the recorded
  # spelling is what the source writes.** With the cursor on the bare
  # `Widget` inside `Api`, the symbol is `::Api::Widget`, the filter
  # looked for candidates spelled `Api::Widget`, matched none, and the
  # only highlight left was the unfiltered declaration -- so the word
  # under the caret was itself absent from the answer.
  it "highlights a namespaced constant written by its bare name" do
    at_bare = highlights(namespaced, at: { line: 6, character: 6 })
    # CONTROL: a top-level constant, whose spelling and qualified name
    # are the same word, was answered correctly all along.
    at_plain = highlights(namespaced, at: { line: 14, character: 2 })

    expect(at_plain).to eq([[11, 6, 3], [14, 0, 1]])
    expect(at_bare).to eq([[1, 8, 3], [6, 6, 1]])
  end

  let(:reopened) { "class Foo\n  def bar\n    1\n  end\nend\n\nclass Foo\n  def bar\n    2\n  end\nend\n" }

  # **Only the *first* declaration was highlighted**, because the `def`
  # line comes from a `find` and a method name is not recorded as a
  # reference candidate. With a class reopened, the two carets are
  # indistinguishable and the one the user is standing on is the one
  # left out.
  it "highlights every declaration of a reopened method, from either caret" do
    from_first = highlights(reopened, at: { line: 1, character: 6 })
    from_second = highlights(reopened, at: { line: 7, character: 6 })

    expect(from_first).to eq([[1, 6, 3], [7, 6, 3]])
    expect(from_second).to eq([[1, 6, 3], [7, 6, 3]])
  end

  # A route helper's symbol is `SymbolId(kind: :route_helper, name:
  # "user")` -- the route *stem* -- so narrowing the file's candidates by
  # that bare name matched none of the `user_path` sites, and there is no
  # declaration to fall back on. Find References answers at the same
  # caret, so the surface was the only thing that did not.
  it "highlights a route helper's call sites" do
    registry = Ovallsp::Routes::RouteRegistry.from_route_facts(
      [{ name: "user", verb: "GET", pathTemplate: "/users/:id", requiredParts: ["id"], optionalParts: [],
         defaults: { controller: "users", action: "show" }, sourceLocation: nil, routeSet: "main_app" }]
    )
    source = "class C\n  def go\n    user_path(1)\n    user_url(2)\n    helper\n  end\n\n  def helper\n  end\nend\n"

    on_helper_route = highlights(source, at: { line: 2, character: 6 }, route_registry: registry)
    # CONTROL: an ordinary method at the same kind of caret, which
    # already worked -- so answering nothing everywhere would not pass.
    on_method = highlights(source, at: { line: 4, character: 6 }, route_registry: registry)

    expect(on_method).to eq([[4, 4, 2], [7, 6, 3]])
    expect(on_helper_route).to eq([[2, 4, 2], [3, 4, 2]])
  end
end
