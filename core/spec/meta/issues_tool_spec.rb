# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../../../scripts/issues"

# `scripts/issues.rb` browses and changes the issue register so that
# neither is hand-editing a 25,000-line document with a strict grammar.
#
# **These examples are about the write primitive, because that is where
# the damage lives.** `024.225` is a scripted edit that pasted the whole
# preceding file in at its anchor -- twice, taking the register from
# 11,555 lines to 25,878 -- and the line count was the only symptom.
# Every mutating subcommand goes through `Issues.rewrite`, which is told
# what the change should cost and refuses one that costs anything else.
#
# The first version of `#verify_shape!` only re-parsed the yaml blocks,
# and an attack walked past it. These four are the ones that now hold,
# and the fifth is the control: without it they would all pass on a
# primitive that simply refused everything.
RSpec.describe "scripts/issues.rb" do
  # `example_tmpdir`, not `Dir.mktmpdir`: the block-less form never
  # removes what it creates, and `tmpdir_hygiene_spec` refuses it.
  let(:root) { example_tmpdir("issues-tool") }
  let(:register) { File.join(root, "docs", "design", "tasks", "024-deferred-review-findings.md") }
  let(:repo) { File.expand_path("../../..", __dir__) }

  before do
    FileUtils.mkdir_p(File.dirname(register))
    FileUtils.cp(File.join(repo, "docs/design/tasks/024-deferred-review-findings.md"), register)
    FileUtils.cp(File.join(repo, "docs/design/tasks/024-deferred-review-findings-resolved.md"),
                 File.join(File.dirname(register), "024-deferred-review-findings-resolved.md"))
    stub_const("Issues::ROOT", root)
  end

  def lines_now = File.readlines(register, encoding: "UTF-8").length

  def attempt(expect_delta:, expect_entries: 0, &block)
    Issues.rewrite(register, expect_delta: expect_delta, why: "spec", expect_entries: expect_entries, &block)
  end

  def first_heading(lines) = lines.index { |l| l.start_with?("## 024.") }

  it "refuses the edit that pasted the file into itself" do
    before = lines_now

    expect { attempt(expect_delta: 2) { |lines| lines + lines } }
      .to raise_error(Issues::RefusedWrite, /changed by #{before}/)
    expect(lines_now).to eq(before)
  end

  it "refuses an unknown key inside a real entry's block, and puts the file back" do
    before = lines_now

    expect do
      attempt(expect_delta: 1) do |lines|
        h = first_heading(lines)
        lines.insert((h...lines.length).find { |i| lines[i].start_with?("status: ") }, "not_a_key: x\n")
      end
    end.to raise_error(Issues::RefusedWrite, /no longer parses/)
    expect(lines_now).to eq(before)
  end

  it "refuses an edit that loses an entry even when the line delta is declared honestly" do
    before = lines_now

    expect do
      attempt(expect_delta: 0) do |lines|
        first = first_heading(lines)
        second = (first + 1...lines.length).find { |i| lines[i].start_with?("## 024.") }
        lines[first...second] = ["\n"] * (second - first)
        lines
      end
    end.to raise_error(Issues::RefusedWrite, /entry count changed by -1/)
    expect(lines_now).to eq(before)
  end

  it "refuses a heading whose metadata no longer follows it" do
    expect do
      attempt(expect_delta: -1) { |lines| lines.delete_at(first_heading(lines)) && lines }
    end.to raise_error(Issues::RefusedWrite)
  end

  # **The control.** A primitive that refused everything would pass all
  # four examples above, so one honest edit has to go through.
  it "allows an edit whose cost is what the caller declared" do
    before = lines_now

    expect(attempt(expect_delta: 1) { |lines| lines + ["\n"] }).to eq(1)
    expect(lines_now).to eq(before + 1)
  end

  describe "browsing" do
    it "reads every entry through the same reader the specs use" do
      numbers = Issues.all.map(&:number)

      expect(numbers).to include("024.243")
      expect(numbers.length).to eq(DeferredFindings.headings(DeferredFindings.register(root)).length)
    end

    it "never hands out a number that is in use or retired" do
      allocated = Issues.next_number
      markdown = DeferredFindings.register(root)

      expect(DeferredFindings.headings(markdown)).not_to include(allocated)
      expect(DeferredFindings.retired_numbers(markdown)).not_to include(allocated)
    end
  end

  # **The two ends of an entry's life, as commands rather than as prose.**
  #
  # Opening one means allocating a number that has never been used,
  # writing four enforced fields in the legend's shape, and taking the
  # item back out of intake; closing one means moving it across two files
  # *and* dealing with the paragraph each language publishes about it.
  # `docs/ISSUES.md`'s "The rule" is the order those decisions are made
  # in, and until this it was the only thing holding them together.
  #
  # These examples run the whole command, delegated scripts included, by
  # giving the throwaway root a copy of `scripts/` — so what is asserted
  # is that the register still passes its own guards afterwards, not that
  # one substitution landed.
  describe "opening and closing an entry" do
    let(:issues_doc) { File.join(root, "docs", "ISSUES.md") }
    let(:english) { File.join(root, "docs", "KNOWN_LIMITATIONS.md") }
    let(:japanese) { File.join(root, "docs", "KNOWN_LIMITATIONS.ja.md") }

    before do
      %w[docs/ISSUES.md docs/KNOWN_LIMITATIONS.md docs/KNOWN_LIMITATIONS.ja.md].each do |relative|
        FileUtils.cp(File.join(repo, relative), File.join(root, relative))
      end
      # The delegated guards resolve their own root from `__dir__`, so a
      # copy of them here is a copy that reads *this* register. Without
      # it they would read the real one, report it current, and say
      # nothing about the file under test.
      FileUtils.cp_r(File.join(repo, "scripts"), root)
    end

    def promote(position, *extra)
      Issues.run(["promote", position.to_s, "--kind=friction", "--target=0.4.0",
                  "--area=`scripts/issues.rb`", "--direction=Give it a command.", *extra])
    end

    # `docs/ISSUES.md` is copied whole, items and all, so a planted one
    # goes to the end of a list that already has entries — and its
    # position is what `promote` is given.
    def plant_intake(title)
      Issues.run(["intake", "add", title, "--where=a spec", "--detail=what was seen"])
      intake_titles.length
    end

    # The intake list itself, not the document: a promoted entry's title
    # reappears in `docs/ISSUES.md` a moment later, in the generated index
    # of open entries, so reading the whole file cannot tell "still in
    # intake" from "promoted".
    def intake_titles
      Issues.intake_items(File.readlines(issues_doc, encoding: "UTF-8")).map { |(_, title, _)| title }
    end

    # A limitation section shaped the way the real pages shape one: a
    # heading, prose, and the marker at the end of the line that
    # documents the finding.
    def publish(number, heading)
      [english, japanese].each do |path|
        File.write(path, "#{File.read(path, encoding: 'UTF-8')}\n\n## #{heading}\n\n" \
                         "What a reader would meet. <!-- documents: #{number} -->\n")
      end
    end

    describe "the intake list" do
      # **Two shapes are in the list today.** `intake add` writes the
      # title on one line and the detail as sub-bullets; an item written
      # by hand wraps the bold title across lines and continues in prose
      # on the line that closes it. A reader that only understood the
      # first saw none of the second, and reported an intake list with
      # items in it as empty — which is what `promote <n>` counts
      # positions in.
      it "reads an item whose bold title wraps across lines" do
        expect(intake_titles).not_to be_empty, "docs/ISSUES.md's own items were read as nothing"
        expect(intake_titles).to all(satisfy { |title| !title.include?("\n") })
      end

      it "counts what `intake add` writes and what is written by hand as one list" do
        before_add = intake_titles.length
        plant_intake("A thing that was noticed")

        expect(before_add).to be > 0, "the hand-written items were counted as none"
        expect(intake_titles.length).to eq(before_add + 1)
        expect(intake_titles.last).to eq("A thing that was noticed")
      end

      it "keeps the count sentence current when an item arrives" do
        before_add = intake_titles.length

        plant_intake("A thing that was noticed")

        lines = File.readlines(issues_doc, encoding: "UTF-8")
        sentence = lines.index { |line| line.match?(Issues::INTAKE_COUNT) }
        expect(lines.join).to match(/\*\*#{Issues.count_word(before_add + 1)} items? above;/i)
        expect(Issues.intake_items(lines).map(&:first)).to all(be < sentence),
                                                          "an item was written below the sentence counting it"

        # **Above the sentence is not enough**, and the mutation manifest
        # said so: inserting at the sentence is also above it, and lands
        # the bullet across the blank line from the list and hard against
        # the paragraph — one list broken into two, with the sentence
        # swallowed. The item joins the run, and the blank that separates
        # the run from the sentence stays where it is.
        planted = Issues.intake_items(lines).find { |(_, title, _, _)| title == "A thing that was noticed" }
        expect(lines[planted.first - 1].strip).not_to be_empty,
                                                      "the new bullet was written across a blank from the list"
        expect(lines[sentence - 1].strip).to be_empty,
                                             "the sentence lost the blank line separating it from the list"
      end

      # **Zero keeps the same sentence.** The list read "Empty, and
      # emptied deliberately" before it had items, and going back to that
      # wording at zero would take the sentence out of `INTAKE_COUNT`'s
      # reach — so the next item to arrive would restore a list under a
      # sentence nothing could restate, and the count would go stale
      # silently. One shape, always findable, is the property worth more
      # than the nicer wording.
      it "says 'No items above' once the list empties, in a sentence still findable" do
        intake_titles.length.times do
          expect(promote(1, "--user-visible=no", "--note=Internal to this repository.")).to eq(0)
        end

        body = File.read(issues_doc, encoding: "UTF-8")
        expect(intake_titles).to be_empty
        expect(body).to include("**No items above;")
        expect(body).to match(Issues::INTAKE_COUNT)
      end

      # The list's own sentence says how many items stand above it, and a
      # count nobody updates is the class of claim this repository
      # re-derives rather than types.
      it "keeps the count sentence current when an item leaves" do
        before_count = intake_titles.length
        expect(File.read(issues_doc, encoding: "UTF-8")).to match(/\*\*\S+ items? above;/)

        expect(promote(1, "--user-visible=no", "--note=Internal to this repository.")).to eq(0)

        expect(intake_titles.length).to eq(before_count - 1)
        expect(File.read(issues_doc, encoding: "UTF-8"))
          .to match(/\*\*#{Issues.count_word(before_count - 1)} items? above;/i)
      end
    end

    describe "promote" do
      it "moves an intake item into the register under a number never used before" do
        at = plant_intake("A thing that was noticed")
        allocated = Issues.next_number

        expect(promote(at, "--user-visible=no", "--note=Internal to this repository.")).to eq(0)

        entry = Issues.find(allocated)
        expect(entry).not_to be_nil, "no entry #{allocated} after promote"
        expect(entry.title).to eq("A thing that was noticed")
        expect(entry.meta).to include("status" => "open", "kind" => "friction", "target" => "0.4.0")
        expect(entry.body).to include("what was seen")
        expect(entry.body).not_to include(Issues::INTAKE_UNVERIFIED),
                                  "promoting an item is the claim that it was driven"
        expect(intake_titles).not_to include("A thing that was noticed")
      end

      it "refuses a defect that does not say whether a user meets it" do
        at = plant_intake("A wrong answer")
        before_refusal = Issues.next_number

        expect(Issues.run(["promote", at.to_s, "--kind=defect", "--target=0.4.0",
                           "--area=`scripts/issues.rb`", "--direction=Fix it."])).to eq(2)
        expect(Issues.next_number).to eq(before_refusal), "a refused promote still spent a number"
        expect(intake_titles).to include("A wrong answer")
      end

      it "refuses `user-visible: no` with no reason, which the register's own guard demands" do
        at = plant_intake("A thing nobody meets")

        expect(promote(at, "--user-visible=no")).to eq(2)
        expect(intake_titles).to include("A thing nobody meets")
      end

      # Everything else about this invocation is valid, so the only thing
      # left to refuse on is the position. Without that the example
      # passes on whichever refusal happens to come first, which is a
      # test of the option parser wearing this one's name.
      it "refuses a position the intake list does not have" do
        past_the_end = intake_titles.length + 1

        expect(promote(past_the_end, "--user-visible=no", "--note=Internal to this repository.")).to eq(2)
      end

      # **The control.** Every example above asserts a refusal, and a
      # command that refused everything would satisfy all of them. This
      # one says the register is still a register afterwards: its own
      # three guards, run against the file the command wrote.
      it "leaves the register passing the guards it delegates to" do
        at = plant_intake("A thing that was noticed")

        expect(promote(at, "--user-visible=no", "--note=Internal to this repository.")).to eq(0)
      end

      # **A delegated script's refusal is its message, not its status.**
      # Running them with the output discarded meant the reason was
      # thrown away and only "FAILED" survived — the shape this
      # repository calls a checker that cannot say what it saw. Planted
      # by replacing the copy in this root, which is the seam the whole
      # describe block already turns on.
      it "prints the delegated script's own message when one refuses" do
        File.write(File.join(root, "scripts", "reindex_findings.rb"),
                   "warn 'reindex-findings: the register is out of order'\nexit 1\n")
        at = plant_intake("A thing that was noticed")

        expect { expect(promote(at, "--user-visible=no", "--note=Internal.")).to eq(2) }
          .to output(/the register is out of order/).to_stderr
      end
    end

    describe "close" do
      def open_a_published_entry
        at = plant_intake("A thing a user meets")
        number = Issues.next_number
        promote(at, "--user-visible=yes")
        publish(number, "Something a user meets")
        number
      end

      it "refuses while either language still publishes a paragraph for it" do
        number = open_a_published_entry

        expect(Issues.run(["close", number, "--released-in=0.4.0"])).to eq(2)
        expect(Issues.find(number).status).to eq("open")
      end

      it "closes it, and drops the section both languages published, when told to" do
        number = open_a_published_entry

        expect(Issues.run(["close", number, "--released-in=0.4.0", "--drop-paragraphs"])).to eq(0)

        entry = Issues.find(number)
        expect(entry.status).to eq("fixed")
        expect(entry.meta["released-in"]).to eq("0.4.0")
        expect(entry.archived).to be(true), "a resolved entry left in the live file breaks the split"
        expect(Issues.published_in(number)).to be_empty
        expect(File.read(english, encoding: "UTF-8")).not_to include("Something a user meets")
        expect(File.read(japanese, encoding: "UTF-8")).not_to include("Something a user meets")
      end

      it "refuses an entry that is already resolved" do
        number = open_a_published_entry
        Issues.run(["close", number, "--released-in=0.4.0", "--drop-paragraphs"])

        expect(Issues.run(["close", number, "--released-in=0.4.0"])).to eq(2)
      end

      it "refuses a number no entry carries" do
        expect(Issues.run(["close", unspellable_number(997), "--released-in=0.4.0"])).to eq(2)
      end

      # **The control for the paragraph half.** Without it, a `close`
      # that never looked at either document would pass every example
      # above: the refusal ones by refusing, and the closing one by
      # closing.
      it "closes an entry no language publishes without being told to drop anything" do
        at = plant_intake("A thing nobody meets")
        number = Issues.next_number
        promote(at, "--user-visible=no", "--note=Internal to this repository.")

        expect(Issues.run(["close", number, "--released-in=0.4.0"])).to eq(0)
        expect(Issues.find(number).status).to eq("fixed")
      end
    end
  end
end
