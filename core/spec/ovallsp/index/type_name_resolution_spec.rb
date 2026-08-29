# frozen_string_literal: true

RSpec.describe Ovallsp::Index::TypeNameResolution do
  # `substitution?` needs one question answered about the signature
  # environment -- "does anything declare this name?" -- so the double
  # answers exactly that, and nothing else. Loading real RBS here would
  # couple these examples to whatever the stdlib declares.
  #
  # It qualifies the name itself because `Environment#declares?` does:
  # the caller passes the bare name it was given, and where the rooted
  # spelling is decided is the point of the method.
  def signatures_declaring(*qualified_names)
    double = Object.new
    double.define_singleton_method(:declares?) do |name|
      qualified_names.include?(Ovallsp::Index::SymbolId.qualify_owner(name))
    end
    double
  end

  # The third answer: declared, and the chain could not be built
  # (`024.223`). Every other name is one the signature set has never
  # heard of, so an example using this double still distinguishes the
  # two.
  def signatures_unable_to_build(*qualified_names)
    double = Object.new
    double.define_singleton_method(:declares?) do |name|
      qualified_names.include?(Ovallsp::Index::SymbolId.qualify_owner(name)) ? nil : false
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

    # `024.246`. The question here is declaration, not enumeration: a
    # name whose ancestry could not be built is still a name signatures
    # declare, so the workspace class that merely shares its last segment
    # is still standing in for it. Reading that third answer as an
    # absence switched the refusal off, and the engine reported a method
    # against the wrong class entirely -- `024.223`'s cause arriving at a
    # reader that entry does not enumerate. Written `== true` this
    # example fails and every other one in this block passes.
    it "still recognises a substitution when the chain could not be built" do
      expect(
        described_class.substitution?(
          "String", "Serializer::Elements::String", signatures_unable_to_build("::String")
        )
      ).to be(true)
    end

    it "is no substitution for a bare name signatures do not declare" do
      expect(
        described_class.substitution?("Tariff", "Pricing::Tariff", signatures_declaring("::String"))
      ).to be(false)
    end

    # This example used to assert that a `rescue StandardError` here
    # answered `false` when the signature lookup raised, and it built the
    # raising collaborator itself. The premise was wrong:
    # `Signatures::Environment#ancestors` answers `[]` for a name it
    # cannot parse and never raises, which `environment_spec` now pins
    # where that containment lives. So the rescue could only ever have
    # hidden a *different* failure, and a double was the only thing that
    # could reach it. Asked of the real collaborator instead.
    it "is no substitution for a name the signature environment cannot parse" do
      environment = Ovallsp::Signatures::Environment.new
      environment.load(workspace_root: nil)

      expect(described_class.substitution?("Not A Type[[[", "Serializer::Elements::String", environment)).to be(false)
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

