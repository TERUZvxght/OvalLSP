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

  # Stands in for an instrumentation/patching gem: something outside the
  # workspace that `prepend`s itself into one of the workspace's own
  # classes (ObservationFixture::Patched). Deliberately a *different
  # arity* and different parameter names from the method it wraps, so
  # describing the wrong one of the two is visible in the recorded
  # signature rather than coincidental. See collector_spec.rb's round-25
  # examples.
  module Instrumentation
    def perform(gem_arg, gem_extra = :instrumented)
      super(gem_arg)
    end
  end

  # The other direction: a gem class the *workspace* prepends a module
  # into (ObservationFixture::ServicePatch). Its own method is gem code
  # and must never be collected, however the workspace patches it.
  class Service
    def call(gem_name)
      "gem:#{gem_name}"
    end
  end
end
