# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# `042`'s D10 / `024.122`. Every `rescue` statement in `core/lib` carries
# a verdict, and a new one with no verdict fails here.
#
# That is the whole mechanism, and it is deliberately not "no rescue may
# swallow". A rule saying that would have had 111 exceptions on the day
# it was written, which is the arrangement `CLAUDE.md`'s preamble warns
# about. What this enforces is that **the decision is made**: writing a
# rescue means writing down what happens to the failure, in a file a
# reviewer reads.
#
# The column that would hold an unargued site is empty and has been since
# 0.2.13. What keeps it empty is the checker's refusal; what keeps the
# *record of that* true is the second example below, added in 0.2.16
# after `024.217` found three places stating the arrangement and all
# three describing the one that ended two releases earlier -- including
# an instruction that, followed, fails the suite.
RSpec.describe "rescue verdicts" do
  SWALLOWED_FAILURES_ROOT = File.expand_path("../../..", __dir__)
  SWALLOWED_FAILURES_SCRIPT = File.join(SWALLOWED_FAILURES_ROOT, "scripts", "check_swallowed_failures.rb")
  SWALLOWED_FAILURES_VERDICTS = File.join(SWALLOWED_FAILURES_ROOT, "core", "spec", "meta", "rescue_verdicts.yml")

  # What a site may carry, asked of the checker rather than restated here.
  def self.allowed_verdicts
    out = IO.popen(["ruby", SWALLOWED_FAILURES_SCRIPT, "--verdicts"], err: %i[child out], &:read)
    raise "cannot read the allowed verdicts: #{out}" unless $?.success?

    out.split("\n").map(&:strip).reject(&:empty?)
  end

  it "covers every rescue in core/lib, and nothing that is gone" do
    output = IO.popen(["ruby", SWALLOWED_FAILURES_SCRIPT], err: %i[child out], &:read)

    expect($?).to be_success, output
  end

  # **How much of the tree it read**, which nothing here asserted.
  #
  # `024.151` is the class: "the checks are correct; their reachability
  # is not defended". Its sharpest instance was `check_doc_links`' `SKIP`
  # constant — widening it dropped inspection from 537 files to 117 and
  # every example still passed, because they asserted outcomes on
  # fixtures and none asserted how much was read.
  #
  # **This checker has the same gap, and unlike its sibling no guard
  # against it.** `check_pinned_mutations` refuses an empty manifest
  # outright; `check_swallowed_failures` has no emptiness test at all —
  # its `Dir.glob` returning nothing makes `problems` empty, which is
  # what it reports as success. Narrow the scan and every rescue is
  # accounted for, because none was found.
  #
  # The floor is a floor, not the count. Rescues are added and removed
  # every release, and an exact number would fail on the next one for a
  # reason nobody wants to read — while a scan that has stopped seeing
  # `core/lib` does not return 140-something, it returns nothing.
  it "read the whole of core/lib, rather than reporting a narrowed scan clean" do
    output = IO.popen(["ruby", SWALLOWED_FAILURES_SCRIPT], err: %i[child out], &:read)

    sites = output[/(\d+) rescue site\(s\)/, 1].to_i
    expect(sites).to be >= 100,
                     "the scan found #{sites} rescue sites in core/lib. A checker that reads less than it " \
                     "thinks reports exactly what a working one reports when nothing is wrong (024.151).\n#{output}"
  end

  # The header of the verdicts file is a set of instructions, and an
  # instruction is a claim. Its option bullets are parsed structurally --
  # a `#` comment line of `name -- description` inside the header block --
  # and compared against the checker's own list. A spelling the checker
  # refuses cannot appear as an option, and an option the checker does not
  # accept cannot appear at all.
  #
  # Prose is not asserted, because prose cannot be. What this stops is the
  # shape `024.217` records: the file telling the next author to write a
  # verdict that fails.
  it "offers the reader exactly the verdicts the checker accepts" do
    header = File.read(SWALLOWED_FAILURES_VERDICTS, encoding: "UTF-8")
                 .lines.take_while { |line| line.start_with?("#") || line.strip.empty? }

    offered = header.filter_map { |line| line[/\A#\s{2,}([a-z]+)\s+--\s/, 1] }

    expect(offered).to match_array(self.class.allowed_verdicts),
                       "the verdicts file offers #{offered.inspect} and the checker accepts " \
                       "#{self.class.allowed_verdicts.inspect}. A reader following this header must not " \
                       "be told to write a verdict the checker refuses -- that is 024.217."
  end

  # And the guidance a *new* rescue receives has to name the same two.
  # Proved by running the checker against a throwaway tree that has one
  # unverdicted rescue in it, rather than by searching this script's
  # source for its own message: a message is text, and text satisfying a
  # text search is the family `024.151` names.
  it "tells an author with no verdict to write one the checker will accept" do
    Dir.mktmpdir do |root|
      lib = File.join(root, "core", "lib", "ovallsp")
      FileUtils.mkdir_p(lib)
      FileUtils.mkdir_p(File.join(root, "core", "spec", "meta"))
      File.write(File.join(lib, "probe.rb"), <<~RUBY)
        def probe
          Integer("x")
        rescue ArgumentError
          nil
        end
      RUBY
      File.write(File.join(root, "core", "spec", "meta", "rescue_verdicts.yml"), "{}\n")

      out = IO.popen({ "CHECK_SWALLOWED_FAILURES_ROOT" => root },
                     ["ruby", SWALLOWED_FAILURES_SCRIPT], err: %i[child out], &:read)

      expect($?).not_to be_success, "an unverdicted rescue was accepted: #{out}"
      expect(out).to include("has no verdict")

      guidance = out[/has no verdict\.(.*)/m, 1].to_s
      self.class.allowed_verdicts.each do |verdict|
        expect(guidance).to include(verdict), "the guidance does not name #{verdict}: #{guidance}"
      end

      refused = %w[surfaces contained swallows] - self.class.allowed_verdicts
      refused.each do |verdict|
        expect(guidance).not_to include(verdict),
                                "the guidance offers #{verdict}, which the checker's next branch refuses. " \
                                "That is 024.217."
      end
    end
  end
end
