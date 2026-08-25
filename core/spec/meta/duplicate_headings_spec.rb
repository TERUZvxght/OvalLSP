# frozen_string_literal: true

# Enumerated with `RepoFiles`, not `git ls-files` — `024.147`. A file you
# have just written is untracked until `git add`, and `preflight` runs
# before the commit, so a check that lists only tracked files is blind to
# exactly the file being worked on.
require_relative "../../../scripts/repo_files"

require "tmpdir"

# `024.140`. A scripted edit with a bad end boundary pastes a block back
# instead of moving it, and the result is a well-formed document that
# says the same thing twice. It happened twice in one session -- once in
# the register (`024.69`'s whole body) and once in a design document
# (`07-vscode-extension.md`, the entire file) -- and the first survived a
# full green suite and a commit.
#
# `deferred_findings_spec.rb` caught the first shape afterwards by
# requiring one `**Area:**` per entry. That was aimed at the symptom: it
# guards one file. This asks the same question of every tracked Markdown
# document, and it is the check that would have caught both.
#
# **The guarantee, stated here and nowhere else** -- `024.206` is what
# happened when a second copy of it drifted:
#
#     No tracked Markdown document states the same heading *path* twice.
#
# A path is the heading's own text preceded by the headings enclosing it,
# at levels one to six, indented up to three spaces, outside fenced
# blocks. The path rather than the text alone, because a subsection name
# legitimately repeats under a different parent -- a per-release
# `Details`, a per-task `Deliverables` -- while a pasted block duplicates
# its parent too and so repeats the whole path.
#
# Three things it must get right to be worth having:
#
# - **Fenced blocks are not headings.** `10-ai-execution-guide.md` quotes
#   a task template and a report template, both of which contain `##
#   Tests`. A line-based scan reports that file and the honest response
#   would be an exemption, which is `024.126`'s trap.
# - **It must fire on the real thing.** The example below plants the
#   actual defect -- a document's own body appended to itself.
# - **It must have read the file.** "No repeated heading" is also what a
#   scan that stopped at line twelve reports, so the fence state at EOF
#   is asserted too (`024.205`).
RSpec.describe "tracked Markdown documents" do
  DUP_HEADINGS_ROOT = File.expand_path("../../..", __dir__)

  # Headings outside fenced code blocks, each as the path of headings
  # enclosing it. Both ``` and ~~~ open a fence, and a fence closes on a
  # marker of the *same character* and at least the opener's length -- so
  # a ``` inside a ~~~ block is content, and a ``` inside a ```` block is
  # content too, which is how this file's own examples stay quotable.
  #
  # `024.205`. This used to store `marker[0]` and discard the length, so
  # inside a ````-fenced block quoting ```-fenced code -- the
  # markdown-in-markdown shape this repository writes constantly -- the
  # inner ``` closed the fence and the real closer opened one that never
  # closed. Every heading from there to EOF was invisible and the file
  # was reported clean having been read no further, which is the named
  # pattern: a check that cannot see the thing it checks reports what a
  # working check reports. `scan` therefore returns the fence state as
  # well, and the example over the tree asserts it is closed.
  #
  # `024.206`. Levels 1--6, and up to three leading spaces, because that
  # is what a renderer reads as a heading and what `024.140` states the
  # guarantee over -- h3 subsections are where a mis-sliced scripted edit
  # actually lands. Keyed on the *path* rather than the text alone: a
  # per-release `### Details` or a per-task `### Deliverables` is a
  # legitimate repeat under a different parent, while a pasted block
  # duplicates its parent too and so repeats the whole path.
  HeadingScan = Struct.new(:headings, :open_fence)

  def self.scan(text)
    fence = nil
    chain = []
    headings = []

    text.each_line do |line|
      marker = line[/\A\s*(`{3,}|~{3,})/, 1]
      if marker
        if fence.nil? then fence = marker
        elsif marker[0] == fence[0] && marker.length >= fence.length then fence = nil
        end
        next
      end
      next if fence

      hashes = line[/\A {0,3}(\#{1,6}) \S/, 1]
      next unless hashes

      # Truncate to the enclosing levels, then place this one. A document
      # that skips a level leaves a hole, which `compact` drops.
      chain = chain[0, hashes.length - 1]
      chain[hashes.length - 1] = line.strip
      headings << chain.compact.join(" > ")
    end

    HeadingScan.new(headings, fence)
  end

  def self.headings_in(text) = scan(text).headings

  def self.tracked_markdown
    RepoFiles.list(DUP_HEADINGS_ROOT, "*.md")
             .reject { |f| f.start_with?("core/vendor/", "vscode/node_modules/") }
  end

  def self.scanned
    tracked_markdown.filter_map do |rel|
      path = File.join(DUP_HEADINGS_ROOT, rel)
      next unless File.file?(path)

      text = File.read(path, encoding: "UTF-8")
      next unless text.valid_encoding?

      [rel, scan(text)]
    end
  end

  it "never state one heading twice, which is what a pasted block looks like" do
    offenders = self.class.scanned.filter_map do |rel, result|
      repeated = result.headings.tally.select { |_, count| count > 1 }
      "#{rel}: #{repeated.map { |h, c| "#{h.inspect} x#{c}" }.join(", ")}" unless repeated.empty?
    end

    expect(offenders).to be_empty,
                         "documents stating a heading more than once:\n  #{offenders.join("\n  ")}\n" \
                         "A repeated heading is usually a block pasted rather than moved -- check the " \
                         "section is not in the file twice before renaming it."
  end

  # `024.205`. The structural half of the example above: "no repeat" is
  # also what a scan that stopped reading at line 12 reports. A fence
  # still open at EOF means every heading below it was skipped, so the
  # coverage is asserted rather than assumed -- and it is a property, not
  # a maintained number.
  it "read each document to the end, rather than stopping at an unclosed fence" do
    unread = self.class.scanned.filter_map { |rel, result| "#{rel} (#{result.open_fence})" if result.open_fence }

    expect(unread).to be_empty,
                      "documents whose fence never closed, so the check stopped reading there:\n  " \
                      "#{unread.join("\n  ")}\nEverything below that line was examined by nothing."
  end

  it "does not read a heading inside a fenced block as one" do
    quoted = <<~MD
      # Real

      ```markdown
      ## Tests
      ```

      ```markdown
      ## Tests
      ```
    MD

    expect(self.class.headings_in(quoted)).to eq(["# Real"])
  end

  it "catches a document whose body was appended to itself" do
    body = "# Title\n\n## One\n\ntext\n\n## Two\n\nmore\n"

    expect(self.class.headings_in(body + body).tally.values).to include(2)
  end

  # `024.205`. The outer fence is four characters and quotes a Markdown
  # document that has both a heading and a three-character fence of its
  # own -- which is how a document here quotes Markdown.
  #
  # The fixture has to be chosen with care: a four-character block
  # quoting a *balanced* pair of three-character markers cannot
  # distinguish anything, because storing only the character opens and
  # closes twice and lands on the same state. The heading between the
  # inner pair is what makes the two readings differ -- it is content to
  # a reader that respects the length and a heading to one that does not.
  it "does not let a shorter marker close a longer fence" do
    quoted = <<~MD
      # Doc

      ````markdown
      ## Quoted

      ```
      ## Inner
      ```
      ````

      ## Real

      a
    MD

    result = self.class.scan(quoted)

    expect(result.open_fence).to be_nil
    expect(result.headings).to eq(["# Doc", "# Doc > ## Real"])
  end

  # `024.206`. Both halves, each stated as the case that must fail.
  it "reads a heading indented up to three spaces, which every renderer does" do
    indented = "# Doc\n\n   ## Dup\n\na\n\n   ## Dup\n\nb\n"

    expect(self.class.headings_in(indented).tally.values).to include(2)
  end

  it "reads a subsection heading, which is where a mis-sliced edit lands" do
    subsections = "# Doc\n\n## Section\n\n### Dup\n\na\n\n### Dup\n\nb\n"

    expect(self.class.headings_in(subsections).tally.values).to include(2)
  end

  # And the control for the path keying, or the example above cannot tell
  # a working rule from one that reports every repeated subsection: the
  # same subsection name under two different parents is not a paste.
  it "leaves the same subsection name under two different parents alone" do
    per_release = "# Doc\n\n## 0.2.15\n\n### Details\n\na\n\n## 0.2.16\n\n### Details\n\nb\n"

    expect(self.class.headings_in(per_release).tally.values).to all(eq(1))
  end

  # `024.207`. Two decisions in the fence tracker that all three of the
  # examples above leave green when they are reverted, because none of
  # their fixtures nests one marker character inside the other.
  #
  # (1) A fence closes on the *same* marker. Toggling unconditionally --
  # `fence = fence.nil? ? marker : nil` -- reads the inner ``` as the
  # closer, and `## Quoted` becomes a heading.
  it "treats a backtick fence inside a tilde fence as content" do
    nested = "# Doc\n\n~~~markdown\n```\n## Quoted\n```\n~~~\n\n## Real\n\nx\n\n## Also real\n\ny\n"

    expect(self.class.headings_in(nested)).to eq(["# Doc", "# Doc > ## Real", "# Doc > ## Also real"])
  end

  # (2) `~~~` opens a fence at all. Deleting the tilde alternative from
  # the marker pattern makes `## Quoted` a heading; the fixture above
  # cannot see that, because its tilde lines are inside no fence either
  # way once the backtick pair is read as one.
  it "treats a tilde fence as a fence" do
    tilde = "# Doc\n\n~~~\n## Quoted\n~~~\n\n## Real\n\nx\n"

    expect(self.class.headings_in(tilde)).to eq(["# Doc", "# Doc > ## Real"])
  end
end
