# frozen_string_literal: true

RSpec.describe Ovallsp::Index::TypeNameResolution do
  # `substitution?` needs one question answered about the signature
  # environment -- "does anything declare this qualified name?" -- so the
  # double answers exactly that, and nothing else. Loading real RBS here
  # would couple these examples to whatever the stdlib declares.
  def signatures_declaring(*qualified_names)
    double = Object.new
    double.define_singleton_method(:ancestors) do |name|
      qualified_names.include?(name) ? [name] : []
    end
    double
  end

  describe ".substitution?" do
    it "recognises a bare name answered by a differently namespaced class as a substitution" do
      expect(
        described_class.substitution?("String", "Serializer::Elements::String", signatures_declaring("::String"))
      ).to be(true)
    end

    # The 024.13 boundary: a workspace genuinely reopening `String` at
    # the top level resolves to the same name, and must keep answering.
    it "does not treat a top-level reopen of the same name as a substitution" do
      expect(
        described_class.substitution?("String", "::String", signatures_declaring("::String"))
      ).to be(false)
    end

    # The qualified-name contract, stated in the module's own comment: a
    # receiver written or inferred with its namespace is nobody else's
    # answer, whatever the workspace resolves it to and whatever
    # signatures declare. The fixture is built so that every *other*
    # branch would answer true -- the resolved class is differently
    # namespaced and signatures declare the name -- so this example fails
    # if the qualified-name guard is removed, which a suite-wide sweep
    # showed nothing else did: the engine, its only production caller,
    # happens to blank qualified receivers one line earlier
    # (`WorkspaceIndex#guessed_type_name?`), and a contract that holds
    # only because the sole caller pre-filters is 0.2.2's emergent-
    # containment lesson over again.
    it "never treats a qualified name as a substitution, even when signatures declare it" do
      expect(
        described_class.substitution?(
          "Billing::Range", "Vendor::Billing::Range", signatures_declaring("::Billing::Range")
        )
      ).to be(false)
    end

    it "is no substitution without a signature environment" do
      expect(described_class.substitution?("String", "Serializer::Elements::String", nil)).to be(false)
    end

    it "is no substitution when the index had no answer" do
      expect(described_class.substitution?("String", nil, signatures_declaring("::String"))).to be(false)
    end

    it "is no substitution for a bare name signatures do not declare" do
      expect(
        described_class.substitution?("Tariff", "Pricing::Tariff", signatures_declaring("::String"))
      ).to be(false)
    end

    # `Signatures::Environment#ancestors` can raise on a malformed name;
    # the rule's answer to "I cannot tell" is "then it is not a
    # substitution", never an exception into the diagnostics engine.
    it "answers false rather than raising when the signature lookup raises" do
      raising = Object.new
      raising.define_singleton_method(:ancestors) { |_name| raise StandardError, "malformed" }

      expect(described_class.substitution?("String", "Serializer::Elements::String", raising)).to be(false)
    end
  end

  # Only a *bare* name. A receiver that carries its own namespace is not
  # somebody else's answer, and `WorkspaceIndex#resolve_type_name` is
  # where a written namespace is enforced since 0.2.6 (`024.78`).
  # Reverting this line made `include Foo::Helpers` refusable whenever
  # any other namespace declared a `Helpers`.
  it "says nothing about a name that carries its own namespace" do
    expect(
      described_class.substitution?("Foo::String", "::Other::String", signatures_declaring("::Foo::String"))
    ).to be(false)
  end
end

