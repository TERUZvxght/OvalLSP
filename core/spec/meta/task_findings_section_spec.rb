# frozen_string_literal: true

require_relative "../../../scripts/repo_files"

# `024.171`. `024.139` closed by naming a countermeasure — "so a check
# can assert that `docs/design/tasks/*.md` other than 024 carry no
# findings section of their own" — and the work it pointed at moved
# `DeferredFindings` into `scripts/` and did nothing about this. **A
# third task file growing its own findings section was still invisible**,
# which is what `024.109` cost: findings that live where nothing reads
# them are findings nobody acts on.
#
# The register is the one place. What this asserts is not that such a
# section cannot exist — 008.5 and 008.6 keep theirs, and their content
# is now a pointer, which is the right outcome — but that one carrying
# *items* has to say where findings actually go.
#
# **Top-level sections only.** `023.8` has a fourth-level heading naming
# one known gap inside a numbered list; that is a detail of the task, not
# a findings section, and sweeping it in would make this check fire on
# ordinary writing. The distinction is the level, and it is the one thing
# here a later reader might reasonably want to change.
RSpec.describe "a findings section in a task document" do
  TASK_FINDINGS_REPO_ROOT = File.expand_path("../../..", __dir__)

  # The shapes this project has actually grown, rather than a guess at
  # what one might be called. Two are the sections `024.139` was about;
  # the others are what a new one would plausibly be titled.
  FINDINGS_HEADINGS = /\A##\s+.*(残課題|残っているKnown Issue|Known Issue|未解決の指摘|Open findings)/
  POINTER = "未処理の指摘はこの文書ではなく `024` に書く"

  def task_documents
    RepoFiles.list(TASK_FINDINGS_REPO_ROOT)
             .select { |path| path.start_with?("docs/design/tasks/") && path.end_with?(".md") }
             .reject { |path| path.include?("024-deferred-review-findings") }
  end

  it "says where findings go, in every task document that has one" do
    offenders = task_documents.filter_map do |path|
      body = File.read(File.join(TASK_FINDINGS_REPO_ROOT, path), encoding: "UTF-8")
      sections = body.split(/^(?=## )/).select { |section| section.match?(FINDINGS_HEADINGS) }
      next if sections.empty?
      next if sections.all? { |section| section.include?(POINTER) }

      path
    end

    expect(offenders).to be_empty,
                         "task documents with a findings section that does not say findings go in `024`: " \
                         "#{offenders.join(', ')}. The register is the one place a finding is read from " \
                         "(024.109, 024.171)."
  end

  # **The control.** Without it the example above passes on a tree where
  # `RepoFiles.list` returns nothing, a rename moved the task directory,
  # or the heading pattern stopped matching — each of which reads exactly
  # like a clean result.
  it "found the sections it is checking" do
    matched = task_documents.count do |path|
      File.read(File.join(TASK_FINDINGS_REPO_ROOT, path), encoding: "UTF-8")
          .split(/^(?=## )/).any? { |section| section.match?(FINDINGS_HEADINGS) }
    end

    expect(task_documents.length).to be > 20
    expect(matched).to be >= 2, "the two sections `024.139` is about are 008.5's and 008.6's; found #{matched}"
  end
end
