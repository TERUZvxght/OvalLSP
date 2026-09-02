# frozen_string_literal: true

# The suite used to run against `$XDG_CACHE_HOME/ovallsp` -- the
# maintainer's own cache, 2.3 GB and 53,509 directories on the machine
# this was measured on. `spec_helper` now points it at a per-process temp
# directory.
#
# **The cost was most of the suite's wall time.** `server_spec.rb`, 31
# examples, on one machine minutes apart:
#
#     against the real cache   21.84s
#     against a temp directory  4.66s
#
# **And the correctness reason is the one that matters more.** A run
# mutated the cache the editor then used, so two trees compared against
# it were not compared against the same thing. A 0.3.0 corpus run came
# out with `gem-index-classes` at 2,077 on one side and 2,220 on the
# other, and a false report was nearly attributed to a fix that
# introduced none.
RSpec.describe "the suite's cache root" do
  it "is a temp directory, not the user's own cache" do
    expect(ENV.fetch("XDG_CACHE_HOME", nil)).to eq(SUITE_CACHE_HOME)
    expect(SUITE_CACHE_HOME).to start_with(Dir.tmpdir)
  end

  # The control: without the redirection this is where a store would go,
  # and the example above is only worth something if that is somewhere
  # else.
  it "is not the path a server would otherwise have used" do
    expect(SUITE_CACHE_HOME).not_to eq(File.join(Dir.home, ".cache"))
    expect(File.join(SUITE_CACHE_HOME, "ovallsp")).not_to start_with(Dir.home)
  end

  # Per process, so two suites running at once cannot prune each other's
  # entries -- which is what `024.71` records happening through the Rails
  # fixture, from the other direction.
  it "is unique to this process" do
    expect(SUITE_CACHE_HOME).to include(Process.pid.to_s)
  end
end
