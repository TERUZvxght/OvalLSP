# frozen_string_literal: true

# `024.122`. Two checks in `Engine` asked a question, could not get an
# answer, and used the *reporting* value as the fallback.
#
# `#ivar_names_tested_for_existence` answered `[]`, which reads as "this
# file is defensive about nothing" -- so a failure turned every
# `defined?(@x)` into an unassigned-ivar report. And
# `#rbs_known_constant?` answered `false`, which reads as "RBS does not
# know this name" -- an assertion about the user's code, made from a
# question that could not be asked.
#
# Enumerating is what decides whether to assert, so a failure to
# enumerate has to decline. §0: a wrong answer is worse than no answer.
RSpec.describe "Ovallsp::Diagnostics::Engine when it cannot enumerate" do
  let(:engine) { Ovallsp::Diagnostics::Engine.new }

  describe "the ivars a file is defensive about" do
    it "answers the names when it can look" do
      document = Ovallsp::TextDocument.new(
        uri: "file:///a.rb", version: 1, language_id: "ruby",
        text: "class A\n  def go\n    @x if defined?(@x)\n  end\nend\n"
      )

      expect(engine.send(:ivar_names_tested_for_existence, document)).to eq(["@x"])
    end

    # The distinguishing half: `[]` is the answer for a file that tests
    # nothing, and a failure must not be that same value.
    it "answers nil rather than an empty list when it cannot" do
      broken = instance_double(Ovallsp::TextDocument)
      allow(broken).to receive(:text).and_raise(IOError, "gone")

      expect(engine.send(:ivar_names_tested_for_existence, broken)).to be_nil
    end
  end

  describe "whether RBS knows a constant" do
    it "says so when it can ask" do
      signatures = build_analysis_stack.signatures

      expect(engine.send(:rbs_known_constant?, "String", signatures)).to be(true)
      expect(engine.send(:rbs_known_constant?, "DefinitelyNotAThing", signatures)).to be(false)
    end

    # Failing towards "known" declines; failing towards "unknown" would
    # report. An implementation that rescued into `false` passes the
    # example above and fails this one.
    it "declines rather than reports when the question cannot be asked" do
      broken = instance_double(Ovallsp::Signatures::Environment)
      allow(broken).to receive(:ancestors).and_raise(IOError, "gone")

      expect(engine.send(:rbs_known_constant?, "Whatever", broken)).to be(true)
    end
  end
end
