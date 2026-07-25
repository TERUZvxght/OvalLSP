# frozen_string_literal: true

# Regression fixture for the round-13 independent review of Task 022.2:
# a plugin that closes the loader's result pipe from inside the child and
# then refuses to exit.
#
# Loader#isolate_child_io deliberately leaves the result channel as a bare
# fd number so no live Ruby IO object references it while plugin code runs
# (that is what defeats spec/fixtures/plugins/pipe_forger). Its own docs
# already concede the remaining hole: "A plugin could still, in principle,
# brute-force-guess the fd number and call IO.for_fd itself." That is what
# this does -- but instead of *writing* a forged payload, it *closes* the
# fd, which the parent sees as a perfectly ordinary EOF while this process
# is still very much alive and sleeping.
#
# The point is Loader#read_isolated_result's post-EOF wait: EOF no longer
# implies "the child has finished #deliver_result and is inside exit!", so
# an unbounded Process.waitpid there blocks the LSP transport thread (
# #load_static runs synchronously in Server#dispatch's `initialize`
# handler) for as long as this plugin cares to sleep. @timeout_seconds
# never fires, because the read it bounds already returned.
Ovallsp::Plugins.register_static("ovallsp-fd-closer") do |_context|
  (3..64).each do |fd|
    ::IO.for_fd(fd).close
  rescue StandardError
    nil
  end

  sleep 60
end
