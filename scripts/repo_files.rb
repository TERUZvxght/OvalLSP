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

  module_function

  # `pathspec` is passed to git unchanged, so callers keep their globs.
  def list(root, *pathspec)
    (git(root, %W[ls-files -z] + pathspec) +
     git(root, %W[ls-files -z --others --exclude-standard] + pathspec)).uniq.sort
  end

  def git(root, args)
    out = IO.popen(["git", *args], chdir: root, err: %i[child out], &:read)
    raise "git #{args.join(' ')} failed in #{root}: #{out}" unless $?.success?

    out.split(NUL).reject(&:empty?)
  end
end
