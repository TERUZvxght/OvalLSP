# frozen_string_literal: true

# `Cache::Store` removes directories from a user's disk, and for six days
# it removed the wrong ones: a spec handed `prune_generations` a fabricated
# `current: "/x"`, `File.dirname` turned that into `/`, and the sweep
# emptied `/Applications` of everything SIP did not protect. Every error
# was swallowed by the method under test, so the suite stayed green
# throughout. `CLAUDE.md` carries the full account.
#
# The fix was to make containment a property of *removal* rather than of
# each caller's arithmetic: one function, `remove_within`, performs every
# deletion and refuses a path outside the cache root. This guard is what
# stops that decaying back.
#
# It is needed because the containment cannot be pinned by ordinary
# examples. `prune_workspaces` enumerates `children_of(cache_root)`, so
# its paths are inside the root by construction and `remove_within` can
# never refuse one; reverse-applying those calls leaves the whole suite
# green. An unpinned behavioural line is a defect in this repository, and
# the answer here is not a fixture that cannot exist but a check one level
# up: *this class deletes in exactly one place.* A future change that
# enumerates something other than the root's own children -- which is
# exactly how the sweep escaped -- then arrives with the containment
# already applied instead of needing someone to remember it.
#
# Modelled on `tmpdir_hygiene_spec.rb`, and for its stated reason: a
# reintroduced direct `FileUtils` call leaves no failing test behind, only
# a destructive capability nobody is looking at.
RSpec.describe "cache removal containment" do
  let(:store_path) { File.expand_path("../../lib/ovallsp/cache/store.rb", __dir__) }
  let(:source) { File.read(store_path, encoding: "UTF-8") }

  # Only the calls that destroy. `mkdir_p` and friends are not this
  # guard's business. `rm_rf`/`rm_r` precede `rm` in the alternation so
  # the longer name wins rather than matching its prefix.
  let(:destructive) { /FileUtils\.(?:rm_rf|rm_r|rm|remove_entry|remove_dir|remove_file)\b/ }

  # Comments in this file discuss `FileUtils.remove_entry` by name --
  # including the one explaining why this guard exists -- so prose has to
  # be stripped before the source is searched, or the explanation of the
  # rule would violate it.
  def code_lines
    source.lines.each_with_index.map { |line, index| [index + 1, line.sub(/#.*/, "")] }
  end

  def destructive_lines = code_lines.select { |_number, code| code.match?(destructive) }

  # The single removal, located by its enclosing method rather than by
  # line number, so that editing anything above it does not need this
  # spec updated.
  def remove_within_range
    lines = source.lines
    start = lines.index { |line| line.match?(/^\s*def self\.remove_within\b/) }
    raise "Cache::Store.remove_within is gone -- containment has no home" if start.nil?

    finish = (start + 1...lines.length).find { |i| lines[i].match?(/^\s{6}end\s*$/) }
    ((start + 1)..(finish + 1))
  end

  it "removes a directory in exactly one place" do
    expect(destructive_lines.length).to eq(1),
                                        "expected one destructive FileUtils call in cache/store.rb, found " \
                                        "#{destructive_lines.length} at line(s) " \
                                        "#{destructive_lines.map(&:first).join(', ')}. Every removal must go " \
                                        "through .remove_within, which refuses a path outside the cache root."
  end

  it "puts that one place inside .remove_within, where the root is checked" do
    line = destructive_lines.first&.first

    expect(remove_within_range).to cover(line),
                                   "the destructive call at line #{line} is outside .remove_within, so it " \
                                   "deletes without checking the path is inside the cache root."
  end

  # The refusal itself, asserted directly: the guards above would both
  # pass if #remove_within's body were reduced to the bare removal.
  it "refuses a path outside the root, and the root itself" do
    Dir.mktmpdir do |root|
      outside = File.join(root, "..", "outside-#{File.basename(root)}")
      FileUtils.mkdir_p(outside)
      sibling = "#{root}-sibling"
      FileUtils.mkdir_p(sibling)

      Ovallsp::Cache::Store.remove_within(root, outside)
      Ovallsp::Cache::Store.remove_within(root, sibling)
      Ovallsp::Cache::Store.remove_within(root, root)

      expect([outside, sibling, root].reject { |dir| Dir.exist?(dir) }).to be_empty
    ensure
      FileUtils.remove_entry(sibling) if sibling && Dir.exist?(sibling)
      FileUtils.remove_entry(outside) if outside && Dir.exist?(outside)
    end
  end
end
