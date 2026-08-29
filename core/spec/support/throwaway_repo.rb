# frozen_string_literal: true

require_relative "../../../scripts/repo_files"

# One place that builds a git repository inside a temporary directory.
#
# `024.157`. Three meta specs each wrote their own `system("git", "-C",
# dir, ...)` sequence, and every one of them was individually plausible.
# What none of them mentioned is that `-C` sets the working directory and
# does **not** override `GIT_DIR`: git exports `GIT_DIR` and
# `GIT_INDEX_FILE` to every hook, absolute in a linked worktree, so under
# `preflight --install`'s pre-commit hook those sequences wrote a
# throwaway tree into the *real* repository's index and committed it --
# a commit deleting every tracked file the throwaway did not have, with
# the suite reporting zero failures the whole time.
#
# So the git invocation lives here, once, and goes through
# `RepoFiles`, which unsets the whole family of location variables at the
# spawn. That is the containment `CLAUDE.md`'s "a test that deletes
# things" section prescribes: not a guard at each call site, but one
# function no caller can aim elsewhere.
#
# `untracked_visibility_spec.rb` fails on a git spawn anywhere in
# `scripts/` or `core/spec/` that does not go through `RepoFiles`, so a
# fourth spec cannot quietly write its own sequence again.
module ThrowawayRepo
  THROWAWAY_IDENTITY = ["-c", "user.email=t@example.invalid", "-c", "user.name=t"].freeze

  # Initialises `root` as a repository. `root` must already exist --
  # `Dir.mktmpdir` with a block, per `CLAUDE.md`; nothing here ever takes
  # a fabricated absolute path.
  def init_throwaway_repo(root)
    raise ArgumentError, "#{root} does not exist" unless File.directory?(root)

    RepoFiles.run(root, "init", "-q", ".", out: File::NULL)
  end

  def commit_throwaway(root, message)
    RepoFiles.run(root, "add", "-A", out: File::NULL)
    RepoFiles.run(root, *THROWAWAY_IDENTITY, "commit", "-qm", message, out: File::NULL)
  end

  # Init plus a first commit, which is what every caller wanted.
  def throwaway_repo(root, message = "one")
    init_throwaway_repo(root)
    commit_throwaway(root, message)
  end
end

RSpec.configure { |config| config.include(ThrowawayRepo) }
