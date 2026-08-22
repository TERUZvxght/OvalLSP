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

  it "07 §5 lists exactly the status-bar strings clientPresentation defines" do
    documented = block_in("docs/design/docs/07-vscode-extension.md", "## 5. Status Bar").lines.map(&:strip).reject(&:empty?)
    source = self.class.read("vscode/src/clientPresentation.ts")
    # Any quoted `OvalLSP: ...` label, single or double quoted, with or
    # without a `$(icon)` prefix. The narrower form saw only the shape
    # today's five happen to take, so a new status string added in any
    # other shape would be invisible on the code side and the document
    # could omit it with this example green.
    real = source.scan(/["'](\$\([a-z~-]+\)\s*)?(OvalLSP: [^"']+)["']/)
                 .map { |icon, label| "#{icon}#{label}" }
                 .reject { |s| s.include?("\#{") }
                 .uniq

    expect(documented.sort).to eq(real.sort)
  end

  it "07 §3 lists exactly the activation events package.json declares" do
    documented = block_in("docs/design/docs/07-vscode-extension.md", "## 3. Activation")
    expect(JSON.parse(documented).fetch("activationEvents").sort).to eq(manifest.fetch("activationEvents").sort)
  end

  # The public SDK document is the plugin API's source of truth (`06`
  # points at it rather than restating it, after `06`'s own five
  # registration methods turned out to be fictional). Every method it
  # shows a plugin author calling must exist.
  it "plugin-sdk.md names only registration methods that exist" do
    named = self.class.read("docs/design/plugin-sdk.md").scan(/\b(register_[a-z_]+)\b/).flatten.uniq
    defined = RepoFiles.list(DESIGN_DRIFT_ROOT, "core/lib/ovallsp/plugins", "core/lib/ovallsp/plugins.rb")
                .flat_map { |rel| self.class.read(rel).scan(/^\s*def (register_[a-z_]+)/).flatten }
                .uniq

    expect(named).not_to be_empty
    expect(named - defined).to be_empty,
                              "plugin-sdk.md shows #{(named - defined).join(", ")}, which core/lib does not define"
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
