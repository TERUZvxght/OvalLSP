# frozen_string_literal: true

require "tmpdir"

# `024.230`. A `def helper` written at the top level of a file was
# indexed as `owner: nil` — not `"Object"` — so neither an `Object` nor a
# `Kernel` receiver reached it, and a call to it got nothing from hover,
# completion, signature help or go to definition.
#
# Ruby puts it on `Object`, privately:
#
#   $ ruby -e '
#   def helper(a); end
#   p [Object.private_instance_methods(false).include?(:helper), self.class]
#   '
#   # => [true, Object]
#   # ruby 3.4.10
#
# **Private is half the answer and the half that is easy to drop.**
# Recorded public, `"str".helper` would be offered and accepted, which
# Ruby refuses — so the visibility is asserted here beside the owner.
#
# **`def self.x` at the top level is not this**, and is deliberately left
# alone. It lands on `main`'s singleton class rather than on `Object`'s:
#
#   $ ruby -e '
#   def self.top_singleton; end
#   p [Object.singleton_methods(false).include?(:top_singleton),
#      self.singleton_class.instance_methods(false).include?(:top_singleton)]
#   '
#   # => [false, true]
#   # ruby 3.4.10
#
# **The blast radius was measured before the change, and it is not what
# the entry feared.** Over 513 files of activesupport and bundler, 7,384
# declarations, the ones carrying `owner: nil` are 358 modules and 177
# classes — top-level namespaces, where `nil` is right — one constant,
# and exactly **one** instance method. The owner rule changes for that
# kind and nothing else.
RSpec.describe "the owner a top-level `def` is indexed under" do
  def declarations(source)
    document = Ovallsp::TextDocument.new(uri: "file:///top.rb", text: source, version: 1, language_id: "ruby")
    Ovallsp::ParserService.new.summarize(document).declarations
  end

  def declaration_for(source, name)
    declarations(source).find { |d| d.symbol_id.name == name }
  end

  it "records it on Object, where Ruby puts it" do
    found = declaration_for("def helper(a)\n  a\nend\n", "helper")

    expect(found.symbol_id.kind).to eq(:instance_method)
    # `::Object`, qualified the way the index qualifies every owner.
    expect(found.symbol_id.owner).to eq("::Object")
  end

  it "records it private, where Ruby puts it" do
    found = declaration_for("def helper(a)\n  a\nend\n", "helper")

    expect(found.visibility).to eq(:private)
  end

  # The control that keeps this from becoming "everything is on Object".
  it "leaves a method inside a class on that class" do
    found = declaration_for("class Widget\n  def build\n  end\nend\n", "build")

    expect(found.symbol_id.owner).to eq("::Widget")
  end

  # And the second: a top-level `def self.x` is `main`'s singleton, not
  # Object's, so it keeps whatever it had rather than being swept in.
  it "leaves a top-level `def self.x` alone" do
    found = declaration_for("def self.top_singleton\nend\n", "top_singleton")

    expect(found.symbol_id.owner).to be_nil
  end

  # The point of the whole change: the index can now be asked.
  it "is reachable through an Object receiver" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    document = Ovallsp::TextDocument.new(uri: "file:///top.rb", text: "def helper(a)\n  a\nend\n",
                                         version: 1, language_id: "ruby")
    workspace_index.replace_file(Ovallsp::ParserService.new.summarize(document))

    symbol = Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "Object", name: "helper",
                                          discriminator: nil)

    expect(workspace_index.declarations_with_uri(symbol).length).to eq(1)
  end

  # **The end the user meets**, and the reason the index change alone was
  # not enough: it took three places agreeing — the declaration's owner,
  # the call candidate's owner, and what a bare call's receiver is.
  # Fixing only the first left all four features answering nothing, which
  # is what they did before.
  describe "a call to a top-level helper, through the real server" do
    let(:output) { StringIO.new }
    let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

    def frame(hash)
      json = JSON.generate(hash)
      "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
    end

    def answers(references: false)
      reference_request =
        if references
          frame(jsonrpc: "2.0", id: 4, method: "textDocument/references",
                params: { textDocument: { uri: "file:///w/caller.rb" }, position: { line: 0, character: 0 },
                          context: { includeDeclaration: true } })
        else
          ""
        end
      input =
        frame(jsonrpc: "2.0", id: 0, method: "initialize",
              params: { processId: nil, rootUri: "file:///w", capabilities: {} }) +
        frame(jsonrpc: "2.0", method: "initialized", params: {}) +
        frame(jsonrpc: "2.0", method: "textDocument/didOpen",
              params: { textDocument: { uri: "file:///w/helper.rb", text: "def helper(a)\n  a\nend\n",
                                        version: 1, languageId: "ruby" } }) +
        frame(jsonrpc: "2.0", method: "textDocument/didOpen",
              params: { textDocument: { uri: "file:///w/caller.rb", text: "helper(1)\n", version: 1,
                                        languageId: "ruby" } }) +
        reference_request +
        frame(jsonrpc: "2.0", id: 1, method: "textDocument/definition",
              params: { textDocument: { uri: "file:///w/caller.rb" }, position: { line: 0, character: 0 } }) +
        frame(jsonrpc: "2.0", id: 2, method: "textDocument/hover",
              params: { textDocument: { uri: "file:///w/caller.rb" }, position: { line: 0, character: 0 } }) +
        frame(jsonrpc: "2.0", id: 3, method: "textDocument/signatureHelp",
              params: { textDocument: { uri: "file:///w/caller.rb" }, position: { line: 0, character: 7 } }) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)
      Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run
      output.rewind
      reader = Ovallsp::IO::FramedReader.new(output)
      seen = []
      begin
        loop { seen << reader.read_message }
      rescue Ovallsp::IO::FramedReader::EOF
        nil
      end
      seen.each_with_object({}) { |m, acc| acc[m[:id]] = m[:result] if m[:id] }
    end

    it "goes to the definition, hovers it, and shows its signature" do
      result = answers

      expect(result[1].first[:uri]).to eq("file:///w/helper.rb")
      expect(result[2][:contents][:value]).to include("helper(a)")
      expect(result[3][:signatures].first[:label]).to eq("helper(a)")
    end

    # **Find References is the one that needs the call's own owner**, and
    # measured, it is the only one: definition, hover and signature help
    # all reach the answer through the scope's implicit self type, so
    # they work with the call candidate carrying no owner at all. This
    # example is what distinguishes that half of the change from the
    # other two.
    it "finds the call from the definition" do
      result = answers(references: true)

      expect(result[4].map { |location| location[:uri] }).to include("file:///w/caller.rb")
    end
  end
end
