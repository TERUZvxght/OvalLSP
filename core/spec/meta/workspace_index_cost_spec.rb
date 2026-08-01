# frozen_string_literal: true

# Two decisions in `WorkspaceIndex` are about cost, not about answers, so
# no behavioural spec can hold them: reversing either leaves every one of
# this suite's examples green while multiplying the work a keystroke does.
# Both are justified by measurements recorded next to the code, and both
# are the kind of line a later reader tidies -- a `select` after a `sort`
# reads no worse than before it, and `sort_by { }.first(n)` is the more
# familiar idiom.
#
# Asserting on source text is how this repository pins a decision it
# cannot execute a test against (`spec/meta/ci_skip_guard_spec.rb`,
# `vscode/src/test/unit/versionPairing.test.ts`). The assertions below are
# deliberately about *which method is called*, not about formatting.
RSpec.describe "WorkspaceIndex's two cost decisions" do
  let(:source) { File.read(File.expand_path("../../lib/ovallsp/workspace_index.rb", __dir__), encoding: "UTF-8") }

  def body_of(method)
    source[/    def #{Regexp.escape(method)}\b.*?\n    end/m] or
      raise "no method #{method} in workspace_index.rb"
  end

  # A bucket is keyed on the downcased *simple* name, so it mixes kinds: a
  # workspace where 1,200 service objects each define `call` puts 1,200
  # method symbols in the bucket `resolve_type_name("Call")` reads.
  # Sorting before filtering measured 3.7ms per call against 51us, on a
  # path `Diagnostics::Engine` runs per constant candidate.
  it "filters a simple-name bucket before sorting it, not after" do
    body = body_of("ordered_symbol_ids")

    expect(body.index(".select(&matching)")).to be < body.index(".sort_by")
  end

  # `workspace/symbol` truncates, and the picker opens with an empty
  # query, so every declaration in the workspace is a match. Sorting all
  # of them on the seven-element key measured 68ms against 23.6ms for
  # `min_by(limit)`, which answers identically because the key is total.
  it "takes only the matches it will return, rather than sorting them all" do
    body = body_of("rank")

    expect(body).to include("matches.min_by(limit)")
    expect(body).not_to include("matches.sort_by")
  end

  # A file that reopens one class ten times touches one symbol ten times.
  # Re-sorting an already-sorted list is correct, so nothing behavioural
  # fails without the `uniq` -- it is the same class of decision as the
  # two above.
  it "sorts each touched symbol once per file, not once per declaration" do
    expect(body_of("replace_file")).to include("touched.uniq.each")
  end

  # The limit reaching `rank` needs no assertion of its own: taking it
  # back out of the signature leaves `min_by(limit)` referring to nothing,
  # which is a NameError on the first query rather than a silent revert.
end
