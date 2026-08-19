# frozen_string_literal: true

# `docs/CLIENT_BEHAVIOUR.md` collects every behaviour this project relies
# on from outside the tree -- VS Code, `vscode-languageclient`, the LSP
# specification. The rows marked **checked** are the ones a machine can
# verify, and this is that machine.
#
# It exists because 0.2.7 shipped, in three files, a claim about the
# client that was false: that a new version number on `publishDiagnostics`
# makes a stale publish acceptable "because the client's staleness filter
# accepts it". The client has no such filter. The claim came from a scope
# document two releases earlier and was quoted forward without being
# checked, while `server_publish_invariant_spec.rb` said the opposite in
# the same tree the whole time.
#
# Nothing could notice, because a claim about VS Code reads exactly like a
# claim about our own code. These examples are the difference.
RSpec.describe "what we rely on the client to do" do
  CLIENT_LIB = File.expand_path(
    "../../../vscode/node_modules/vscode-languageclient/lib/common/client.js", __dir__
  )

  # Skipped rather than failed when the extension's dependencies are not
  # installed: a Ruby-only checkout is a legitimate way to work on Core,
  # and CI installs them. The example count in `documented_counts_spec`
  # is what would notice a permanent skip.
  before { skip("vscode/node_modules is not installed") unless File.exist?(CLIENT_LIB) }

  let(:handle_diagnostics) do
    source = File.read(CLIENT_LIB, encoding: "UTF-8")
    start = source.index("handleDiagnostics(params) {")
    source[start, source.index("triggerDiagnosticQueue() {", start) - start]
  end

  # The claim: the client ignores `params.version` and queues by uri, so
  # the last publish to arrive is what the panel shows. That is why
  # ordering is `Server#publish_findings`'s job and not the client's --
  # and why the version travels as information rather than as something
  # the client acts on.
  it "ignores the version on publishDiagnostics" do
    expect(handle_diagnostics).not_to include("version")
  end

  it "queues the diagnostics by uri, last write winning" do
    expect(handle_diagnostics).to include("this._diagnosticQueue.set(params.uri, params.diagnostics)")
  end

  # And the tree says so in one place. A second statement of an external
  # fact is how the wrong one survived: it can be corrected while the
  # other stays, and both read as authoritative.
  # And the tree states it in one place. A second statement of an external
  # fact is how the wrong one survived: it can be corrected in one file
  # while the other stays, and both read as authoritative.
  #
  # Scoped to live code and user-facing documents. `docs/design/tasks/**`
  # is a dated record by construction -- an entry saying "this was
  # believed and was wrong" is the account, not a competing claim -- and
  # this file quotes the phrase in order to look for it.
  it "is stated in one document, which the rest of the tree points at" do
    root = File.expand_path("../../..", __dir__)
    searched = Dir.glob(File.join(root, "{core/lib,core/spec,vscode/src}/**/*.{rb,ts}")) +
               Dir.glob(File.join(root, "docs/*.md"))
    restated = searched
               .reject { |path| path.include?("CLIENT_BEHAVIOUR") || path.end_with?(File.basename(__FILE__)) }
               .select { |path| File.read(path, encoding: "UTF-8").match?(/staleness filter/i) }
               .map { |path| path.delete_prefix("#{root}/") }

    expect(restated).to be_empty,
                        "these state a fact about the client instead of pointing at " \
                        "docs/CLIENT_BEHAVIOUR.md: #{restated.join(', ')}"
  end
end
