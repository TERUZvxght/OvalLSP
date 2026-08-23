# frozen_string_literal: true

# `024.42`. Signature help showed `push(...) -> Unknown` for `Array#push`,
# which RBS declares `-> self`, and `map() -> Array[U]` where `U` is the
# method's own type variable and means nothing to a reader.
#
# `TypeConverter` maps `self`, `void`, `untyped`, `top` and `bottom` all
# to `Types::UNKNOWN`. That is right for the **type model** — nothing
# downstream can act on any of them — and wrong for a **label**, which is
# prose for a human. The label was built from the converted type, so it
# inherited a decision made for a different purpose.
#
# What RBS actually declares, read rather than remembered:
#
#     Array#push : (*::Elem) -> self
#     Array#map  : [U] () { (::Elem) -> U } -> ::Array[U]
#
# So an `Overload` now carries `return_label` — the word RBS wrote —
# beside `return_type`, which stays the model's value. Two answers to two
# different questions, rather than one answer bent to serve both.
RSpec.describe "Ovallsp::Signatures return labels" do
  let(:environment) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }

  def overloads_for(owner, name)
    symbol = Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: owner, name: name, discriminator: nil)
    environment.method_signatures(symbol)&.overloads
  end

  it "keeps the word RBS wrote for a self-returning method" do
    overloads = overloads_for("::Array", :push)

    expect(overloads).not_to be_nil, "no RBS signature for Array#push -- the fixture, not the fix"
    expect(overloads.map(&:return_label)).to include("self")
  end

  # The distinguishing half: the *type* must not change. Downstream can
  # act on `Types::UNKNOWN` and cannot act on the string "self", so
  # bending the model to serve the label would be the trade this entry
  # says was made the wrong way round.
  it "leaves the model's type alone" do
    overloads = overloads_for("::Array", :push)

    expect(overloads.map(&:return_type)).to all(eq(Ovallsp::Types::UNKNOWN))
  end

  # The other side of the rule, and it was written the wrong way round
  # first. An ordinary type keeps the *converted* form, because that is
  # what every other reader in the tree renders; reaching for the
  # declaration here would make signature help the one place saying
  # `::String` where the rest says `String`. Three query-service
  # examples caught that, which is what the rule below now encodes:
  # the source's word is used only where the conversion lost something.
  it "keeps the converted form for an ordinary declared type" do
    overloads = overloads_for("::String", :upcase)

    expect(overloads).not_to be_nil
    expect(overloads.map(&:return_label)).to all(eq("String"))
  end

  # The user-visible half: signature help's own label. Everything above
  # is machinery until this line reads the way RBS wrote it.
  it "shows the declared word in the signature-help label" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    stack = build_analysis_stack(workspace_index: workspace_index,
                                 model_registry: Ovallsp::Models::ModelRegistry.new,
                                 signatures: environment)
    service = Ovallsp::Semantic::QueryService.new(
      local_inferencer: stack.local_inferencer, method_resolver: stack.method_resolver,
      model_registry: Ovallsp::Models::ModelRegistry.new, signatures: environment,
      workspace_index: workspace_index
    )
    overload = overloads_for("::Array", :push).first
    label = service.send(:rbs_signature, :push, overload)[:label]

    expect(label).to end_with("-> self")
    expect(label).not_to include("Unknown")
  end

  # An overload built without one — the RBI parser, a synthesised
  # untyped overload — falls back to the converted type, so the label is
  # never empty and no caller has to know which producer made it.
  it "falls back to the type when nothing recorded a label" do
    overload = Ovallsp::Signatures::Overload.new(return_type: Ovallsp::Types::Nominal.new(name: "Integer"))

    expect(overload.return_label).to eq("Integer")
  end
end
