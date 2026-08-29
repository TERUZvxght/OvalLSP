# frozen_string_literal: true

# Enumerated with `RepoFiles`, not `git ls-files` — `024.147`. A file you
# have just written is untracked until `git add`, and `preflight` runs
# before the commit, so a check that lists only tracked files is blind to
# exactly the file being worked on.
require_relative "../../../scripts/repo_files"

require "json"

# `046`'s C5. `docs/design/docs/07-vscode-extension.md` listed eight
# command ids and ten settings. **Zero of the commands and two of the
# settings were real.** Its status-bar section named seven strings, none
# of which is one of the five the extension produces. The document had
# been read and cited for a year.
#
# Nothing could have noticed. A design document restating a manifest is
# two copies of one fact with no relationship between them, which is the
# shape `CLAUDE.md`'s countermeasure rule is about -- so the relationship
# is made here, and the restatement is checked against the manifest that
# owns it.
#
# `DOCUMENTATION_MAP` gained the trigger row in the same change; this is
# the half of that row a machine can carry.
RSpec.describe "design documents that restate something the code owns" do
  DESIGN_DRIFT_ROOT = File.expand_path("../../..", __dir__)

  def self.read(rel) = File.read(File.join(DESIGN_DRIFT_ROOT, rel), encoding: "UTF-8")

  # The first fenced block of a numbered section, which is where each of
  # these documents puts its list.
  def block_in(document, heading)
    text = self.class.read(document)
    start = text.index(heading)
    raise "#{document} has no #{heading.inspect}" if start.nil?

    finish = text.index("\n## ", start + 3) || text.length
    section = text[start...finish]
    section[/```[a-z]*\n(.*?)```/m, 1] or raise "#{heading.inspect} in #{document} has no fenced block"
  end

  let(:manifest) { JSON.parse(self.class.read("vscode/package.json")) }

  it "07 §6 lists exactly the command ids package.json contributes" do
    documented = block_in("docs/design/docs/07-vscode-extension.md", "## 6. Commands").split.reject(&:empty?)
    real = manifest.fetch("contributes").fetch("commands").map { |c| c.fetch("command") }

    expect(documented.sort).to eq(real.sort)
  end

  it "07 §7 lists exactly the settings package.json contributes" do
    documented = block_in("docs/design/docs/07-vscode-extension.md", "## 7. Settings")
                 # `[A-Za-z0-9._-]`, not `[A-Za-z.]`: an id with a digit,
                 # hyphen or underscore would otherwise be dropped from the
                 # documented side and the comparison would pass while the
                 # document omitted it. None of today's five has one, which
                 # is exactly why nothing noticed.
                 .scan(/"(ovallsp\.[A-Za-z0-9._-]+)":/).flatten
    real = manifest.fetch("contributes").fetch("configuration").fetch("properties").keys

    expect(documented.sort).to eq(real.sort)
  end

  # Any `OvalLSP: ...` label in a string literal of any of TypeScript's
  # three delimiters, with or without a `$(icon)` prefix of any shape.
  #
  # Each of the three conditions the 0.2.14 version still imposed was a
  # shape ordinary TypeScript takes, and the consequence was
  # one-directional and unreported: the file could define a status string
  # the document does not list, with every example green. `024.209`.
  #
  #   * `'` and `"` only, so a **template literal was invisible** -- and
  #     `statusPresentation`'s own fallback is one, so the check was
  #     already blind to a string the shipped extension can produce;
  #   * an icon name of `[a-z~-]` only, so **one digit in a codicon name**
  #     made the whole literal unmatchable rather than partly matched,
  #     because the optional group failed and the label no longer abutted
  #     the opening quote.
  #
  # Both were measured against this tree before the pattern was widened:
  # appending either shape to `clientPresentation.ts` left all six
  # examples passing while §5 listed five strings and the file defined
  # six.
  DESIGN_DRIFT_STATUS = /["'`](\$\([^)]*\)\s*)?(OvalLSP: [^"'`]*)["'`]/

  it "07 §5 lists exactly the status-bar strings clientPresentation defines" do
    documented = block_in("docs/design/docs/07-vscode-extension.md", "## 5. Status Bar").lines.map(&:strip).reject(&:empty?)
    source = self.class.read("vscode/src/clientPresentation.ts")
    real = source.scan(DESIGN_DRIFT_STATUS)
                 .map { |icon, label| "#{icon}#{label}" }
                 .uniq

    expect(documented.sort).to eq(real.sort)
  end

  # And §5's claim is that `clientPresentation.ts` is the *only* place
  # the status bar's text comes from -- 唯一の定義, in its own words. The
  # example above cannot see that: it reads one file, so a status string
  # assigned anywhere else in `vscode/src` is simply outside it.
  #
  # Asserted structurally rather than by widening the scan to every `.ts`
  # file, which would be wrong: dozens of notification messages, log
  # lines and command titles begin `OvalLSP: ` and are not status-bar
  # strings at all, so a wider scan would compare §5 against a list it
  # has no business listing. What makes §5 true is that every assignment
  # to a status bar item's `text` takes `statusPresentation`'s value.
  it "assigns the status bar's text only from clientPresentation's own decision" do
    assignments = RepoFiles.list(DESIGN_DRIFT_ROOT, "vscode/src/*.ts")
                           .reject { |rel| rel.start_with?("vscode/src/test/") }
                           .flat_map do |rel|
      self.class.read(rel).each_line.with_index(1).filter_map do |line, number|
        "#{rel}:#{number}  #{line.strip}" if line.match?(/\.text\s*=/) && line.match?(/status/i)
      end
    end

    expect(assignments).not_to be_empty, "no status-bar text assignment was found at all"
    assignments.each do |site|
      expect(site).to match(/=\s*shown\.text|=\s*statusPresentation\(/),
                      "this assigns the status bar's text from something other than " \
                      "`statusPresentation`, so 07 §5's claim that clientPresentation.ts is the " \
                      "only definition is no longer true: #{site}"
    end
  end

  it "07 §3 lists exactly the activation events package.json declares" do
    documented = block_in("docs/design/docs/07-vscode-extension.md", "## 3. Activation")
    expect(JSON.parse(documented).fetch("activationEvents").sort).to eq(manifest.fetch("activationEvents").sort)
  end

  # Each example above compares two lists, and would pass on two empty
  # ones -- which is what a renamed heading or a reformatted block
  # produces. This asserts the extractors found something to compare.
  it "extracts a non-empty list from each place it reads" do
    expect(block_in("docs/design/docs/07-vscode-extension.md", "## 6. Commands").split.length).to be >= 5
    expect(manifest.dig("contributes", "commands").length).to be >= 5
    expect(manifest.dig("contributes", "configuration", "properties").keys.length).to be >= 3
  end
end
