# frozen_string_literal: true

require_relative "../../../scripts/check_protocol_doc"

# **The chain that broke, and the row that was supposed to catch it.**
#
# 0.3.0 added a request to the Runtime Agent, bumped the protocol version
# from 1 to 2, and built a capability on both. `docs/design/docs/05-protocol.md`
# was not touched. `docs/DOCUMENTATION_MAP.md` names that document in its
# trigger table -- and that row is one of eight whose "Checked by" column
# reads as nothing at all, so the whole of its enforcement was a person
# remembering.
#
# Measured before this file existed: the document stated version 1 against
# the Agent's 2, had no section for three of the nine requests the Agent
# dispatches, and specified seven methods appearing nowhere in `core/lib`.
# Six of those seven read as an ordinary specification -- a request shape, a
# response shape -- which is exactly what the map's row says a section for
# something unimplemented must not do.
#
# The decision is tested against synthetic inputs rather than against the
# tree, so each question has an example that fails for that reason alone.
# Every fixture dispatches exactly what it documents apart from the one
# thing its example is about, and each asserts the problem count as well as
# its text -- otherwise an example passes on a second, unrelated problem,
# which is how the first draft of this file passed.
RSpec.describe "scripts/check_protocol_doc.rb" do
  root = File.expand_path("../../..", __dir__)

  # Names that exist here and nowhere real, so no example can pass by
  # accidentally naming something the tree happens to contain.
  def agent_source(version: 2, dispatches: %w[agent/hello agent/probeAlpha])
    body = dispatches.map { |m| "        when \"#{m}\"\n          respond(id, x)\n" }.join
    "module A\n  PROTOCOL_VERSION = #{version}\n  def dispatch(m)\n    case method\n#{body}    end\n  end\nend\n"
  end

  def doc(version: 2, sections: { "agent/hello" => "接続確立。\n", "agent/probeAlpha" => "何かを返す。\n" })
    head = "## 2. バージョニング\n\n```json\n{\"protocolVersion\": #{version}}\n```\n\n## 4. Requests\n\n"
    head + sections.map { |name, body| "### #{name}\n\n#{body}\n" }.join
  end

  def lib_naming(*methods) = [methods.map { |m| "        when \"#{m}\"\n" }.join]

  def only_hello = { agent: agent_source(dispatches: %w[agent/hello]), lib: lib_naming("agent/hello") }

  def problems(agent: agent_source, document: doc, lib: lib_naming("agent/hello", "agent/probeAlpha"))
    ProtocolDoc.problems(agent_source: agent, doc: document, lib_sources: lib)
  end

  # The control, and every example below is worth only what this is worth: a
  # document that agrees with its Agent produces nothing at all.
  it "says nothing when the version, the dispatch and the sections all agree" do
    expect(problems).to be_empty
  end

  it "reports a version the document states and the Agent does not" do
    found = problems(document: doc(version: 1))

    expect(found.length).to eq(1)
    expect(found.first).to match(/protocolVersion 1 .* says 2/)
  end

  it "reports a request the Agent dispatches and the document does not name" do
    found = problems(agent: agent_source(dispatches: %w[agent/hello agent/probeAlpha agent/probeBeta]),
                     lib: lib_naming("agent/hello", "agent/probeAlpha", "agent/probeBeta"))

    expect(found.length).to eq(1)
    expect(found.first).to match(%r{`agent/probeBeta` is dispatched .* has no section})
  end

  # The direction that is worse, because it reads as an instruction rather
  # than as a gap: a section specifying a method nothing implements.
  it "reports a section for a method nothing in core/lib names" do
    found = problems(**only_hello,
                     document: doc(sections: { "agent/hello" => "接続確立。\n",
                                               "agent/probeGhost" => "```json\n{\"a\": 1}\n```\n" }))

    expect(found.length).to eq(1)
    expect(found.first).to match(%r{specifies `agent/probeGhost`.*reads as a specification}m)
  end

  # And its control. Without this the check would demand that every design
  # note be implemented or deleted, which is not what the rule asks for.
  it "allows a section that says nothing implements it" do
    expect(problems(**only_hello,
                    document: doc(sections: { "agent/hello" => "接続確立。\n",
                                              "agent/probeGhost" => "**未実装。**\n" }))).to be_empty
  end

  # `agent/model` is a prefix of `agent/models`, and a substring test would
  # call the shorter one implemented because the longer one is.
  it "tells a method from another whose name it is a prefix of" do
    found = problems(agent: agent_source(dispatches: %w[agent/probeOne agent/probeOneMore]),
                     document: doc(sections: { "agent/probeOne" => "a\n", "agent/probeOneMore" => "b\n" }),
                     lib: lib_naming("agent/probeOneMore"))

    expect(found.length).to eq(1)
    expect(found.first).to match(%r{specifies `agent/probeOne`,})
  end

  # The tree itself. Split from the examples above because a failure here is
  # a document to fix, and a failure above is this checker to fix.
  it "finds the document and the Agent in agreement in this tree" do
    agent = File.read(File.join(root, ProtocolDoc::AGENT_PATH), encoding: "UTF-8")
    document = File.read(File.join(root, ProtocolDoc::DOC_PATH), encoding: "UTF-8")

    found = ProtocolDoc.problems(agent_source: agent, doc: document, lib_sources: ProtocolDoc.lib_sources(root))

    expect(found).to be_empty, "check-protocol-doc:\n  #{found.join("\n  ")}"
  end

  # A checker that cannot see the thing it checks reports exactly what a
  # working checker reports when nothing is wrong. This is the example that
  # tells those apart, and `scripts/check_pinned_mutations.rb` reporting all
  # four mutations uncaught on its first run is why the repository knows to
  # write one.
  it "is reading a real dispatch and a real document, not two empty files" do
    agent = File.read(File.join(root, ProtocolDoc::AGENT_PATH), encoding: "UTF-8")
    document = File.read(File.join(root, ProtocolDoc::DOC_PATH), encoding: "UTF-8")

    expect(ProtocolDoc.dispatched(agent).length).to be >= 5
    expect(ProtocolDoc.sections(document).length).to be >= 5
    expect(ProtocolDoc.protocol_version(agent)).to match(/\A\d+\z/)
    expect(ProtocolDoc.lib_sources(root).length).to be >= 20
  end

  it "is invoked by preflight" do
    expect(File.read(File.join(root, "scripts", "preflight.rb"), encoding: "UTF-8"))
      .to include("check_protocol_doc.rb")
  end
end
