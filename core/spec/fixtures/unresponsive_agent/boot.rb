#!/usr/bin/env ruby
# frozen_string_literal: true

# Simulates a Runtime Agent stuck during boot (e.g. a slow Rails app) that
# never completes the agent/hello handshake. Used to test
# AgentProcessManager's boot-timeout -> static-only degradation.
sleep 10
