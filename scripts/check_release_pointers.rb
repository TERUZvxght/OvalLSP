#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"

# Every release branch is named by a task document, so a session that can
# only see `main` can still find the work.
#
# **What this cost.** 0.2.3 was prepared twice, in parallel. The task
# document on `main` said the work "continues in" a file that existed only
# on a branch nothing on `main` named, so a session starting from `main`
# found a pointer to nothing and rebuilt the release from scratch. Days of
# duplicated work, recorded in `docs/design/tasks/028-0.2.3-review-loop.md`.
#
# `CLAUDE.md`'s "Where a release's work lives" says the task file on `main`
# that names the release also names its branch, and
# `docs/DOCUMENTATION_MAP.md` carries the row. Nothing enforced either: the
# row's "Checked by" column is one of eight that reads as nothing at all.
# Measured when this was written, `release/0.3.1` existed on the remote and
# no document in the tree named it -- the same shape, one release later.
#
# **It reports rather than assumes when it cannot see.** A tarball, a
# `git archive` extraction and a single-branch clone all legitimately have
# no release branches, and calling that a pass without saying so would be
# the shape `scripts/check_pinned_mutations.rb` reported on its first run:
# a checker that cannot see what it checks prints what a working one prints.
#
# Usage: ruby scripts/check_release_pointers.rb
# Exits non-zero when a branch git can see is named by no task document.

module ReleasePointers
  ROOT = File.expand_path("..", __dir__)
  TASKS_DIR = "docs/design/tasks"
  # `release/<major>.<minor>.<patch>` and nothing else. The older prefixes
  # (`feat/`, `fix/`) are deliberately not matched: the convention that
  # retired them is dated 2026-09-01, and a branch still carrying one is
  # from before this rule and is not evidence of anything now.
  RELEASE_BRANCH = %r{\Arelease/\d+\.\d+\.\d+\z}

  module_function

  # Local branches and remote-tracking branches, short names, deduplicated.
  def visible_branches(root = ROOT)
    out = `cd #{root.inspect} && git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null`
    return [] unless $?.success?

    out.lines.map(&:strip)
       .map { |ref| ref.sub(%r{\A[^/]+/(?=release/)}, "") }
       .select { |ref| ref.match?(RELEASE_BRANCH) }
       .uniq.sort
  end

  def task_documents(root = ROOT)
    Dir.glob(File.join(root, TASKS_DIR, "*.md")).sort.to_h { |p| [p.sub("#{root}/", ""), File.read(p, encoding: "UTF-8")] }
  end

  # The whole verdict, as data, so the decision is testable without a repo.
  def problems(branches:, documents:)
    branches.reject { |branch| documents.any? { |_path, text| text.include?(branch) } }
            .map do |branch|
      "`#{branch}` exists and no document in #{TASKS_DIR} names it. A session that can see only `main` " \
        "cannot find that work -- open the release's record and name the branch in it."
    end
  end

  def run(root = ROOT)
    branches = visible_branches(root)
    documents = task_documents(root)

    if documents.empty?
      warn "check-release-pointers: #{TASKS_DIR} holds no documents, so this check cannot see what it checks"
      return 1
    end

    # The census before the verdict, always: the count is what tells a
    # clean run from a blind one.
    puts "check-release-pointers: #{branches.length} release branch(es) visible, " \
         "#{documents.length} task document(s) read."
    if branches.empty?
      puts "check-release-pointers: none visible -- a tarball, a `git archive` extraction or a " \
           "single-branch clone has none, and nothing here is asserted about them."
      return 0
    end

    found = problems(branches: branches, documents: documents)
    if found.empty?
      puts "check-release-pointers: every visible release branch is named by a task document."
      0
    else
      warn "check-release-pointers: #{found.length} problem(s):"
      found.each { |p| warn "  - #{p}" }
      1
    end
  end
end

exit ReleasePointers.run if $PROGRAM_NAME == __FILE__
