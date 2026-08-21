# frozen_string_literal: true

# `042`'s D10 / `024.122`. Every `rescue` statement in `core/lib` carries
# a verdict, and a new one with no verdict fails here.
#
# That is the whole mechanism, and it is deliberately not "no rescue may
# swallow". A rule saying that would have had 111 exceptions on the day
# it was written, which is the arrangement `CLAUDE.md`'s preamble warns
# about. What this enforces is that **the decision is made**: writing a
# rescue means writing down what happens to the failure, in a file a
# reviewer reads, and `swallows` is a verdict somebody has to type rather
# than a default nobody notices.
#
# Emptying the `swallows` column is the work; this is what stops it
# refilling behind that work's back.
RSpec.describe "rescue verdicts" do
  it "covers every rescue in core/lib, and nothing that is gone" do
    script = File.expand_path("../../../scripts/check_swallowed_failures.rb", __dir__)
    output = IO.popen(["ruby", script], err: %i[child out], &:read)

    expect($?).to be_success, output
  end
end
