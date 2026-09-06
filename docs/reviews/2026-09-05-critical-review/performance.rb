require 'json'
require 'digest'
require 'logger'
require 'ovallsp'
warn "review-performance: cwd=#{Dir.pwd} ruby=#{RUBY_VERSION} ovallsp=#{Ovallsp::VERSION}"
path = Gem.find_files('net/http.rb').first
abort 'net/http.rb not available' unless path
source = File.read(path, encoding: 'UTF-8')
warn "review-performance: corpus=net/http.rb sha256=#{Digest::SHA256.hexdigest(source)}"
env = Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) }
stack = Ovallsp::AnalysisStack.build(signatures: env)
doc = Ovallsp::TextDocument.new(uri: 'file:///review/net/http.rb', text: source, version: 1, language_id: 'ruby')
parser = Ovallsp::ParserService.new
stack.replace_file(parser.summarize(doc))
context = stack.semantic_context(route_registry: Ovallsp::Routes::RouteRegistry.new)
engine = Ovallsp::Diagnostics::Engine.new
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
samples = 3.times.map do
  start = clock.call; parser.summarize(doc); parse = clock.call - start
  start = clock.call; findings = engine.analyze(document: doc, semantic_context: context, mode: :safe); analyze = clock.call - start
  {parse_seconds: parse.round(4), analyze_seconds: analyze.round(4), findings: findings.group_by(&:code).transform_values(&:length)}
end
puts JSON.pretty_generate(ruby: RUBY_VERSION, ovallsp: Ovallsp::VERSION, corpus: 'net/http.rb',
  corpus_sha256: Digest::SHA256.hexdigest(source), mode: 'safe', signatures: 'core and stdlib, no project sig',
  runtime_agent: false, workspace_index: 'single corpus file', samples: samples)
