# frozen_string_literal: true

# `042`'s D7. The manifest half, which is safe to run here: every mutation
# names one place exactly, and every example it names exists and is selected
# uniquely.
#
# **Applying the mutations is not run from here.** It writes to `core/lib` and
# restores it, and an interrupted rspec would leave the tree wrong -- so it is
# ci.yml's own job ("Pinned mutations"), which gates. What this example
# guarantees is that the manifest cannot rot without the ordinary suite saying
# so: a renamed example or a rewritten line makes it fail here, immediately,
# rather than in CI after a push.
RSpec.describe "pinned mutations" do
  def verify_only
    script = File.expand_path("../../../scripts/check_pinned_mutations.rb", __dir__)
    IO.popen(["ruby", script, "--verify-only"], err: %i[child out], &:read)
  end

  it "names one place exactly, and one example, for every decision it claims to pin" do
    output = verify_only

    expect($?).to be_success, output
  end

  # `024.211`. This mode takes an early `next` before anything is written
  # and before any example is run to failure, and it used to fall through
  # to the applying run's summary anyway -- so every ordinary suite run
  # printed "every one caught by the example that names it" off the back
  # of a run that caught nothing, in the script built to detect exactly
  # that shape.
  #
  # Asserted on the wording rather than on an exit status because the
  # exit status was never wrong: what was false was the sentence, and a
  # sentence is the only thing that can be false here.
  it "does not claim the applying run's conclusion after applying nothing" do
    output = verify_only

    expect($?).to be_success, output
    expect(output).to include("Nothing was applied here")
    expect(output).not_to include("caught by the example that names it")
  end
end
