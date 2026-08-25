# frozen_string_literal: true

require "yaml"

# One reader of `.github/workflows/ci.yml`, for the specs that pin the
# guards which exist only there.
#
# Several steps of that workflow are CI-only text: nothing else in the
# tree runs them, so deleting one leaves every check in the repository
# green while the guarantee resting on it goes. Two spec files pin such
# steps and were doing it two different ways -- `ci_skip_guard_spec`
# locating the step in parsed YAML, `suites_ran_spec` asserting a
# substring of the whole file. A substring survives a step that has been
# commented out, so the weaker of the two passed under every mutation it
# appeared to guard against. `024.203`.
#
# `executed?` is the other half, and `046`'s round-2 finding is what it
# is for: three one-line edits -- `continue-on-error: true`, `if: false`,
# and `|| true` appended to the run text -- each disable a gate with the
# whole of `spec/meta` green. The first two are parsed structure GitHub
# acts on and are answered here. The third is run text, and belongs to
# whichever example asserts what the step runs.
module CiWorkflow
  WORKFLOW = File.expand_path("../../../.github/workflows/ci.yml", __dir__)

  module_function

  # Explicit encoding, never the machine's ambient locale: this workflow
  # quotes Japanese document names, and `File.read` alone raises
  # `invalid byte sequence in US-ASCII` on a runner with no locale set.
  def text = File.read(WORKFLOW, encoding: "UTF-8")

  def jobs = YAML.safe_load(text).fetch("jobs")

  def job(name) = jobs.fetch(name)

  def core_step(name) = job("core").fetch("steps").find { |s| s["name"] == name }

  # GitHub runs a step when it carries no `if` and is not excused from
  # failing. Either key turns a red gate green without removing one
  # character of the text a substring assertion reads.
  def executed?(step)
    !step.nil? && step["if"].nil? && step["continue-on-error"] != true
  end
end
