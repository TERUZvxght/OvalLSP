# frozen_string_literal: true

# **The stack an example gets is the stack the server gets** (`042`'s D8).
#
# Twenty-eight spec files used to write these constructors out, and most
# were missing one: `open_surface_spec.rb`'s `LocalInferencer` had no
# `signatures:`, no `workspace_index:` and no `hierarchy_index:` while the
# server's had all three. An example was therefore green against a program
# that is not the one that ships -- `024.109`'s category arriving through
# the wiring rather than through a fixture, and invisible until
# `spec/meta/analysis_stack_spec.rb` compared the two lists.
#
# `024.119` records the migration.
module AnalysisStackHelper
  # Loaded once for the suite: an RBS environment costs seconds and every
  # example wants the same one.
  def self.shared_signatures
    @shared_signatures ||= Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) }
  end

  def build_analysis_stack(workspace_index: Ovallsp::WorkspaceIndex.new,
                           signatures: AnalysisStackHelper.shared_signatures, **rest)
    Ovallsp::AnalysisStack.build(signatures: signatures, workspace_index: workspace_index, **rest)
  end
end

RSpec.configure { |config| config.include AnalysisStackHelper }
