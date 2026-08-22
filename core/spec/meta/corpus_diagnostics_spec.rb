# frozen_string_literal: true

require "tmpdir"

# `046`'s C8. Every false corpus result this project has recorded came
# from the run not being what the reader thought it was, and
# `026-0.2.1-review-loop.md` lists five: a diff computed from a file
# still being written (79 invented findings), a diff between two
# *different* corpora (10 invented), a `cd` that persisted so both sides
# ran from the same worktree, two processes writing the same output
# files, and a rewritten script that left both sides in the baseline
# tree.
#
# **None would have been caught by re-reading the numbers.** What catches
# them is the run stating what it is -- and the point of a spec here is
# that the statements cannot quietly stop being printed, which is exactly
# how they would be lost: nobody diffs stderr.
#
# The corpus is a throwaway directory, never the repository, so this
# stays fast and says nothing about the tree's own finding counts.
RSpec.describe "corpus_diagnostics.rb reports on its own run" do
  CORPUS_SCRIPT = File.expand_path("../../../scripts/corpus_diagnostics.rb", __dir__)
  CORPUS_CORE = File.expand_path("../..", __dir__)

  # Run from `core/`, which the script requires -- it loads `ovallsp`
  # from `Dir.pwd`.
  def run_corpus(*args)
    out = IO.popen(["ruby", CORPUS_SCRIPT, *args], chdir: CORPUS_CORE, err: [:child, :out], &:read)
    [out, $?.success?]
  end

  around do |example|
    Dir.mktmpdir { |dir| @corpus = dir and example.run }
  end

  def write(name, source)
    path = File.join(@corpus, name)
    File.write(path, source)
    path
  end

  it "states the working directory, revision, version and corpus digest" do
    write("a.rb", "Nope::Missing\n")
    output, ok = run_corpus(@corpus)

    expect(ok).to be(true), output
    %w[cwd revision dirty-tracked-files ovallsp-version signature-root corpus-files corpus-sha256]
      .each { |key| expect(output).to include("corpus-diagnostics: #{key}=") }
  end

  # `026`'s second false result was a diff between two corpora, one of
  # which held this repository's own `core/lib`. "I passed the same
  # argument" is not evidence the two sides saw the same files; a digest
  # over the file list is.
  it "digests the file list, so two runs over different corpora cannot look alike" do
    write("a.rb", "X\n")
    one, = run_corpus(@corpus)
    write("b.rb", "Y\n")
    two, = run_corpus(@corpus)

    digest = ->(text) { text[/corpus-sha256=(\h+)/, 1] }

    expect(digest.call(one)).not_to be_nil
    expect(digest.call(one)).not_to eq(digest.call(two))
  end

  # An empty corpus produces an empty diff, and an empty diff reads as
  # "this change altered nothing" -- the most expensive wrong answer this
  # script can give.
  it "refuses a corpus with no Ruby in it" do
    output, ok = run_corpus(@corpus)

    expect(ok).to be(false), output
    expect(output).to include("matched no .rb files")
  end

  # Before this, a mistyped path was not a directory, so it was taken as
  # a file: the run reported `corpus-files=1`, found nothing, and looked
  # like a run.
  it "refuses a path that does not exist rather than measuring the rest" do
    write("a.rb", "X\n")
    output, ok = run_corpus(@corpus, File.join(@corpus, "no-such-dir"))

    expect(ok).to be(false), output
    expect(output).to include("does not exist")
  end

  describe "--expect-control" do
    # 0.2.1's control was `unresolved-constant`, identical at 9,550 on
    # both sides. A control asserted after the fact is a control chosen
    # to agree, so the expected value is given on the command line before
    # the run.
    before { write("a.rb", "Definitely::Absent\n") }

    it "passes when the control comes out where it was said it would" do
      count, = run_corpus(@corpus)
      actual = count[/count\.unresolved-constant=(\d+)/, 1]
      expect(actual).not_to be_nil, count

      output, ok = run_corpus("--expect-control=unresolved-constant:#{actual}", @corpus)
      expect(ok).to be(true), output
      expect(output).to include("control unresolved-constant = #{actual}, as expected")
    end

    it "fails the run when the control moved, because the two sides are then not comparable" do
      output, ok = run_corpus("--expect-control=unresolved-constant:99999", @corpus)

      expect(ok).to be(false), output
      expect(output).to include("CONTROL FAILED")
    end

    it "refuses a malformed expectation rather than silently checking nothing" do
      output, ok = run_corpus("--expect-control=unresolved-constant", @corpus)

      expect(ok).to be(false), output
      expect(output).to include("wants CODE:N")
    end
  end
end
