# frozen_string_literal: true

module Ovallsp
  # The Extension<->Core protocol version -- distinct from, and unrelated
  # to, RuntimeAgent::Agent::PROTOCOL_VERSION (Core<->Runtime Agent
  # subprocess) and Plugins::CURRENT_PROTOCOL_VERSION (Core<->plugin).
  # Neither of those existed to negotiate compatibility between the VS
  # Code extension itself and the Core Server it launches -- this one does
  # (Task 023.2).
  #
  # A single integer bumped whenever the Extension<->Core wire contract
  # changes in a way a client/server pair must agree on to interoperate
  # safely (not merely "we added a new optional field", which capability
  # negotiation via `initializationOptions`/`capabilities.experimental`
  # already handles without a version bump). MINIMUM/MAXIMUM exist so a
  # future breaking change can widen the accepted range gradually instead
  # of every client and server needing to update in lockstep.
  module ProtocolVersion
    CURRENT = 1
    MINIMUM_CLIENT = 1
    MAXIMUM_CLIENT = 1
    MINIMUM_SERVER = 1
    MAXIMUM_SERVER = 1
  end
end
