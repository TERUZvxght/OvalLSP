# frozen_string_literal: true

# A test command that runs cleanly to completion and simply never calls
# anything in the workspace -- the one case that legitimately means "the
# suite ran and genuinely observed nothing" (Runner#run returns `[]`, not
# `nil`), as opposed to every failure mode around it.
exit 0
