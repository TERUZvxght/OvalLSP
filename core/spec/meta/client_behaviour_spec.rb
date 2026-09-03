# frozen_string_literal: true

# Enumerated with `RepoFiles`, not `git ls-files` — `024.147`. A file you
# have just written is untracked until `git add`, and `preflight` runs
# before the commit, so a check that lists only tracked files is blind to
# exactly the file being worked on.
require_relative "../../../scripts/repo_files"

require "open3"

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
  # installed: a Ruby-only checkout is a legitimate way to work on Core.
  #
  # **This used to say "the example count in `documented_counts_spec` is
  # what would notice a permanent skip", and that was false** --
  # `RSpec.world.example_count` counts skipped examples, so a run where
  # these never executed is indistinguishable from one where they did. A
  # review round measured it: a fresh worktree with no `vscode/node_modules`
  # gives the same count and a green suite. Nothing noticed for a release
  # that these two checks -- the ones `docs/CLIENT_BEHAVIOUR.md` marks
  # **checked** -- ran nowhere.
  #
  # ci.yml's "skipped instead of run" step now names this file, the same
  # way it already names the two suites that skip when Rails is missing,
  # and the core job installs the extension's production dependencies so
  # there is something to read.
  #
  # The `before` hook is on the source-reading group only. The
  # restatement scan below needs no `node_modules` and used to be
  # disabled with them, so the guard that catches a fact being stated
  # twice was off in CI as well.
  describe "read from the client's own source" do
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
  end

  # And the tree states it in one place. A second statement of an external
  # fact is how the wrong one survived: it can be corrected in one file
  # while the other stays, and both read as authoritative.
  #
  # Only `docs/design/tasks/**` is out of scope: a dated record saying
  # "this was believed and was wrong" is the account, not a competing
  # claim. Everything else tracked is scanned, in both languages.
  #
  # **The first version of this scanned `docs/*.md` and matched English
  # only**, and the claim it was written to eliminate was newly written,
  # in the same change set, into `docs/design/docs/02-architecture.md` in
  # Japanese -- where it became the sentence `document_store.rb`'s class
  # comment cites as its authority. A review round found it by grepping
  # for both phrasings. A guard whose scope is a hand-written list of
  # directories has the defect it exists to catch, which is the second
  # time that shape has appeared in this file's neighbourhood; the
  # citation scan next door was widened for the same reason.
  PHRASINGS = [/staleness filter/i, /陳腐化フィルタ/].freeze

  it "is stated in one document, which the rest of the tree points at" do
    root = File.expand_path("../../..", __dir__)
    restated = RepoFiles.list(root)
                      .select { |path| path.match?(/\.(rb|ts|md)\z/) }
                      .reject { |path| path.include?("CLIENT_BEHAVIOUR") }
                      .reject { |path| path.start_with?("docs/design/tasks/") }
                      .reject { |path| path.end_with?(File.basename(__FILE__)) }
                      .select do |path|
                        body = File.read(File.join(root, path), encoding: "UTF-8")
                        PHRASINGS.any? { |phrase| body.match?(phrase) }
                      end

    expect(restated).to be_empty,
                        "these state a fact about the client instead of pointing at " \
                        "docs/CLIENT_BEHAVIOUR.md: #{restated.join(', ')}"
  end

  # The Japanese edition of the document was retired in 058: internal
  # documents are one language, and this one is internal. What its guard
  # held -- a row for every row, translated rather than copied, the same
  # rows marked checked -- is recorded in that release's task document.
  #
  # The check is only worth having if it would catch what it was written
  # for, and this file exempts itself from it -- so the matcher is run
  # against a planted restatement rather than trusted.
  it "would catch a restatement outside the one document" do
    expect(PHRASINGS.any? { |phrase| "the staleness filter drops it".match?(phrase) }).to be(true)
    expect(PHRASINGS.any? { |phrase| "陳腐化フィルタが落とす".match?(phrase) }).to be(true)
    expect(PHRASINGS.any? { |phrase| "an unrelated sentence about versions".match?(phrase) }).to be(false)
  end
end

