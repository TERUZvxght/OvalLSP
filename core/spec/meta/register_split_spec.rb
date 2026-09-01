# frozen_string_literal: true

require_relative "../../../scripts/deferred_findings"

# 024.R9. Measured at the revision that moves it, as that entry asks:
# the register was 20,703 lines and 287 entries, and **239 of those
# entries -- 15,670 lines, 75.7% -- were resolved.** So the file every
# session reads, and every scripted edit risks, was three-quarters
# archive. `024.225` records a scripted edit that took it from 11,555
# lines to 25,878 twice over, with the diff too large to read.
#
# Split by state, and **the path does not move**. 024.R9's "proposed
# shape" is a move to the top of `docs/`; 26 tracked files name the
# register by path and every one of them would have had to change to buy
# a shorter string. The split is what the numbers support; the move is
# recorded as available and not taken.
#
# The constraint that decides everything here is 024.R9's own: **one
# place to look.** A reader holding `024.N` must not have to know which
# file it went to. These examples are that constraint.
RSpec.describe "the register, split by state" do
  ROOT_FOR_SPLIT = File.expand_path("../../..", __dir__)
  LIVE = File.join(ROOT_FOR_SPLIT, "docs", "design", "tasks", "024-deferred-review-findings.md")
  ARCHIVE = File.join(ROOT_FOR_SPLIT, "docs", "design", "tasks", "024-deferred-review-findings-resolved.md")

  def read(path) = File.read(path, encoding: "UTF-8")

  let(:live) { read(LIVE) }
  let(:archive) { read(ARCHIVE) }
  let(:combined) { DeferredFindings.register(ROOT_FOR_SPLIT) }

  it "keeps the register at the path 26 tracked files already name" do
    expect(File).to exist(LIVE)
  end

  it "puts the resolved entries in a file of their own" do
    expect(File).to exist(ARCHIVE)
  end

  # The whole point. If a number can be in neither, a citation dangles;
  # if it can be in both, every count double-reads it.
  it "puts every entry in exactly one of the two" do
    in_live = DeferredFindings.headings(live)
    in_archive = DeferredFindings.headings(archive)

    expect(in_live & in_archive).to be_empty, "in both files: #{(in_live & in_archive).inspect}"
    expect((in_live + in_archive).tally.select { |_, n| n > 1 }).to be_empty
  end

  it "sorts them by state and not by anything else" do
    all = DeferredFindings.entries(combined)
    resolved = ->(n) { %w[fixed done].include?(all[n]["status"]) }

    expect(DeferredFindings.headings(live).reject { |n| all[n].nil? }.select(&resolved)).to be_empty,
                                                                                           "resolved entries left in the live file"
    expect(DeferredFindings.headings(archive).reject { |n| all[n].nil? }.reject(&resolved)).to be_empty,
                                                                                              "open entries moved into the archive"
  end

  # `DeferredFindings.register` is what every check reads, so a check
  # written before the split keeps seeing one register. Without this the
  # split silently halves every count in the repository.
  it "answers as one register to everything that reads it" do
    expect(DeferredFindings.headings(combined).length)
      .to eq(DeferredFindings.headings(live).length + DeferredFindings.headings(archive).length)
    expect(DeferredFindings.entries(combined).length).to be >= 287
  end

  # "One place to look": the live file's generated index carries every
  # number, so a reader who opens the file they have always opened finds
  # the archived ones too.
  it "indexes every entry in the live file, archived ones included" do
    index = live[/^\| \[`024\./] ? live : ""
    missing = DeferredFindings.headings(archive).reject { |n| index.include?("[`#{n}`]") }

    expect(missing).to be_empty,
                       "archived entries with no row in the live index -- a reader holding one of these " \
                       "numbers has to know which file it went to: #{missing.first(8).inspect}"
  end

  it "links an archived entry's index row into the archive" do
    number = DeferredFindings.headings(archive).first
    row = live.lines.find { |l| l.include?("[`#{number}`]") }

    expect(row).not_to be_nil
    expect(row).to include("024-deferred-review-findings-resolved.md#")
  end

  # The live file is what this whole entry is about.
  it "leaves the live file a fraction of what it was" do
    expect(live.lines.length).to be < 8_000,
                                 "the live register is #{live.lines.length} lines; it was 20,703 and the " \
                                 "split exists to make it the open work plus its legend"
  end

  # `reindex_findings.rb` rewrites the live file and only reads the
  # archive, so the byte-for-byte rebuild check does not cover the
  # archive's own order. Entries arrive there by being moved, and an
  # entry dropped in the wrong place is invisible until somebody scrolls.
  it "keeps the archive in numeric order too" do
    require_relative "../../../scripts/reindex_findings"

    numbers = DeferredFindings.headings(archive)
    expect(numbers).to eq(numbers.sort_by { |n| ReindexFindings.entry_key(n) })
  end
end
