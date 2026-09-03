# frozen_string_literal: true

require_relative "utf8"

# The files that are, **or are about to be**, part of this repository.
#
# `024.147`. Every check in this tree enumerated its input with `git
# ls-files`, which lists *tracked* files only — so a file you have just
# written is invisible to all of them until `git add`. And
# `scripts/preflight.rb` runs before the commit, which is precisely the
# window in which the new file does not exist as far as any check is
# concerned.
#
# The consequence is not subtle once stated: **the suite can be green
# before a commit and red after it**, having examined different sets of
# files. 0.2.14 shipped exactly that — `release_gate_spec.rb`'s planted
# example passed while the file was untracked and failed the moment it
# was committed, and the commit message says "2,374 examples, 0
# failures" because that is what the run reported.
#
# Demonstrated rather than argued: an untracked Markdown file carrying a
# duplicated heading *and* a citation of a document that has never
# existed passes both `duplicate_headings_spec` and `check_doc_links`,
# each reporting the tree clean.
#
# `--others --exclude-standard` adds files git does not yet track and
# would not ignore. A file that is genuinely ignored (`.gitignore`) is
# still excluded, so build output and local scratch stay out.
module RepoFiles
  NUL = "\0"

  # **The variables that decide which repository git operates on, unset.**
  #
  # `024.157`. Git exports `GIT_DIR` and `GIT_INDEX_FILE` to every hook,
  # and in a *linked worktree* both are absolute paths to that worktree's
  # gitdir and index. `chdir:` and `-C` change the working directory;
  # neither overrides `GIT_DIR`. So a spec that builds a throwaway
  # repository in `Dir.mktmpdir` and runs `git add -A && git commit` in it
  # wrote the throwaway tree's contents into the *real* worktree's index
  # and landed a commit on the branch that worktree had checked out -- a
  # commit deleting every tracked file the throwaway repository did not
  # have. Measured, not argued: under those two variables
  # `untracked_visibility_spec.rb` reported "3 examples, 0 failures" and
  # left a commit on the other repository's branch removing its sources.
  #
  # Three things made it worse than a red suite. `list` unions `ls-files`
  # with `--others`, and `--others` enumerates the filesystem, so it came
  # back with nearly the right answer from the wrong repository and every
  # assertion still passed. `check_home_paths.rb` enumerates through here
  # and runs `git log --all`, so the public-repository privacy guard read
  # whichever repository `GIT_DIR` named and reported clean about it. And
  # the vector is documented: `preflight.rb --install` installs exactly
  # such a hook and `docs/DEVELOPMENT.md` tells contributors to run it.
  #
  # **Contained where the spawn happens, not at each caller** -- the shape
  # `docs/CODE_DISCIPLINE.md`'s "Code that deletes" section prescribes, for the
  # same reason: every call site here computed its own target and was
  # individually plausible, and safety was an emergent property of all of
  # them being right at once, which is not a property. Every `git` in
  # `scripts/` and `core/spec/` goes through `spawn_args` or `run`, and
  # `untracked_visibility_spec.rb` fails on one that does not.
  LOCATION_ENV = %w[
    GIT_DIR
    GIT_INDEX_FILE
    GIT_WORK_TREE
    GIT_OBJECT_DIRECTORY
    GIT_ALTERNATE_OBJECT_DIRECTORIES
    GIT_COMMON_DIR
    GIT_NAMESPACE
  ].freeze

  module_function

  # An env hash that unsets every one of them. `IO.popen`/`system`/`Open3`
  # all treat a nil value as "remove this from the child's environment".
  def clean_env
    LOCATION_ENV.to_h { |name| [name, nil] }
  end

  # The leading arguments for any git subprocess: the scrubbed env, then
  # the command. `system(*RepoFiles.spawn_args("status"), chdir: root)`.
  def spawn_args(*args)
    [clean_env, "git", *args]
  end

  # `pathspec` is passed to git unchanged, so callers keep their globs.
  def list(root, *pathspec)
    (tracked(root, *pathspec) +
     git(root, %W[ls-files -z --others --exclude-standard] + pathspec)).uniq.sort
  end

  # Committed content only, and **deliberately the opposite of `list`**.
  #
  # `024.194`. The argument above is about the files a check *inspects*:
  # a file you have just written must not be invisible to the checks that
  # judge it. It is not an argument about the files a check treats as
  # *evidence that something happens*. `release_gate_spec` asks "does
  # anything invoke this script?", and answering yes on the strength of an
  # uncommitted scratch file means the check passed for a reason that
  # exists in no commit — so a gate reads as wired on this machine and
  # nowhere else.
  #
  # The cost is the mirror image of `024.147`'s and is the right way
  # round here: a genuinely new caller reports its gate unwired until
  # `git add`. "Nothing runs this" is the answer that must not be given
  # on evidence no commit contains.
  def tracked(root, *pathspec)
    git(root, %W[ls-files -z] + pathspec).uniq.sort
  end

  def git(root, args)
    out = capture(root, args)
    raise "git #{args.join(' ')} failed in #{root}: #{out}" unless $?.success?

    out.split(NUL).reject(&:empty?)
  end

  # Runs git in `root` and returns its combined output; `$?` carries the
  # status. Every caller that used a backtick or a bare `IO.popen(["git",
  # ...])` reads this instead.
  def capture(root, args)
    IO.popen(clean_env, ["git", *args], chdir: root, err: %i[child out], &:read)
  end

  # `system`, for a caller that only wants the status.
  def run(root, *args, **opts)
    system(*spawn_args(*args), chdir: root, **opts)
  end
end
