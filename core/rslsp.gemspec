# frozen_string_literal: true

require_relative "lib/rslsp/version"

Gem::Specification.new do |spec|
  spec.name = "rslsp"
  spec.version = Rslsp::VERSION
  spec.summary = "Ruby Semantic LSP core language server"
  spec.description = "Standalone Core Language Server for Ruby Semantic LSP (RSLSP)."
  spec.authors = ["OvalLSP"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["lib/**/*.rb", "bin/*"]
  spec.bindir = "bin"
  spec.executables = ["rslsp"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.13"
end
