# frozen_string_literal: true

# Run under core's bundle, passing the lib directory of each compared tree.
# Counts one warmed analysis of a fixed source; this is not an LSP latency test.
require "digest"
require "json"
require File.join(File.expand_path(ARGV.fetch(0)), "ovallsp")

source = "class Widget\n" \
  "  def initialize(name)\n    @name = name\n  end\n" \
  "  def show\n    bogus\n    accepts\n    @never_set\n    label(1, 2)\n    accepts(\"x\")\n  end\n" \
  "  def accepts(one); end\n  def label(a); end\nend\n"
puts "cwd=#{Dir.pwd} lib=#{File.expand_path(ARGV.fetch(0))} version=#{Ovallsp::VERSION}"
signatures = Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) }
stack = Ovallsp::AnalysisStack.build(signatures: signatures)
document = Ovallsp::TextDocument.new(uri: "file:///parse-count-control.rb", text: source,
                                    version: 1, language_id: "ruby")
stack.replace_file(Ovallsp::ParserService.new.summarize(document))
context = stack.semantic_context(route_registry: Ovallsp::Routes::RouteRegistry.new, assigned_ivars: [])
engine = Ovallsp::Diagnostics::Engine.new
engine.analyze(document: document, semantic_context: context, mode: :standard)
calls = []
counter = Module.new do
  define_method(:parse) do |text, **options|
    calls << text
    super(text, **options)
  end
end
Prism.singleton_class.prepend(counter)
findings = engine.analyze(document: document, semantic_context: context, mode: :standard)
answers = findings.map { |f| [f.code, f.message, f.range] }
puts JSON.generate(source_sha256: Digest::SHA256.hexdigest(source),
                   whole_source_parses: calls.count(source), total_parses: calls.length,
                   findings_sha256: Digest::SHA256.hexdigest(JSON.generate(answers)),
                   codes: findings.map(&:code).sort)
