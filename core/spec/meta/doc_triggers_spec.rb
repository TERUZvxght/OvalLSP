# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "../../../scripts/check_doc_triggers"

# **`docs/DOCUMENTATION_MAP.md`'s trigger table, for the rows a machine
# can read.**
#
# The table says what else must change when a given file does, and its
# "Checked by" column reads `—` on several rows — which means the rule is
# enforced by whoever remembers to open the document. That is the
# arrangement the map's own header says kept failing.
#
# Only the rows whose left column is a *set of files* become data. A
# revert, or a round finding the same place the previous one did, is a
# judgement no scanner makes and stays prose. And only the pairs nothing
# already checks: a rule here that restated `check_protocol_doc.rb` or
# `swallowed_failures_spec` would be a second, weaker implementation of a
# check that exists.
RSpec.describe "the documentation trigger table as data" do
  DOC_TRIGGERS_REPO = File.expand_path("../../..", __dir__)

  let(:root) { example_tmpdir("doc-triggers") }

  # One planted rule, so the examples say what they mean whatever the
  # real table holds that day — the shape `024.126`'s sibling finding in
  # this task was about, where an example rested on a document's current
  # contents.
  #
  # **The paths are assembled, never spelled.** `check_doc_links.rb`
  # reads every tracked file for citations and a spec is tracked content,
  # so a fixture path written the way a real one is written becomes a
  # dangling citation in the file that tests the trigger table. It did,
  # on the first run of this file — `024.126`, again.
  def companion = unspellable("docs", "companion-that-does-not-exist.md")

  def trigger = unspellable("src", "trigger.ts")

  def unrelated = unspellable("docs", "unrelated-and-does-not-exist.md")

  let(:rules) do
    [{ "id" => "planted", "when" => [trigger], "then" => [companion],
       "note" => "the planted rule's own sentence" }]
  end

  def write(relative, content)
    FileUtils.mkdir_p(File.join(root, File.dirname(relative)))
    File.write(File.join(root, relative), content)
  end

  # A repository with a base commit to diff against. The base is a SHA
  # rather than `origin/main`, because a throwaway repository has no
  # remote and pinning this against the real one is what `024.157` is.
  def base_commit
    write(trigger, "one\n")
    write(companion, "one\n")
    throwaway_repo(root, "base")
    RepoFiles.capture(root, %w[rev-parse HEAD]).strip
  end

  def complaints(base) = DocTriggers.complaints(root, rules, base)

  it "reports a trigger file changed with no companion changed" do
    base = base_commit
    write(trigger, "two\n")
    commit_throwaway(root, "the trigger alone")

    expect(complaints(base)).to include(a_string_matching(/planted rule's own sentence/))
  end

  # **The control.** Every example that asserts a refusal needs the case
  # that must still go through, or a checker that complained about
  # everything would satisfy it.
  it "says nothing when the companion changed too" do
    base = base_commit
    write(trigger, "two\n")
    write(companion, "two\n")
    commit_throwaway(root, "both")

    expect(complaints(base)).to be_empty
  end

  it "says nothing when the trigger did not change" do
    base = base_commit
    write(unrelated, "one\n")
    commit_throwaway(root, "something else")

    expect(complaints(base)).to be_empty
  end

  # `preflight` runs before the commit, so the change it must judge is
  # usually not committed yet. A check that read only the committed range
  # would be blind in exactly the window it runs in (`024.147`).
  it "sees a trigger file changed and not yet committed" do
    base = base_commit
    write(trigger, "two\n")

    expect(complaints(base)).not_to be_empty
  end

  it "sees a companion changed and not yet committed" do
    base = base_commit
    write(trigger, "two\n")
    commit_throwaway(root, "the trigger alone")
    write(companion, "two\n")

    expect(complaints(base)).to be_empty
  end

  # A checker that cannot see the thing it checks reports exactly what a
  # working one reports when nothing is wrong (`024.148`). A base ref
  # that does not resolve is that, so it says so instead.
  it "refuses a base it cannot resolve rather than reporting the tree clean" do
    base_commit

    expect { DocTriggers.complaints(root, rules, "no-such-ref") }.to raise_error(DocTriggers::Unreadable)
  end

  describe "the rules this repository actually keeps" do
    let(:real) { DocTriggers.rules(DOC_TRIGGERS_REPO) }

    it "reads a table with rules in it" do
      expect(real).not_to be_empty
      expect(real.map { |rule| rule["id"] }.uniq.length).to eq(real.length)
    end

    it "gives every rule a when, a then and a note that says why" do
      incomplete = real.reject do |rule|
        rule["when"].is_a?(Array) && rule["when"].any? &&
          rule["then"].is_a?(Array) && rule["then"].any? &&
          rule["note"].to_s.length > 20
      end

      expect(incomplete.map { |rule| rule["id"] }).to be_empty
    end

    # A glob matching nothing is a rule that can never fire, which reads
    # exactly like a rule that is being satisfied.
    it "names patterns that match something in this tree" do
      tracked = RepoFiles.list(DOC_TRIGGERS_REPO)
      barren = real.flat_map do |rule|
        (rule["when"] + rule["then"]).reject { |glob| tracked.any? { |path| DocTriggers.matches?(glob, path) } }
                                     .map { |glob| "#{rule['id']}: #{glob}" }
      end

      expect(barren).to be_empty
    end

    # The table is the prose; this is the half of it a machine reads. A
    # rule whose id no row names is a rule nobody can find from the
    # document they were told to walk.
    it "names a row of the trigger table for every rule" do
      map = File.read(File.join(DOC_TRIGGERS_REPO, "docs", "DOCUMENTATION_MAP.md"), encoding: "UTF-8")
      unnamed = real.map { |rule| rule["id"] }.reject { |id| map.include?("`#{id}`") }

      expect(unnamed).to be_empty,
                         "rules no row of docs/DOCUMENTATION_MAP.md names: #{unnamed.join(', ')}"
    end
  end
end
