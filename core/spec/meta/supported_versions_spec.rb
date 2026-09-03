# frozen_string_literal: true

# **Which Ruby the product says it was tested against, in the four places
# that say it.**
#
# `docs/DOCUMENTATION_MAP.md`'s "Which Ruby, Rails or platform the product
# accepts" row lists thirteen documents and has nothing in its "Checked
# by" column — one of the six that still read as nothing. It went stale
# the way an unchecked row does: `SUPPORT_MATRIX` named three 3.4 patch
# releases and the Marketplace description named two, for a release,
# until 0.3.1 noticed and 0.3.2 wrote this.
#
# **The patch versions only.** The row's prose is written for four
# different audiences and demanding identical wording would buy a
# stricter check by making the prose worse — the same argument
# `check_site_links.rb` makes about the site's Japanese. What every one
# of them must agree about is the *fact*: which interpreters this was
# run under. That is a set, and a set can be compared.
RSpec.describe "the Ruby versions the documents name as tested" do
  # Methods, not constants: a constant inside a `describe` lands on
  # Object, and `spec_constants_spec.rb` fails on two files sharing one.
  def repo_root = File.expand_path("../../..", __dir__)

  # The four the trigger table names for this fact and that state it as a
  # version rather than as a range. `KNOWN_LIMITATIONS` and the site
  # pages are on the row too and speak in prose; they are not here
  # because there is nothing set-shaped in them to compare.
  def documents
    %w[docs/SUPPORT_MATRIX.md docs/SUPPORT_MATRIX.ja.md vscode/README.md vscode/README.ja.md]
  end

  # No trailing `\b`. Ruby's word boundary is Unicode-aware, so where a
  # version is followed immediately by Japanese text there is no
  # boundary after the last digit and the version is not matched at
  # all -- which this file reported as the Japanese README having
  # dropped a version it plainly has. The measurement was the thing
  # that was wrong, and reading the two lines side by side is what
  # showed it.
  def patch_versions(body) = body.scan(/(?<!\d)3\.4\.\d+/).uniq.sort

  def stated
    documents.to_h { |path| [path, patch_versions(File.read(File.join(repo_root, path), encoding: "UTF-8"))] }
  end

  it "names the same set in every document that names one" do
    sets = stated

    expect(sets.values.uniq.length).to eq(1),
                                       "the documents disagree about which 3.4.x this was run under:\n" +
                                       sets.map { |path, v| "  #{path}: #{v.join(', ')}" }.join("\n")
  end

  # The control. Without it this passes on four documents that mention no
  # version at all, which is what a careless edit would leave behind and
  # is indistinguishable from agreement.
  it "is comparing a set that is actually there" do
    sets = stated

    expect(sets.keys).to match_array(documents)
    sets.each { |path, versions| expect(versions.length).to be >= 2, "#{path} names #{versions.length} version(s)" }
  end

  # And the other direction: the versions named must be ones CI or the
  # release gate actually runs, so the documents cannot claim a run
  # nothing performs. `3.4` is the minor `ci.yml` names; the patch
  # releases are the maintainer's own machines, which is why this checks
  # the minor rather than each patch.
  it "names patch releases of a minor CI runs" do
    workflow = File.read(File.join(repo_root, ".github", "workflows", "ci.yml"), encoding: "UTF-8")
    minors = workflow[/ruby:\s*\[([^\]]*)\]/, 1].to_s.scan(/"([\d.]+)"/).flatten

    expect(minors).to include("3.4")
    stated.each do |path, versions|
      versions.each do |version|
        expect(minors).to include(version[/\A\d+\.\d+/]), "#{path} names #{version}, whose minor CI does not run"
      end
    end
  end
end
