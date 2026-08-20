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
    %r{\Acore/spec/ovallsp/(semantic/(hierarchy_index|method_resolver|method_analyzer)|local_inferencer)_spec\.rb\z}
  ].freeze

  # **A debt with a ceiling, not an exemption.** The two places that
  # decide what ships -- `Server#initialize` and
  # `scripts/corpus_diagnostics.rb` -- assemble nothing now, which is
  # where both measured failures happened. These spec files still write
  # the constructors out, and most are missing one (`signatures:`,
  # `hierarchy_index:` or `generated_method_index:`), so each is an
  # example that can pass while the server answers differently.
  #
  # Listed by name rather than by pattern so the set can only shrink: a
  # new file cannot join it without an edit here, and the count below is
  # a measured claim. Migrating them is `042`'s D8 in 0.2.12; this is the
  # part of it that is bookkeeping rather than design, and it is recorded
  # rather than left to a reader to notice.
  NOT_YET_MIGRATED = %w[
    core/spec/ovallsp/diagnostics/argument_type_spec.rb
    core/spec/ovallsp/diagnostics/class_body_macro_spec.rb
    core/spec/ovallsp/diagnostics/dynamic_ancestor_spec.rb
    core/spec/ovallsp/diagnostics/engine_spec.rb
    core/spec/ovallsp/diagnostics/forward_alias_spec.rb
    core/spec/ovallsp/diagnostics/nested_alias_spec.rb
    core/spec/ovallsp/diagnostics/nested_bare_name_spec.rb
    core/spec/ovallsp/diagnostics/open_surface_spec.rb
    core/spec/ovallsp/diagnostics/project_signature_spec.rb
    core/spec/ovallsp/diagnostics/rooted_receiver_spec.rb
    core/spec/ovallsp/diagnostics/union_receiver_spec.rb
    core/spec/ovallsp/diagnostics/unreadable_macro_spec.rb
    core/spec/ovallsp/diagnostics/visibility_spec.rb
    core/spec/ovallsp/models/root_scoped_model_spec.rb
    core/spec/ovallsp/parser_concern_class_methods_spec.rb
    core/spec/ovallsp/parser_module_function_spec.rb
    core/spec/ovallsp/rename/planner_spec.rb
    core/spec/ovallsp/semantic/ambiguous_ancestor_spec.rb
    core/spec/ovallsp/semantic/class_object_ancestors_spec.rb
    core/spec/ovallsp/semantic/method_resolver_availability_spec.rb
    core/spec/ovallsp/semantic/nameless_ancestor_spec.rb
    core/spec/ovallsp/semantic/query_service_spec.rb
    core/spec/ovallsp/semantic/reference_resolver_spec.rb
    core/spec/ovallsp/semantic/reopened_object_spec.rb
    core/spec/ovallsp/server_views_spec.rb
    core/spec/ovallsp/signatures/environment_spec.rb
    core/spec/ovallsp/signatures/untyped_function_spec.rb
    core/spec/ovallsp/types/literal_types_spec.rb
  ].freeze

  def permitted?(path)
    PERMITTED.any? { |p| p.is_a?(Regexp) ? p.match?(path) : p == path }
  end

  it "is assembled in exactly one place" do
    repo_root = File.expand_path("../../..", __dir__)
    tracked = Dir.chdir(repo_root) { `git ls-files "*.rb"`.lines.map(&:chomp) }
    pattern = /\bOvallsp::(?:#{Regexp.union(ASSEMBLED)})\.new|^\s*(?:#{Regexp.union(ASSEMBLED)})\.new/

    offenders = tracked.reject { |path| permitted?(path) || NOT_YET_MIGRATED.include?(path) }.select do |path|
      File.read(File.join(repo_root, path), encoding: "UTF-8").match?(pattern)
    end

    expect(offenders).to be_empty,
                         "these assemble their own analysis stack instead of calling " \
                         "`Ovallsp::AnalysisStack.build`: #{offenders.join(', ')}. " \
                         "A harness that assembles is a harness that can differ from the server " \
                         "(042's D8; 024.103 and 024.112 were both measured against one that did)."
  end

  # The debt can only shrink. A file that stops assembling must leave the
  # list, so the list cannot quietly describe a tree that has moved on --
  # which is the failure `024.102`'s stocktake found in `036`.
  it "lists only files that really do still assemble one" do
    repo_root = File.expand_path("../../..", __dir__)
    pattern = /\bOvallsp::(?:#{Regexp.union(ASSEMBLED)})\.new/

    stale = NOT_YET_MIGRATED.reject do |path|
      full = File.join(repo_root, path)
      File.exist?(full) && File.read(full, encoding: "UTF-8").match?(pattern)
    end

    expect(stale).to be_empty,
                     "these no longer assemble their own stack (or no longer exist) -- " \
                     "remove them from NOT_YET_MIGRATED: #{stale.join(', ')}"
  end

  # The distinguishing half: the check must fail for a real duplicate, not
  # merely pass because the pattern matches nothing.
  it "would catch a harness that assembled its own" do
    pattern = /\bOvallsp::(?:#{Regexp.union(ASSEMBLED)})\.new/

    expect("x = Ovallsp::LocalInferencer.new(method_resolver: r)").to match(pattern)
    expect("x = Ovallsp::DocumentStore.new").not_to match(pattern)
  end
end
