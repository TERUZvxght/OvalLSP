# frozen_string_literal: true

# `046`'s C2. `AGENTS.md`'s "work in progress lives in
# `docs/design/tasks/`" bullet used to name the current task file by
# number, and went stale three times -- twice pointing at a file the
# branch it was read on did not contain, once created while fixing the
# same line.
#
# The plan for this check was to verify the number is the highest on
# HEAD. 0.2.14 deleted the number instead: a pointer that must be edited
# every release will be wrong most of the time, and "list the directory"
# cannot go stale at all. So what is left to guard is that the number
# does not come back -- the bullet reacquiring one is the regression, and
# it would look like an improvement to whoever wrote it.
#
# Fenced to that bullet deliberately. `AGENTS.md` cites `024.36` and
# other numbered records elsewhere, and those are references to a
# document rather than a pointer at the working head.
RSpec.describe "AGENTS.md's work-in-progress pointer" do
  AGENTS_MD = File.expand_path("../../../AGENTS.md", __dir__)

  # One pattern, read by the assertion and by the example that proves the
  # assertion fires. Written twice, they can drift, and the drift shows
  # up as the planted example passing while the real one has stopped
  # matching anything -- which is this release's own subject.
  AGENTS_TASK_FILE = %r{`?(\d{3}(?:\.\d+)?-[a-z0-9.-]+\.md)`?}

  # The bullet, from its bold opener to the blank line before the next
  # top-level bullet. Its own italic postscript is part of it.
  def bullet
    text = File.read(AGENTS_MD, encoding: "UTF-8")
    start = text.index("- **Work in progress lives in")
    raise "the work-in-progress bullet is gone from AGENTS.md" if start.nil?

    finish = text.index("\n- ", start + 3) || text.length
    text[start...finish]
  end

  it "does not name a task file by number" do
    named = bullet.scan(AGENTS_TASK_FILE)

    expect(named).to be_empty,
                     "the bullet names #{named.flatten.join(", ")}. A pointer that has to be edited " \
                     "every release goes stale; it tells the reader to list the directory instead."
  end

  it "tells the reader how to find the file rather than which one it is" do
    expect(bullet).to include("highest-numbered")
    expect(bullet).to match(/list the directory/)
  end

  # Without this, both examples above would pass if the bullet were
  # deleted outright -- `bullet` raises on that, but a regex over a
  # shorter string is not evidence the string still says anything.
  it "would catch the number coming back" do
    planted = "- **Work in progress lives in `docs/design/tasks/`.** " \
              "The current file is `046-0.2.14-making-the-record-true.md`.\n"

    expect(planted.scan(AGENTS_TASK_FILE)).not_to be_empty
  end
end
