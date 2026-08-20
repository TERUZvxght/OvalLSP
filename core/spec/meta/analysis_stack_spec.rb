# frozen_string_literal: true

require "spec_helper"

# **`042`'s D8: the thing under test must be the thing that ships.**
#
# Twice a fix has been measured against a harness that did not have the
# collaborator the fix reads. `024.103` in 0.2.10 came out byte-identical
# on both sides of a 6,772-finding comparison. `024.112` in 0.2.11 did it
# again -- in `scripts/corpus_diagnostics.rb`, whose own comment says
# "keep every constructor here matching `Server#initialize`", added after
# the first time. A comment asking a reader to keep two lists in step is
# the arrangement that failed; this is the check that replaces it.
#
# The rule: **one function assembles the analysis stack, and nothing else
# assembles one.** A harness cannot be a subset of the server if it does
# not assemble anything, and a collaborator added to the stack reaches
# every consumer of the stack in the same edit.
RSpec.describe "the analysis stack" do
  # The collaborators whose wiring decides what the engine can answer. A
  # constructor call to any of these, outside the one assembler, is a
  # second program that can silently differ from the one that ships.
  ASSEMBLED = %w[
    Semantic::HierarchyIndex
    Semantic::MethodResolver
    Semantic::MethodAnalyzer
    LocalInferencer
  ].freeze

  # Where assembling is the job, and where a direct constructor call is
  # the subject rather than a duplicate of the server's wiring.
  PERMITTED = [
    "core/lib/ovallsp/analysis_stack.rb",
    "core/spec/meta/analysis_stack_spec.rb",
    %r{\Acore/spec/ovallsp/(semantic/(hierarchy_index|method_resolver|method_analyzer)|local_inferencer)_spec\.rb\z}
  ].freeze


  def permitted?(path)
    PERMITTED.any? { |p| p.is_a?(Regexp) ? p.match?(path) : p == path }
  end

  it "is assembled in exactly one place" do
    repo_root = File.expand_path("../../..", __dir__)
    tracked = Dir.chdir(repo_root) { `git ls-files "*.rb"`.lines.map(&:chomp) }
    pattern = /\bOvallsp::(?:#{Regexp.union(ASSEMBLED)})\.new|^\s*(?:#{Regexp.union(ASSEMBLED)})\.new/

    offenders = tracked.reject { |path| permitted?(path) }.select do |path|
      File.read(File.join(repo_root, path), encoding: "UTF-8").match?(pattern)
    end

    expect(offenders).to be_empty,
                         "these assemble their own analysis stack instead of calling " \
                         "`Ovallsp::AnalysisStack.build`: #{offenders.join(', ')}. " \
                         "A harness that assembles is a harness that can differ from the server " \
                         "(042's D8; 024.103 and 024.112 were both measured against one that did)."
  end

  # The distinguishing half: the check must fail for a real duplicate, not
  # merely pass because the pattern matches nothing.
  it "would catch a harness that assembled its own" do
    pattern = /\bOvallsp::(?:#{Regexp.union(ASSEMBLED)})\.new/

    expect("x = Ovallsp::LocalInferencer.new(method_resolver: r)").to match(pattern)
    expect("x = Ovallsp::DocumentStore.new").not_to match(pattern)
  end
end
