# frozen_string_literal: true

require "stringio"

RSpec.describe "Ovallsp::Server textDocument/prepareRename and textDocument/rename (Task 016)" do
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

  it "renames a method's declaration and every resolved call site across files" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\nend\n") +
      did_open("file:///user.rb", "Widget.new.build\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 1, character: 6 }, newName: "construct" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    changes = sent_messages.first[:result][:changes]
    expect(changes.keys).to contain_exactly(:"file:///widget.rb", :"file:///user.rb")
    expect(changes[:"file:///widget.rb"].first).to eq(
      range: { start: { line: 1, character: 6 }, end: { line: 1, character: 11 } }, newText: "construct"
    )
    expect(changes[:"file:///user.rb"].first[:newText]).to eq("construct")
  end

  it "returns a placeholder and range from prepareRename" do
    input =
      did_open("file:///widget.rb", "class Widget\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/prepareRename",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 0, character: 7 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result[:placeholder]).to eq("Widget")
    expect(result[:range]).to eq(start: { line: 0, character: 6 }, end: { line: 0, character: 12 })
  end

  it "refuses (null result) prepareRename on a generated route helper call" do
    route_registry = Ovallsp::Routes::RouteRegistry.from_route_facts([
                                                                      { name: "user", verb: "GET", pathTemplate: "/users/:id",
                                                                        requiredParts: ["id"], optionalParts: [],
                                                                        defaults: { controller: "users", action: "show" },
                                                                        sourceLocation: nil, routeSet: "main_app" }
                                                                    ])
    input =
      did_open("file:///c.rb", "class UsersController\n  def show\n    user_path(1)\n  end\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/prepareRename",
        params: { textDocument: { uri: "file:///c.rb" }, position: { line: 2, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    server = Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger, route_registry: route_registry)
    server.run

    expect(sent_messages.first[:result]).to be_nil
  end

  it "refuses (null WorkspaceEdit) a rename that would collide with an existing declaration" do
    input =
      did_open("file:///a.rb", "class Widget\nend\n\nclass Gadget\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 7 }, newName: "Gadget" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to be_nil
  end

  it "does not confuse a local variable with a same-named local in a different scope" do
    source = "def a\n  x = 1\n  x\nend\n\ndef b\n  x = 2\n  x\nend\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 2, character: 2 }, newName: "y" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    edits = sent_messages.first[:result][:changes][:"file:///a.rb"]
    lines = edits.map { |e| e[:range][:start][:line] }
    expect(lines).to contain_exactly(1, 2)
  end

  # **Renaming from a parameter's use rewrote the body and left the
  # signature**, which is the failure 0.2.17 shipped a fix for arriving
  # through a binding form nothing recorded:
  #
  #   def g(arg)     ->   def g(arg)
  #     arg + 1             renamed + 1
  #   end                 end
  #
  # That parses and raises `NameError` when it runs. The parser seeded
  # each frame from Prism's `#locals`, so the *use* resolved and the
  # binding site was never an occurrence -- so Rename could not know it
  # had missed one, and refusing was not available to it either.
  it "rewrites a parameter's own binding site, not only its uses" do
    input =
      did_open("file:///param.rb", "def g(arg)\n  arg + 1\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///param.rb" }, position: { line: 1, character: 2 },
                  newName: "renamed" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    edits = sent_messages.first[:result][:changes][:"file:///param.rb"]
    starts = edits.map { |e| [e[:range][:start][:line], e[:range][:start][:character]] }.sort

    expect(starts).to eq([[0, 6], [1, 2]]),
                      "rewriting the use alone hands back a file that raises NameError"
  end

  # **A keyword parameter's name is the method's interface, and Ruby has
  # no spelling that separates the two.** `def m(by:)` binds a local
  # named `by` *because* the keyword is `by`; there is no `def m(by: as
  # factor)`. So renaming the local necessarily renames the keyword
  # every caller passes, which is not the edit the user asked for and
  # not one any caller would be given.
  #
  # The parser therefore records no binding site for it -- and that on
  # its own left the worse answer, not the safe one: the body was
  # rewritten and the signature left, exactly the file-that-does-not-run
  # shape. Refusing is the answer, and the planner asks a question it
  # can always answer: **do I know where this local is bound?** A local
  # with no write among its occurrences has a binding site this engine
  # cannot see, whatever the reason, and rewriting the rest of it is
  # never right.
  it "refuses to rename a keyword parameter rather than rewriting half of it" do
    input =
      did_open("file:///kw.rb", "def m(by:)\n  by * 2\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///kw.rb" }, position: { line: 1, character: 2 },
                  newName: "factor" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    changes = sent_messages.first[:result]&.dig(:changes)
    expect(changes.to_h.values.flatten).to be_empty,
                                           "rewriting the body alone leaves a method that raises NameError"
  end

  # **prepareRename warms the reference index, and did not.**
  # `#references_result` and `#rename_result` both call
  # `#ensure_reference_index_current`; this did not, so with the index
  # cold -- its state until the user has run Find All References or an
  # actual rename, and again after every edit that bumps the generation
  # -- `Rename::Planner#locations_for` saw declarations only. A local
  # has none, so the editor refused the rename box at a position where
  # `textDocument/rename` would have worked. `024.245`.
  #
  # Not the same trade as `documentHighlight`, which deliberately leaves
  # it cold: highlights are asked on every cursor move, and this is
  # asked once, when the user presses F2.
  it "warms the reference index, so a local can be renamed without a rehearsal" do
    input =
      did_open("file:///cold.rb", "def m\n  value = 1\n  value\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/prepareRename",
        params: { textDocument: { uri: "file:///cold.rb" }, position: { line: 1, character: 2 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to include(placeholder: "value")
  end

  # The same cold F2, on a class written inside a `module` body, driven
  # end to end (`024.244`). The compact spelling below it is the control:
  # it was already offered and stays offered.
  it "offers prepareRename on a class written inside a module body with nothing asked first" do
    source = "module Api\n  class Widget\n  end\nend\n\nclass Api2::Widget2\nend\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/prepareRename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 1, character: 8 } }
      ) +
      frame(
        jsonrpc: "2.0", id: 2, method: "textDocument/prepareRename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 5, character: 12 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    results = sent_messages.sort_by { |m| m[:id] }.map { |m| m[:result] }
    expect(results[0]).to eq(
      range: { start: { line: 1, character: 8 }, end: { line: 1, character: 14 } }, placeholder: "Widget"
    )
    expect(results[1][:placeholder]).to eq("Widget2")
  end

  # **Two same-named classes in different namespaces**, which is the
  # fixture that tells the two candidate behaviours apart: handing a
  # class reference the declared identity is only right if the identity
  # is the *right* declaration's. A bare `Widget` written on its own
  # `class` line was resolved with no nesting at all, so the caret on the
  # one in `Web` answered about the one in `Api` -- and renaming it
  # rewrote both `class` lines, giving two different classes one name.
  # Ruby resolves that name through the lexical nesting, and
  # `ReferenceCandidate` has been carrying it all along (`024.244`).
  #
  # `Api`'s own untouched line is the control: an answer that edited
  # everything called `Widget` would satisfy a count and fails this.
  it "renames only the same-named class the caret is actually inside" do
    source = "module Api\n  class Widget\n  end\nend\n\nmodule Web\n  class Widget\n  end\nend\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 6, character: 8 }, newName: "Gadget" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    edits = sent_messages.first[:result][:changes][:"file:///a.rb"]
    expect(edits.map { |e| e[:range][:start][:line] }).to contain_exactly(6)
    expect(edits).to all(include(newText: "Gadget"))
  end

  # **One token is both the hash key and the value**, which is what
  # Ruby's shorthand is, so there is no edit to that token that renames
  # the local and leaves the key alone. The value is the local; the key
  # is a symbol, and for a keyword argument it is the callee's parameter
  # name:
  #
  #   $ ruby -e '
  #   def take(name:) = name
  #   name = "n"
  #   p({ name: })
  #   p take(name:)
  #   '
  #   # => {name: "n"}
  #   # => "n"
  #   # ruby 3.4.10
  #
  # The parser recorded the local read over the whole `key:` token,
  # colon included, so substituting the new name deleted the colon: the
  # hash literal below became a syntax error and the call became
  # positional and raised `ArgumentError`. Shrinking the recorded range
  # to the identifier is not the fix -- that rewrites the *key*, which
  # turns the syntax error into a hash whose key silently changed and
  # leaves the keyword call raising. The edit that preserves meaning is
  # the expansion, and it is what this asserts.
  #
  # The whole file is compared rather than a list of lines, because the
  # thing being got wrong is the text. `take`'s own `name:` parameter on
  # line 0 is the control: it is a different scope, three of the four
  # candidate behaviours would touch it, and it has to come back
  # untouched.
  it "expands Ruby's hash shorthand rather than overwriting its colon" do
    source = "def take(name:) = name\ndef go\n  name = \"n\"\n  [{ name: }, take(name:)]\nend\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 2, character: 2 }, newName: "label" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    edits = sent_messages.first[:result][:changes][:"file:///a.rb"]
    lines = source.lines
    edits.sort_by { |e| [-e[:range][:start][:line], -e[:range][:start][:character]] }.each do |edit|
      line = edit[:range][:start][:line]
      lines[line] = lines[line].dup
      lines[line][edit[:range][:start][:character]...edit[:range][:end][:character]] = edit[:newText]
    end

    expect(lines.join).to eq(
      "def take(name:) = name\ndef go\n  label = \"n\"\n  [{ name: label }, take(name: label)]\nend\n"
    )
    expect(Prism.parse(lines.join)).to be_success
  end

  # `024.271`. `def <local>.name` evaluates its receiver in the enclosing
  # scope -- the local is not visible inside the singleton body at all:
  #
  #   $ ruby -e '
  #   class Runner
  #     def go
  #       ty = Object.new
  #       def ty.reads_outer
  #         defined?(ty)
  #       end
  #       [ty.reads_outer, binding.local_variable_defined?(:ty)]
  #     end
  #   end
  #   p Runner.new.go
  #   '
  #   # => [nil, true]
  #   # ruby 3.4.10
  #
  # The receiver is one of the `def` node's children and was walked with
  # the rest of them, after `@cref` had already become the method's. A
  # receiver this parser cannot name has no owner at all, so that `ty`
  # was recorded as `nil#3` while the `ty =` that created it was
  # `::Runner#3` -- one variable, two identities. Rename rewrote every
  # mention *except* the one on the `def` line, and the file stopped
  # running: `024.28`'s failure, produced by rename rather than refused
  # by it.
  #
  # The whole file is compared, because the thing being got wrong is the
  # text, and it is parsed, because "still runs" is the actual guarantee.
  it "rewrites a local used as a `def` receiver, so the file still parses" do
    source = "class Runner\n  def go\n    ty = Thing.new\n    def ty.outer\n      :x\n    end\n    ty\n  end\nend\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 2, character: 4 }, newName: "thing" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    edits = sent_messages.first[:result][:changes][:"file:///a.rb"]
    lines = source.lines
    edits.sort_by { |e| [-e[:range][:start][:line], -e[:range][:start][:character]] }.each do |edit|
      line = edit[:range][:start][:line]
      lines[line] = lines[line].dup
      lines[line][edit[:range][:start][:character]...edit[:range][:end][:character]] = edit[:newText]
    end

    expect(lines.join).to eq(
      "class Runner\n  def go\n    thing = Thing.new\n    def thing.outer\n      :x\n    end\n    thing\n  end\nend\n"
    )
    expect(Prism.parse(lines.join)).to be_success
  end

  # `024.278`. **A local variable never spans files**, and its identity
  # had no file in it. `Semantic::ReferenceResolver#resolve_local` builds
  # a synthetic owner of `"#{owner}##{scope_id}"`; scope ids are counted
  # per file, so two files whose locals land on the same counter and the
  # same cref owner share one identity.
  #
  # A top-level `def` has no owner at all, so any two files written that
  # way collide on their first method's locals. Renaming `ks` in one
  # rewrote `ks` in the other -- a WorkspaceEdit against a file the user
  # never opened, which is a worse failure than the nine shapes 0.2.17
  # fixed: those left one file wrong, this one edits a second file.
  #
  # Two classes are enough to make it not require top-level code, and
  # that is asserted separately below.
  it "renames a local in one file without touching a same-named local in another" do
    source_a = "def m\n  ks = 1\n  ks\nend\n"
    source_b = "def n\n  ks = 2\n  ks\nend\n"
    input =
      did_open("file:///a.rb", source_a) +
      did_open("file:///b.rb", source_b) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 1, character: 2 }, newName: "zz" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    changes = sent_messages.first[:result][:changes]
    expect(changes.keys).to eq([:"file:///a.rb"])
    expect(changes[:"file:///a.rb"].length).to eq(2)
  end

  # The same collision without top-level code: one class reopened in two
  # files, which is ordinary Rails. Both locals are `::Widget#<n>` with
  # the same counter.
  it "renames a local in one file of a reopened class without touching the other" do
    source_a = "class Widget\n  def m\n    ks = 1\n    ks\n  end\nend\n"
    source_b = "class Widget\n  def n\n    ks = 2\n    ks\n  end\nend\n"
    input =
      did_open("file:///wa.rb", source_a) +
      did_open("file:///wb.rb", source_b) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///wa.rb" }, position: { line: 2, character: 4 }, newName: "zz" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    changes = sent_messages.first[:result][:changes]
    expect(changes.keys).to eq([:"file:///wa.rb"])
  end

  # The control, and the reason the fix is "put the file in the identity"
  # rather than "only ever edit the caret's file": a *method* rename must
  # still cross files, and does.
  it "still renames a method's call sites in other files" do
    input =
      did_open("file:///w.rb", "class Widget\n  def build\n  end\nend\n") +
      did_open("file:///u.rb", "class User\n  def go\n    Widget.new.build\n  end\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///w.rb" }, position: { line: 1, character: 6 }, newName: "assemble" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    changes = sent_messages.first[:result][:changes]
    expect(changes.keys).to contain_exactly(:"file:///w.rb", :"file:///u.rb")
  end

  # `024.280`. A named capture in a regexp used with `=~` binds a local:
  #
  #   $ ruby -e '
  #   /(?<where>\d+)/ =~ "a12"
  #   p [where, defined?(where)]
  #   '
  #   # => ["12", "local-variable"]
  #   # ruby 3.4.10
  #
  # Prism gives that binding's `LocalVariableTargetNode` the range of the
  # **whole regexp literal**, so `024.260` declined to record it — right,
  # because rewriting that range destroys the regexp. What nobody
  # recorded is the consequence at the other end: the *uses* were
  # recorded and the *binding* was not, so renaming from a use rewrote
  # the uses and left the capture.
  #
  # **And it failed silently**, which is why it is fixed rather than
  # refused. `where = where.sub(...) if where` assigns before it reads,
  # so the renamed name is a defined-but-nil local: the guard goes false,
  # the `sub` never runs, and the next line passes `nil`. Nothing raises.
  #
  # The name is written literally inside the pattern, so its own range is
  # computable, and rewriting *that* is what Ruby needs. What the rename
  # still cannot see is a `Regexp.last_match[:where]` elsewhere — a
  # string, the same blind spot `send` has, and the same one every other
  # rename in this file lives with.
  it "rewrites a regexp named capture with the local it binds" do
    source = "/(?<where>\\d+)/ =~ line\nwhere = where.to_i if where\nputs where\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 1, character: 0 },
                  newName: "digits" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    edits = sent_messages.first[:result][:changes][:"file:///a.rb"]
    lines = source.lines
    edits.sort_by { |e| [-e[:range][:start][:line], -e[:range][:start][:character]] }.each do |edit|
      line = edit[:range][:start][:line]
      lines[line] = lines[line].dup
      lines[line][edit[:range][:start][:character]...edit[:range][:end][:character]] = edit[:newText]
    end

    expect(lines.join).to eq("/(?<digits>\\d+)/ =~ line\ndigits = digits.to_i if digits\nputs digits\n")
    expect(Prism.parse(lines.join)).to be_success
  end
end
