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

  # **How many decisions are pinned**, which nothing here asserted.
  #
  # `024.151` is the class: "the checks are correct; their reachability
  # is not defended".
  #
  # **The checker already refuses an *empty* manifest** — driven, it
  # exits 1 and says so, and the first draft of this comment claimed
  # otherwise. What nothing caught is a *gutted* one: a manifest cut to
  # a single entry is not empty, is consistent with itself, and passes
  # both examples above. The manifest that exists to stop a guarantee
  # being quietly disabled could itself be quietly narrowed.
  #
  # A floor rather than the count: entries are added every release, and
  # an exact number fails on the next one for a reason nobody wants to
  # read.
  it "is pinning a manifest, rather than reporting an empty one consistent" do
    output = verify_only

    pinned = output[/(\d+) mutation\(s\)/, 1].to_i
    expect(pinned).to be >= 50,
                      "the manifest holds #{pinned} mutations. An empty one is consistent with itself and " \
                      "reports exactly what a full one reports when nothing is wrong (024.151).\n#{output}"
  end
end
