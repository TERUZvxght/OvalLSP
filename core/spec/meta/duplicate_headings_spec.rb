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
# guards one file. This is the same question asked of every tracked
# Markdown document, and it is the check that would have caught both.
#
# Two things it must get right to be worth having:
#
# - **Fenced blocks are not headings.** `10-ai-execution-guide.md` quotes
#   a task template and a report template, both of which contain `##
#   Tests`. A line-based scan reports that file and the honest response
#   would be an exemption, which is `024.126`'s trap.
# - **It must fire on the real thing.** The example below plants the
#   actual defect -- a document's own body appended to itself.
RSpec.describe "tracked Markdown documents" do
  DUP_HEADINGS_ROOT = File.expand_path("../../..", __dir__)

  # Headings outside fenced code blocks. Both ``` and ~~~ open a fence,
  # and a fence closes on the same marker -- so a ``` inside a ~~~ block
  # is content, which is how this file's own examples stay quotable.
  def self.headings_in(text)
    fence = nil
    text.each_line.filter_map do |line|
      marker = line[/\A\s*(`{3,}|~{3,})/, 1]
      if marker
        if fence.nil? then fence = marker[0]
        elsif marker[0] == fence then fence = nil
        end
        next
      end
      next if fence

      line.rstrip if line.match?(/\A\#{1,2} \S/)
    end
  end

  def self.tracked_markdown
    RepoFiles.list(DUP_HEADINGS_ROOT, "*.md")
             .reject { |f| f.start_with?("core/vendor/", "vscode/node_modules/") }
  end

  it "never state one heading twice, which is what a pasted block looks like" do
    offenders = self.class.tracked_markdown.filter_map do |rel|
      path = File.join(DUP_HEADINGS_ROOT, rel)
      next unless File.file?(path)

      text = File.read(path, encoding: "UTF-8")
      next unless text.valid_encoding?

      repeated = self.class.headings_in(text).tally.select { |_, count| count > 1 }
      "#{rel}: #{repeated.map { |h, c| "#{h.inspect} x#{c}" }.join(", ")}" unless repeated.empty?
    end

    expect(offenders).to be_empty,
                         "documents stating a heading more than once:\n  #{offenders.join("\n  ")}\n" \
                         "A repeated heading is usually a block pasted rather than moved -- check the " \
                         "section is not in the file twice before renaming it."
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
end
