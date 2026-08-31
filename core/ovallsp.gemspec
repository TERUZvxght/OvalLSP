# frozen_string_literal: true

require_relative "lib/ovallsp/version"

Gem::Specification.new do |spec|
  spec.name = "ovallsp"
  spec.version = Ovallsp::VERSION
  spec.summary = "Ruby Semantic LSP core language server"
  spec.description = "Standalone Core Language Server for Ruby Semantic LSP (OvalLSP)."
  spec.authors = ["OvalLSP"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["lib/**/*.rb", "bin/*"]
  spec.bindir = "bin"
  spec.executables = ["ovallsp"]
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", ">= 0.24"
  spec.add_dependency "rbs", ">= 3.0"

  # Three pasted interpreter sessions ask Ruby about `delegate` and
  # `ActiveSupport::Concern`, so `scripts/check_interpreter_sessions.rb`
  # has to be able to run them. It runs each session with `BUNDLE_*`
  # cleared -- a session is a claim about *Ruby*, not about this
  # bundle -- and that made them resolve against whatever the machine
  # happened to have installed. On a CI runner, where `GEM_PATH` is the
  # vendored bundle and nothing else, they could not run at all and the
  # checker reported four wrong answers that were really four absences.
  # Declaring it puts the gem where both environments look. `024.285`.
  spec.add_development_dependency "activesupport"
  spec.add_development_dependency "benchmark"
  spec.add_development_dependency "rspec", "~> 3.13"
end
