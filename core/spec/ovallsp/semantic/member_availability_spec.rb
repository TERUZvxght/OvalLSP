# frozen_string_literal: true

# `MethodResolver#resolve` answers a list, and an empty list means two
# different things: the method is not there, or the receiver's members
# could not be enumerated at all. `resolve`'s own second line is
# `return [] if types.empty?` -- the second case, spelled as the first.
#
# Every consumer then reconstructs the difference locally.
# `Diagnostics::Engine#closed_nominal?` keeps its own list of ways of not
# knowing and subtracts them one at a time; 0.2.6 added four of those, one
# per review round, each after a user-visible false report. Completion,
# hover and signature help each reach the index by their own route and
# disagree at the same position (`024.100`, and six more the 0.2.8 drive
# round measured).
#
# So the value says which of the three it is, and `unknown` is produced by
# whatever failed to enumerate rather than inferred by a caller. A new way
# of not knowing then makes every reader silent by construction, instead
# of by each reader being taught. `037`'s C2.
RSpec.describe Ovallsp::Semantic::MemberAvailability do
  let(:candidate) { double("candidate", name: "save") }

  describe "the three answers" do
    it "is present when something was found" do
      availability = described_class.present([candidate])

      expect([availability.present?, availability.absent?, availability.unknown?]).to eq([true, false, false])
      expect(availability.candidates).to eq([candidate])
    end

    it "is absent only when the whole surface was enumerated and the name was not in it" do
      availability = described_class.absent

      expect([availability.present?, availability.absent?, availability.unknown?]).to eq([false, true, false])
      expect(availability.candidates).to be_empty
    end

    it "is unknown when something could not be enumerated, and says what" do
      availability = described_class.unknown(:ancestor_not_identified)

      expect([availability.present?, availability.absent?, availability.unknown?]).to eq([false, false, true])
      expect(availability.reason).to eq(:ancestor_not_identified)
    end
  end

  # The property the whole exercise rests on: a caller cannot get from
  # `unknown` to "not there" without saying so. `#absent?` is the only
  # predicate that admits absence, and `unknown` does not answer it --
  # so a check written against `#absent?` is silent on a receiver nobody
  # could enumerate, whether or not its author thought about that
  # receiver.
  it "never lets an unknown be read as an absence" do
    expect(described_class.unknown(:whatever)).not_to be_absent
  end

  # And an unknown must name its reason: an unexplained one is the state
  # the boolean was, wearing a new type.
  it "refuses an unknown with no reason" do
    expect { described_class.unknown(nil) }.to raise_error(ArgumentError, /reason/)
  end

  # **This example could not distinguish anything until 0.2.12.** It
  # asserted `described_class.absent` is frozen -- which a `Data` is
  # anyway, whatever this class does -- so it passed with every `freeze`
  # in the file removed. One of the two `024.109` reports whose identity
  # was lost with the round's list; found by
  # `scripts/check_pinned_mutations.rb` rather than by re-reading.
  #
  # What matters is the *candidates array*, which is the thing a caller
  # is handed and could push onto. The literal is built with `+""`-style
  # explicitness for the same reason `text_document_spec` does: a frozen
  # string literal would make the fixture pass either way.
  it "is frozen all the way to the candidates a reader is handed" do
    present = described_class.present(["build"])

    expect(present).to be_frozen
    expect(present.candidates).to be_frozen
    expect { present.candidates << "extra" }.to raise_error(FrozenError)
  end

  it "freezes the candidates of an absence and an unknown too" do
    expect(described_class.absent.candidates).to be_frozen
    expect(described_class.unknown(:surface_open).candidates).to be_frozen
  end
end
