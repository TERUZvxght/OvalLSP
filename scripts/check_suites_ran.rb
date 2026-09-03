#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require "json"

# Did the suites that decide something actually run, or did they skip?
#
#   ruby scripts/check_suites_ran.rb core/tmp/rspec.json
#
# Three spec files skip themselves when their environment is absent, and
# `rspec` still exits 0. A green run can therefore mean the suite that
# decides whether a capability row is true never executed:
#
#   spec/integration/real_rails_spec.rb   needs local rails + sqlite3
#   spec/e2e/capabilities_spec.rb         same fixture
#   spec/meta/client_behaviour_spec.rb    needs vscode/node_modules
#
# Measured with the fixture unavailable: the e2e suite reports every one
# of its examples as pending, zero failures, and exit status 0.
#
# **An example count cannot see this**, which is the trap. A skipped
# example is still an example, so a full count with zero failures is
# exactly what a fully skipped file looks like. The figure that used to
# stand here was a frozen one, and it had drifted from the suite it
# named by the time anyone re-read it -- `024.196`. `scripts/preflight.rb`'s first version
# asserted a non-zero count and therefore could not fail in the one case
# it existed for -- found by review round 1. This logic lived only inside
# `.github/workflows/ci.yml`, forty lines of Ruby embedded in YAML that
# nothing tested and nothing else could call.
#
# **A pending example is a skip unless its message says `NOT YET`.**
# `docs/EXTENSION_CAPABILITIES.md` defines a `NOT YET` row as one that is
# specified, has an E2E row, and is currently failing or pending -- a
# state the document tells authors to use. Failing on those would make
# the documented state unexpressible. The environment skip is what this
# is about, and its message does not say `NOT YET`.
module CheckSuitesRan
  SUITES = {
    "real-Rails integration" => "spec/integration/real_rails_spec.rb",
    "capability E2E" => "spec/e2e/capabilities_spec.rb",
    "client-behaviour" => "spec/meta/client_behaviour_spec.rb"
  }.freeze

  ALLOWED_PENDING = "NOT YET"

  module_function

  # Returns [] when every named suite ran, or a list of complaints.
  def complaints(report, suites: SUITES)
    examples = report.fetch("examples")

    suites.filter_map do |label, path|
      mine = examples.select { |ex| ex.fetch("file_path").include?(path) }
      next "#{path} contributed zero examples -- was it even loaded?" if mine.empty?

      skipped = mine.select do |ex|
        ex.fetch("status") == "pending" && !ex.fetch("pending_message").to_s.include?(ALLOWED_PENDING)
      end
      next if skipped.empty?

      detail = skipped.first(5).map { |ex| "      - #{ex.fetch('full_description')} (#{ex.fetch('pending_message')})" }
      "#{skipped.size}/#{mine.size} #{label} examples were skipped rather than run:\n#{detail.join("\n")}"
    end
  end

  def ran_counts(report, suites: SUITES)
    examples = report.fetch("examples")
    suites.to_h { |label, path| [label, examples.count { |ex| ex.fetch("file_path").include?(path) }] }
  end
end

if __FILE__ == $PROGRAM_NAME
  path = ARGV[0] or abort("usage: ruby scripts/check_suites_ran.rb <rspec-json>")
  report = JSON.parse(File.read(path, encoding: "UTF-8"))

  problems = CheckSuitesRan.complaints(report)
  if problems.empty?
    CheckSuitesRan.ran_counts(report).each { |label, n| puts "check-suites-ran: all #{n} #{label} examples ran." }
    exit 0
  end

  problems.each { |p| warn("check-suites-ran: #{p}") }
  warn("check-suites-ran: a skipped suite is not a passing suite. Install the missing environment " \
       "(docs/DEVELOPMENT.md has the command) rather than reading the exit status.")
  exit 1
end
