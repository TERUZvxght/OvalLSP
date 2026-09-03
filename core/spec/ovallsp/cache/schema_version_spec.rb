# frozen_string_literal: true

# `Cache::Key::SCHEMA_VERSION`'s own doc says to bump it "whenever a
# FileSummary-reachable shape changes in a way an old cached entry
# couldn't safely be `Marshal.load`ed back as (a renamed/removed Data
# field ...)". 0.2.6 added `open_surface_owners` to `FileSummary` and did
# not bump it; a reviewer caught that by dumping a 0.2.5-shaped summary
# and loading it here — `TypeError: struct size differs`. `Store#load`
# rescues `StandardError`, so the consequence is not a crash but a silent
# whole-cache miss against a directory that then lingers.
#
# A golden pair rather than a note in a review checklist, because that
# arrangement is what failed: adding a field is a one-line edit nobody
# reads this file during. Changing either half now fails until both are
# considered together.
#
# **The pair compared `FileSummary.members` alone until 0.2.17, and that
# is not what the constant's doc says.** A field added one hop down —
# to the Data class held *inside* one of those lists — is refused by
# `Marshal.load` in exactly the same way and moved nothing here. It
# happened: `ReferenceCandidate` gained a member and this example stayed
# green. So the second half is now every Data shape a `FileSummary` can
# hold, and the pair fails on a change to any of them.
#
# The list of classes is written out by hand, and that is the remaining
# gap worth naming: a *new* Data class that becomes reachable from a
# FileSummary without being added below is invisible here, the same way
# the nested ones were. Adding one is the moment to add its row.
RSpec.describe "the cache schema version and the shape it protects" do
  # Everything a `FileSummary` can hold, transitively: its own members,
  # the Data classes in its lists, and the Data classes inside those.
  # `Cref` and `Reference` are deliberately absent — neither is reachable
  # from a summary, so neither can make a cached entry unloadable, and
  # dragging them in would demand a cache bump (which throws away every
  # user's cache) for a change that cannot affect one.
  def reachable_shapes
    [
      Ovallsp::Index::FileSummary, Ovallsp::Index::Declaration, Ovallsp::Index::SymbolId,
      Ovallsp::Index::Parameter, Ovallsp::Index::AncestorFact, Ovallsp::Index::AliasFact,
      Ovallsp::Index::ReferenceCandidate, Ovallsp::Index::GeneratedMethodFact
    ].to_h { |klass| [klass.name.split("::").last.to_sym, klass.members] }
  end

  it "moves whenever a shape a FileSummary can hold does" do
    expect([Ovallsp::Cache::Key::SCHEMA_VERSION, reachable_shapes]).to eq(
      [7,
       { FileSummary: %i[uri content_hash document_version declarations diagnostics source read_sequence
                         ancestor_facts alias_facts reference_candidates generated_method_facts
                         open_surface_owners module_function_names buffer_id
                         pattern_bound_names],
         Declaration: %i[symbol_id location visibility parameters origin body_source name_location],
         SymbolId: %i[kind owner name discriminator],
         Parameter: %i[name kind default_source],
         AncestorFact: %i[owner relation target location nesting],
         AliasFact: %i[owner new_name old_name singleton location visibility],
         ReferenceCandidate: %i[kind name location scope_id owner singleton receiver lexical_nesting arguments
                                implicit_hash_value write],
         GeneratedMethodFact: %i[owner name kind parameters return_type source_location origin confidence
                                 metadata] }]
    )
  end

  # Why the pair is worth anything, and why the gap it had was not
  # cosmetic: a payload written under the previous shape does not come
  # back with the new field defaulted, it raises — and `Store#load`
  # rescues that into a whole-cache miss nobody is told about. The
  # experiment is run on a stand-in rather than on a real 0.2.16 dump,
  # because the tree holds no such blob and shipping one would mean
  # regenerating a fixture every time a member moves. Ruby's answer is
  # what is being asserted, not this project's.
  it "refuses a Marshal payload written under a shape with one member fewer" do
    stub_const("SchemaShapeUnderTest", Data.define(:kind, :name))
    blob = Marshal.dump(SchemaShapeUnderTest.new(kind: :local_variable, name: "n"))
    stub_const("SchemaShapeUnderTest", Data.define(:kind, :name, :implicit_hash_value))

    expect { Marshal.load(blob) }.to raise_error(TypeError, /struct size differs/)
  end
end
