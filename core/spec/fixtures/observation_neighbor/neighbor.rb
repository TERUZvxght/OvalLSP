# frozen_string_literal: true

# Deliberately lives in a directory whose full path *begins with* the
# observation collector spec's workspace root
# (spec/fixtures/observation) but is not inside it. A containment check
# written as a bare string prefix accepts this file; a check on a path
# component boundary rejects it. See collector_spec.rb's
# "workspace root containment is a path boundary, not a string prefix"
# example (round 24).
module ObservationNeighbor
  class Outsider
    def helper(n)
      n.to_s
    end
  end
end
