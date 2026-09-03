# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "../../../scripts/review_round"

# `docs/REVIEW_LOOP.md`'s cadence is four rules and an ordering, and until
# this every one of them was a thing to remember: a round closes when a
# reviewer *that has not seen this change set*, using a method *the
# previous round did not use*, reports nothing.
#
# Two of those are mechanical and were checked by nobody.
#
# - **The method.** A closing round whose method repeats the previous
#   round's closes nothing, and the previous round's method is written in
#   the task document where nothing reads it.
# - **The fixed thing.** "A round reviews a fixed thing, and every
#   addition between rounds resets it" — so a round that ran while the
#   tree moved under it measured two trees and can conclude about
#   neither. Recorded as an ordering rule, observed by hand.
#
# What is asserted here is the pair of refusals and, for each, the case
# that must still go through. A gate that refuses everything satisfies
# every refusal example ever written.
RSpec.describe "scripts/review_round.rb" do
  # `example_tmpdir`, not the block-less `Dir.mktmpdir` that
  # `tmpdir_hygiene_spec` refuses.
  let(:root) { example_tmpdir("review-round") }
  let(:document) { File.join(root, "docs", "design", "tasks", "058-a-release.md") }

  before do
    FileUtils.mkdir_p(File.dirname(document))
    File.write(document, "# 058 — a release\n\n## Review\n\n#{round(3, 'diff')}")
    # `core/tmp/` is where the state file goes and is ignored in the real
    # repository, so the throwaway one ignores it too — otherwise
    # `start`'s own bookkeeping is what makes the next `git status`
    # dirty.
    File.write(File.join(root, ".gitignore"), "core/tmp/\n")
    throwaway_repo(root, "a release")
    stub_const("ReviewRound::ROOT", root)
  end

  def round(number, method) = "### Round #{number} — `#{method}`\n\n| # | Finding | Disposition |\n|---|---|---|\n"

  def body = File.read(document, encoding: "UTF-8")

  def commit_something(name)
    File.write(File.join(root, name), "one\n")
    commit_throwaway(root, name)
  end

  # **The script in its own process, loading its own requires.**
  #
  # Every other example here reaches `ReviewRound` through this file,
  # which requires `fileutils` at line 1 — so the spec supplied a
  # constant the script never asked for, and twelve green examples stood
  # over a `start` that raised `uninitialized constant
  # ReviewRound::FileUtils` the first time anyone ran it. A spec that
  # loads the subject's dependencies for it cannot see a missing one.
  #
  # The real file, not a copy: `OVALLSP_REVIEW_ROUND_ROOT` exists so the
  # tracked script can be aimed at a throwaway repository, which is what
  # makes running the actual thing possible here.
  def run_as_a_process(*args)
    script = File.expand_path("../../../scripts/review_round.rb", __dir__)
    Open3.capture3({ "OVALLSP_REVIEW_ROUND_ROOT" => root }, "ruby", script, *args, chdir: root)
  end

  describe "start" do
    it "opens the next round under the method it was given" do
      expect(ReviewRound.run(%w[start attack])).to eq(0)

      expect(body).to include(round(4, "attack"))
      expect(ReviewRound.state).to include("round" => 4, "method" => "attack")
    end

    it "opens one when run as its own process, with nothing loading its requires for it" do
      _, err, status = run_as_a_process("start", "attack")

      expect(status).to be_success, err
      expect(body).to include(round(4, "attack"))
    end

    # **The state is written first, and the heading only if it lands.**
    # The other order leaves the document claiming a round that was never
    # opened, and the next `start` then refuses that method as already
    # used — observed once, from a crash between the two writes.
    it "leaves the document untouched when the state cannot be recorded" do
      before_start = body
      allow(ReviewRound).to receive(:record).and_raise(Errno::EACCES)

      expect { ReviewRound.run(%w[start attack]) }.to raise_error(Errno::EACCES)
      expect(body).to eq(before_start)
    end

    # And the mirror: a state file saying a round is open, over a
    # document with no round in it, refuses every later `start` for a
    # round nobody can find.
    it "forgets the state when the heading cannot be written" do
      allow(ReviewRound).to receive(:append_round).and_raise(Errno::EACCES)

      expect { ReviewRound.run(%w[start attack]) }.to raise_error(Errno::EACCES)
      expect(ReviewRound.state).to be_nil
    end

    it "refuses the method the previous round used" do
      expect(ReviewRound.run(%w[start diff])).to eq(2)

      expect(body).not_to include("Round 4")
      expect(ReviewRound.state).to be_nil
    end

    it "refuses a method the loop does not define" do
      expect(ReviewRound.run(%w[start skim])).to eq(2)
      expect(ReviewRound.state).to be_nil
    end

    it "refuses a tree that is not clean, because a round reviews a fixed thing" do
      File.write(File.join(root, "docs", "design", "tasks", "058-a-release.md"), "# 058 — a release\n\nedited\n")

      expect(ReviewRound.run(%w[start attack])).to eq(2)
      expect(ReviewRound.state).to be_nil
    end

    it "refuses while a round is still open" do
      ReviewRound.run(%w[start attack])
      commit_throwaway(root, "the round's own heading")

      expect(ReviewRound.run(%w[start drive])).to eq(2)
      expect(ReviewRound.state).to include("method" => "attack")
    end

    it "opens round 1 in a document that records none" do
      File.write(document, "# 058 — a release\n\n## Review\n\nNothing yet.\n")
      commit_throwaway(root, "no rounds")

      expect(ReviewRound.run(%w[start diff])).to eq(0)
      expect(body).to include(round(1, "diff"))
    end
  end

  describe "close" do
    # **The refusal this exists for.** A fix committed while the round is
    # open moves the index, so the reviewer's report is about a tree that
    # no longer exists — which is the ordering `docs/REVIEW_LOOP.md`
    # states and nothing enforced.
    it "refuses a round whose tree moved under it" do
      ReviewRound.run(%w[start attack])
      commit_something("a-fix.rb")

      expect(ReviewRound.run(%w[close])).to eq(1)
    end

    # **Refusing is not the same as holding the round open.** A round the
    # index moved under is finished — it concluded about neither tree —
    # and the only thing left to do is start a fresh one. Keeping the
    # state file meant `start` then refused with "close it first" while
    # `close` refused with "it closes nothing", and the way out was
    # deleting a file in `core/tmp/` that nothing mentions.
    it "is over once the index moved, so the next round can start" do
      ReviewRound.run(%w[start attack])
      commit_something("a-fix.rb")
      ReviewRound.run(%w[close])

      expect(ReviewRound.state).to be_nil
      expect(ReviewRound.run(%w[start drive])).to eq(0)
      expect(body).to include(round(5, "drive"))
    end

    # **The control.** Without it every example here passes on a `close`
    # that refuses unconditionally.
    it "closes a round whose tree did not move" do
      ReviewRound.run(%w[start attack])

      expect(ReviewRound.run(%w[close])).to eq(0)
      expect(ReviewRound.state).to be_nil
    end

    it "says so when no round is open" do
      expect(ReviewRound.run(%w[close])).to eq(2)
    end
  end

  describe "status" do
    it "answers when nothing is open" do
      expect(ReviewRound.run(%w[status])).to eq(0)
    end

    it "reports the open round, and that the tree has moved" do
      ReviewRound.run(%w[start attack])
      commit_something("a-fix.rb")

      expect { ReviewRound.run(%w[status]) }.to output(/round 4.*attack/mi).to_stdout
      expect { ReviewRound.run(%w[status]) }.to output(/index has changed/i).to_stdout
    end

    # The other half of the same report, so "the index has changed" is
    # not what it says whatever happened.
    it "reports an open round over a tree that has not moved" do
      ReviewRound.run(%w[start attack])

      expect { ReviewRound.run(%w[status]) }.not_to output(/index has changed/i).to_stdout
    end
  end
end
