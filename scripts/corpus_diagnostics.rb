# frozen_string_literal: true

# Drives the diagnostics engine over a corpus of real Ruby and prints
# every finding, one per line, in a form two revisions' runs can be
# diffed against each other:
#
#   code<TAB>path:line:character<TAB>message
#
# This exists because fixtures stopped finding defects partway through the
# 0.2.0 review loop, and every round after that found its defects by
# running the engine over the stdlib, the installed gems and this
# repository's own `core/lib`, then reading the difference against `main`.
# That method was an ad-hoc script rebuilt from memory each round, which
# made the loop's own recommendation unrunnable by whoever read it. See
# `docs/design/tasks/025-0.2.0-review-loop-handover.md`.
#
# Usage, from `core/`:
#
#   bundle exec ruby ../scripts/corpus_diagnostics.rb <dir-or-file>...
#
# Compare by running it once here and once from a `git worktree` of the
# other revision, pointing *both* at the same corpus directory, then
# `comm` the sorted outputs. A line only the new side produces is a report
# the change introduced; a line only the old side produces is one it
# removed. Both are worth reading; the first is worth reading first.
#
# Every path in the corpus is indexed into one workspace before anything
# is analysed, which is what makes cross-file resolution behave as it does
# in an editor. Nothing here writes to the corpus.
#
# This runs `mode: :standard`, while the Server defaults to `:safe`. The
# difference is `unresolved-constant`, which a default-configured user
# never sees and which outnumbers everything else on a large corpus by
# roughly an order of magnitude. Filter it out (`grep -v
# '^unresolved-constant'`) when the question is what a user would be
# shown; keep it when the question is what the engine can resolve.
#
# Signatures are loaded from `Dir.pwd` by default, not from the corpus, so
# a gem's own `sig/` is not read when you point this at one. That keeps an
# A/B comparison honest -- both sides see the same signatures -- but it
# means an absolute count over a foreign corpus is not what a user opening
# that project would be shown.
#
# `OVALLSP_SIGNATURE_ROOT` overrides it, which is how to ask the second
# question. Set it to the corpus's own root and a gem that ships `sig/`
# is measured the way its author intended:
#
#   OVALLSP_SIGNATURE_ROOT=<gem-root> bundle exec ruby \
#     ../scripts/corpus_diagnostics.rb <gem-root>/lib
#
# It exists because the checks that read signatures cannot be measured
# without it. `argument-type` reports only where a parameter's type is
# *stated*, so pointing this at a corpus whose signatures are not loaded
# measures the check at its floor and says nothing about its ceiling.
# Keep it unset for an A/B run between two revisions; set it when the
# question is how a check behaves on code that has signatures.

# From `Dir.pwd`, so this has to be run from `core/`. The engine and the
# signature root were the same directory until the variable above
# separated them.
$LOAD_PATH.unshift(File.expand_path("lib", Dir.pwd))
require "ovallsp"

if ARGV.empty?
  warn "usage: bundle exec ruby ../scripts/corpus_diagnostics.rb <dir-or-file>..."
  exit 1
end

paths = ARGV.flat_map { |arg| File.directory?(arg) ? Dir.glob(File.join(arg, "**", "*.rb")) : [arg] }.sort

workspace_index = Ovallsp::WorkspaceIndex.new
model_registry = Ovallsp::Models::ModelRegistry.new
signature_root = ENV.fetch("OVALLSP_SIGNATURE_ROOT", Dir.pwd)
signatures = Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: signature_root) }
# Built the way `Server#initialize` builds it. Until 0.2.1 this script
# constructed a *different* engine from the server's -- it omitted the
# `signatures:` the shadow rule of the day read -- so every number it
# produced described a configuration no user runs. That is not a smaller
# measurement, it is a measurement of something else, and it is why a
# 55-report regression reached a release whose headline figure came from
# here (024.48). The rule now lives in the diagnostics engine alone and
# reads the `signatures:` handed to `SemanticContext` below; keep every
# constructor here matching `Server#initialize`, whatever each currently
# takes.
hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
method_resolver = Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index,
                                                        hierarchy_index: hierarchy_index)
# `workspace_index:` is not optional here even though the constructor
# allows it: without it this harness builds a *different program* from the
# one the server runs, and 0.2.10 caught that the hard way -- a fix for
# `024.103` came out byte-identical on both sides of a 6,772-finding
# comparison, because the collaborator the fix reads was never wired in.
# Identical output is the signature of a measurement error, which is the
# only reason it was looked at (CLAUDE.md).
local_inferencer = Ovallsp::LocalInferencer.new(
  model_registry: model_registry, method_resolver: method_resolver, signatures: signatures,
  workspace_index: workspace_index, hierarchy_index: hierarchy_index,
  method_analyzer: Ovallsp::Semantic::MethodAnalyzer.new(
    workspace_index: workspace_index, method_resolver: method_resolver,
    summary_store: Ovallsp::Semantic::MethodSummaryStore.new,
    model_registry: model_registry, generated_method_index: Ovallsp::Semantic::GeneratedMethodIndex.new
  ),
  observation_store: Ovallsp::Observation::Store.new
)
context = Ovallsp::Diagnostics::SemanticContext.new(
  workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
  local_inferencer: local_inferencer, model_registry: model_registry,
  route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1,
  ancestry_registry: Ovallsp::Runtime::AncestryRegistry.new
)

parser = Ovallsp::ParserService.new
documents = {}

paths.each do |path|
  text = File.read(path, encoding: "UTF-8")
  # A corpus of real gems contains fixtures for broken encodings, and
  # Prism raises rather than reporting on them. Skipping is not a
  # judgement about them; they are simply not what this is measuring.
  next unless text.valid_encoding?

  document = Ovallsp::TextDocument.new(uri: "file://#{path}", text: text, version: 1, language_id: "ruby")
  summary = parser.summarize(document)
  workspace_index.replace_file(summary)
  hierarchy_index.replace_file(summary)
  documents[path] = document
rescue StandardError => e
  # To stderr, so a crash on one file neither stops the run nor lands in
  # the stream being diffed.
  warn "INDEX-ERROR #{path}: #{e.class}: #{e.message}"
end

engine = Ovallsp::Diagnostics::Engine.new

documents.each do |path, document|
  engine.analyze(document: document, semantic_context: context, mode: :standard).each do |finding|
    position = finding.range[:start]
    puts "#{finding.code}\t#{path}:#{position[:line]}:#{position[:character]}\t#{finding.message.gsub(/\s+/, " ")}"
  end
rescue StandardError => e
  warn "ANALYZE-ERROR #{path}: #{e.class}: #{e.message}"
end
