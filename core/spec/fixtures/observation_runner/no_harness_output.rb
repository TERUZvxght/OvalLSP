# frozen_string_literal: true

# A test command that exits *cleanly* without the harness ever writing a
# result file -- `exit!` skips at_exit, which is where Harness#dump runs.
#
# It stands in for the ordinary real-world configurations that behave the
# same way from Runner's side: a test command that isn't a Ruby process at
# all (`make test`, `npm test`, `docker compose run ...`), a wrapper script
# that re-execs with a sanitized environment and drops the `-r<harness>`
# RUBYOPT, or a Spring/Zeus-style preloader whose client hands the run to
# an already-running server process and exits 0 having loaded nothing.
# All of them exit zero and leave a zero-byte result file, which is "the
# harness never ran" (Runner#run returns `nil`), never "the suite ran and
# genuinely observed nothing" (`[]`) -- see no_observations.rb for the
# latter, which really does go through the harness.
exit!(0)
