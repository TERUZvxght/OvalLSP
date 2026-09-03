# frozen_string_literal: true

# The working rules are one short file, `AGENTS.md`, and `CLAUDE.md` is
# an import of it -- so every agent reads the same card and nothing is
# kept in step by hand. `058` set this up, replacing an 803-line
# `CLAUDE.md` and a 199-line `AGENTS.md` that restated it.
#
# What this holds:
#
# - **The card stays a card.** A line budget, because the file this
#   replaced grew a paragraph per incident for forty releases until the
#   rules were no longer legible among their own histories. Adding a
#   line costs a line, or a check that makes the line unnecessary.
# - **`CLAUDE.md` stays an import.** Held by pinning the whole file, not
#   by counting list items: 058's third review round wrote a rival
#   rulebook into it as prose, under the note, and the count did not
#   notice. A rule written there and not in the card is a second
#   rulebook, which is `024.150`'s shape.
# - **The card points; it does not claim.** Which release is being
#   prepared, on which branch, and in which task file is what
#   `git branch --show-current` and the highest-numbered task file say.
#   A claim written here went stale within one release each time it was
#   tried; `agents_pointer_spec` guarded that until 058 folded it in
#   here, and the same round widened both patterns past the spellings
#   the old one knew -- a branch outside backticks, a two-part version,
#   this change set's own `worktree-` branch, a task file named anywhere
#   in the card but the two it reads by reference.
# - **The documents behind the card say which section they stand
#   behind, and that section exists.** The countermeasure `024.150`
#   records, in a new shape -- that entry describes the first one, the
#   `restates` markers 058 retired with the spec that read them. The
#   list of documents is read from the card's own index, so a document
#   added there is asked by default. What is *not* checked is that the
#   declared section is the right one: a declaration is a claim, and
#   this holds only that it names something.
RSpec.describe "the working-rules card" do
  AGENTS_CARD_ROOT = File.expand_path("../../..", __dir__)
  # The budget sits within a line of the card as 058 wrote it: a new
  # line has to pay for itself.
  AGENTS_CARD_BUDGET = 120

  # `CLAUDE.md`, whole. Changing the note means changing this too, on
  # purpose: the file is not where anything else goes.
  CLAUDE_MD = <<~MD
    @AGENTS.md

    ## Claude Code

    The project's working rules are `AGENTS.md`, imported above so that Claude
    Code and every other agent read one card rather than two copies of it. If
    this note is all you can see of this file's content, the import did not
    load: open `AGENTS.md` before doing anything else.
  MD

  # A branch a piece of work is on, in any spelling this project has
  # used, or a sentence that says which release is in hand. The generic
  # `release/<version>` the documents use has no digit after the slash.
  AGENTS_CARD_STALE_CLAIM = %r{(?:feat|fix|release|worktree)[-/][0-9][0-9.]*|being prepared|in preparation|in hand}i
  # A task file named by number -- the pointer that went stale three times.
  AGENTS_CARD_TASK_FILE = %r{\b\d{3}(?:\.\d+)?-[a-z0-9.-]+\.md\b}
  # The two task documents the card sends a reader to, and may name.
  AGENTS_CARD_REFERENCE_TASKS = %w[036-road-to-1.0.0.md 042-second-enumeration.md].freeze
  # How a document behind the card declares the section it stands behind.
  AGENTS_CARD_STANDS_BEHIND = /`AGENTS\.md`'s\s+"([^"]+)"/
  # Documents the index names that are not asked to declare: a user-facing
  # document is written for a reader who does not know the card, and a
  # task record is history.
  AGENTS_CARD_UNDECLARED = %r{\Adocs/ROADMAP\.md\z|\Adocs/design/tasks/}

  def card = File.read(File.join(AGENTS_CARD_ROOT, "AGENTS.md"), encoding: "UTF-8")
  def claude = File.read(File.join(AGENTS_CARD_ROOT, "CLAUDE.md"), encoding: "UTF-8")
  def headings = card.lines.grep(/^## /).map { |l| l.sub(/^## /, "").strip }

  # The index section, from its heading to the next.
  def index_section
    start = card.index("## Where the rules are")
    raise "the index section is gone from AGENTS.md" if start.nil?

    finish = card.index("\n## ", start + 3) || card.length
    card[start...finish]
  end

  def indexed_documents = index_section.scan(%r{`(docs/[A-Za-z0-9._/-]+\.md)`}).flatten.uniq

  it "fits its budget" do
    lines = card.lines.length
    expect(lines).to be <= AGENTS_CARD_BUDGET,
                     "AGENTS.md is #{lines} lines; the budget is #{AGENTS_CARD_BUDGET}. " \
                     "Remove a line, or turn one into a check."
  end

  # The control: a budget is also satisfied by an empty file.
  it "is a card rather than an empty file" do
    expect(card.lines.length).to be >= 40
    expect(headings.length).to be >= 4
  end

  it "is the whole of what CLAUDE.md says" do
    expect(claude).to eq(CLAUDE_MD),
                      "CLAUDE.md is not the import and the note this spec pins. Rules go in AGENTS.md; " \
                      "if the note itself changed, change CLAUDE_MD here with it."
  end

  it "does not say which release is being prepared, or on which branch" do
    claims = card.scan(AGENTS_CARD_STALE_CLAIM)
    expect(claims).to be_empty, "the card names a release or branch: #{claims.join(', ')}"
  end

  it "names no task file by number, beyond the two it sends a reader to" do
    expect(card).to include("highest-numbered")
    named = card.scan(AGENTS_CARD_TASK_FILE) - AGENTS_CARD_REFERENCE_TASKS
    expect(named).to be_empty,
                     "the card names #{named.join(', ')}; a pointer that has to be edited every " \
                     "release goes stale, so it tells the reader to list the directory"
  end

  it "has the section every document in its index says it stands behind" do
    asked = indexed_documents.reject { |path| path.match?(AGENTS_CARD_UNDECLARED) }
    expect(asked.length).to be >= 4, "the index names #{asked.inspect}; it used to name more"
    asked.each do |path|
      body = File.read(File.join(AGENTS_CARD_ROOT, path), encoding: "UTF-8").gsub(/\s+/, " ")
      named = body.scan(AGENTS_CARD_STANDS_BEHIND).flatten
      expect(named).not_to be_empty, "#{path} does not say which AGENTS.md section it stands behind"
      missing = named - headings
      expect(missing).to be_empty, "#{path} stands behind AGENTS.md sections that do not exist: #{missing.inspect}"
    end
  end

  it "would catch each thing the third review round got past the first version" do
    claim = AGENTS_CARD_STALE_CLAIM
    expect("Work for the next one lives on `release/0.3.2`.".scan(claim)).not_to be_empty
    expect("The release in preparation is 0.3.2, on branch release/0.3.2.".scan(claim)).not_to be_empty
    expect("Work continues on `release/0.4`.".scan(claim)).not_to be_empty
    expect("The current branch is `worktree-057-rulebook-cleanup`.".scan(claim)).not_to be_empty
    expect("The release being prepared is **0.3.2**.".scan(claim)).not_to be_empty
    expect("The branch is `release/<version>`.".scan(claim)).to be_empty
    expect("merged into `main` by pull request".scan(claim)).to be_empty

    pointer = AGENTS_CARD_TASK_FILE
    expect("- Read section 0. The current file is `046-0.2.14-making-the-record-true.md`.".scan(pointer)).not_to be_empty
    expect("under `.claude/`; the work is `058-the-rulebook-cleaned.md`.".scan(pointer)).not_to be_empty
    expect("the highest-numbered `docs/design/tasks/NNN-*.md`".scan(pointer)).to be_empty

    gone = "`AGENTS.md`'s \"Sections nobody wrote\" lines point here."
    expect(gone.scan(AGENTS_CARD_STANDS_BEHIND).flatten).to eq(["Sections nobody wrote"])
  end
end
