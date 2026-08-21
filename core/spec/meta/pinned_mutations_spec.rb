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
  it "names one place exactly, and one example, for every decision it claims to pin" do
    script = File.expand_path("../../../scripts/check_pinned_mutations.rb", __dir__)
    output = IO.popen(["ruby", script, "--verify-only"], err: %i[child out], &:read)

    expect($?).to be_success, output
  end
end
