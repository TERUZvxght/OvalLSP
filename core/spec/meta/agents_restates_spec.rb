# frozen_string_literal: true

# 024.150: `AGENTS.md` is a condensed restatement of `CLAUDE.md`'s rules,
# and nothing relates the two. Measured in 0.2.16, it is not a pure
# restatement -- three rules and the whole opening section have no
# counterpart -- so it stays, and what it needs is a relationship.
#
# The cheap inferred relationship was tried and rejected there: requiring
# each bullet that cites `CLAUDE.md` to share a distinctive token with it
# gave three false positives in eleven, because two bullets cite the file
# as something to *read* rather than as the rule's home and one is a
# genuine paraphrase carrying no identifier. A check with that error rate
# is one somebody switches off (`024.192`).
#
# So the relationship is **declared, not inferred**. A bullet that
# restates a rule names the section it restates, and this check holds
# `CLAUDE.md` to still having it. The two "read this file" bullets carry
# no marker and are not asked about, which is what removes the false
# positives -- the paraphrase says what it paraphrases instead of a
# scanner guessing.
RSpec.describe "AGENTS.md declares what it restates" do
  root = File.expand_path("../../..", __dir__)
  agents = File.read(File.join(root, "AGENTS.md"), encoding: "UTF-8")
  claude = File.read(File.join(root, "CLAUDE.md"), encoding: "UTF-8")

  markers = agents.scan(/<!--\s*restates:\s*(.+?)\s*-->/).flatten
  headings = claude.lines.grep(/^## /).map { |l| l.sub(/^## /, "").strip }

  # Without this, deleting every marker makes the file pass -- which is
  # the failure mode of any check whose subject is its own input.
  it "carries a marker for each rule it restates" do
    expect(markers.length).to be >= 10,
                              "AGENTS.md declares #{markers.length} restated sections; " \
                              "the rule bullets that restate CLAUDE.md must each name their section"
  end

  it "names only sections CLAUDE.md still has" do
    missing = markers.uniq.reject { |m| headings.include?(m) }
    expect(missing).to be_empty,
                       "AGENTS.md restates sections CLAUDE.md no longer has: #{missing.inspect}\n" \
                       "CLAUDE.md's headings are:\n  #{headings.join("\n  ")}"
  end

  # A marker is a claim about the bullet it sits in. Two bullets claiming
  # the same section is fine (the measurement section carries three
  # rules); a marker outside a bullet is not, because then nothing
  # restates it.
  it "puts every marker inside a bullet" do
    stray = agents.lines.select { |l| l.include?("<!-- restates:") && !l.start_with?("  ", "- ") }
    expect(stray).to be_empty, "markers outside a bullet: #{stray.inspect}"
  end
end
