# frozen_string_literal: true

# `Cache::Key::SCHEMA_VERSION`'s own doc says to bump it "whenever a
# FileSummary-reachable shape changes in a way an old cached entry
# couldn't safely be `Marshal.load`ed back as (a renamed/removed Data
# field ...)". 0.2.6 added `open_surface_owners` to `FileSummary` and did
# not bump it; a reviewer caught that by dumping a 0.2.5-shaped summary
# and loading it here — `TypeError: struct size differs`. `Store#load`
# rescues `StandardError`, so the consequence is not a crash but a silent
# whole-cache miss against a directory that then lingers until pruned.
#
# A golden pair rather than a note in a review checklist, because that
# arrangement is what failed: adding a field is a one-line edit nobody
# reads this file during. Changing either half now fails until both are
# considered together.
RSpec.describe "the cache schema version and the shape it protects" do
  it "moves whenever FileSummary's members do" do
    expect([Ovallsp::Cache::Key::SCHEMA_VERSION, Ovallsp::Index::FileSummary.members]).to eq(
      [2, %i[uri content_hash document_version declarations diagnostics source read_sequence ancestor_facts
             alias_facts reference_candidates generated_method_facts open_surface_owners]]
    )
  end
end
