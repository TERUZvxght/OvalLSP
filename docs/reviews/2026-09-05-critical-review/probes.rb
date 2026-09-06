# frozen_string_literal: true
require 'json'
require 'tmpdir'
require 'stringio'
require 'fileutils'
require 'logger'
require 'ovallsp'

warn "review-probes: cwd=#{Dir.pwd} ruby=#{RUBY_VERSION} ovallsp=#{Ovallsp::VERSION}"
RESULTS = {runtime: {ruby: RUBY_VERSION, ovallsp: Ovallsp::VERSION}}
LOGGER = Logger.new(File::NULL)

def document(source, uri = 'file:///review.rb', version: 1)
  Ovallsp::TextDocument.new(uri: uri, text: source, version: version, language_id: 'ruby')
end

def diagnose(source, signatures, mode: :safe)
  stack = Ovallsp::AnalysisStack.build(signatures: signatures)
  doc = document(source)
  stack.replace_file(Ovallsp::ParserService.new.summarize(doc))
  context = stack.semantic_context(route_registry: Ovallsp::Routes::RouteRegistry.new)
  Ovallsp::Diagnostics::Engine.new.analyze(document: doc, semantic_context: context, mode: mode)
    .map { |f| {code: f.code, message: f.message, line: f.range[:start][:line] + 1} }
end

def messages(output)
  reader = Ovallsp::IO::FramedReader.new(StringIO.new(output.string))
  result = []
  loop { result << reader.read_message }
rescue Ovallsp::IO::FramedReader::EOF
  result
end

def with_server(root)
  output = StringIO.new
  server = Ovallsp::Server.new(input: StringIO.new, output: output, logger: LOGGER, workspace_root: root)
  yield server, output
ensure
  server&.send(:shutdown_background_tasks)
end

def open_doc(server, uri, source)
  server.send(:handle_did_open, {textDocument: {uri: uri, text: source, version: 1, languageId: 'ruby'}})
  server.send(:drain_settled_analyses)
end

def rename(server, uri, source, old, new_name)
  offset = source.index(old)
  position = document(source).char_offset_to_position(offset)
  edit = server.send(:rename_result, {textDocument: {uri: uri}, position: position, newName: new_name})
  return {accepted: false} unless edit
  updated = source.dup
  edits = edit.fetch(:changes).fetch(uri, [])
  doc = document(source)
  edits.sort_by { |e| doc.position_to_char_offset(e[:range][:start]) }.reverse_each do |e|
    from = doc.position_to_char_offset(e[:range][:start])
    to = doc.position_to_char_offset(e[:range][:end])
    updated[from...to] = e[:newText]
  end
  {accepted: true, source: updated, parses: Prism.parse(updated).success?}
end

Dir.mktmpdir('ovallsp-review-probes-') do |root|
  ENV['XDG_CACHE_HOME'] = File.join(root, 'cache')
  signatures = Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: root) }
  fixtures = {
    explicit_guard: "class Guarded\n def go\n  optional if self.respond_to?(:optional)\n end\nend\n",
    bare_guard: "class Guarded\n def go\n  optional if respond_to?(:optional)\n end\nend\n",
    guard_control: "class Unrelated\n def go = absent\nend\n",
    guard_leaks: "class Guarded\n def go\n  absent if respond_to?(:absent)\n end\nend\nclass Unrelated\n def go = absent\nend\n",
    missing_keyword: "class Keyword\n def take(required:); end\n def go = take\nend\n",
    extra_keyword: "class Keyword\n def take(required:); end\n def go = take(required: 1, extra: 2)\nend\n",
    positional_control: "class Keyword\n def take(value); end\n def go = take\nend\n",
    primitive_typo: "class Primitive\n def go = 'hello'.uppcase\nend\n",
    custom_typo: "class Custom\n def go = uppcase\nend\n",
    inherited_constant: "class Parent\n LIMIT = 3\nend\nclass Child < Parent; end\nChild::LIMIT\n",
    constant_control: "class Parent\n LIMIT = 3\nend\nParent::LIMIT\n",
    unrelated_constant: "module Foreign\n LIMIT = 3\nend\nclass Consumer\n def go = LIMIT\nend\n",
    missing_constant: "class Consumer\n def go = LIMIT\nend\n",
    module_typo: "module Helper\n def self.go = typo\nend\n"
  }
  fixtures.each { |name, source| RESULTS[name] = {source: source, findings: diagnose(source, signatures, mode: :standard)} }
  {explicit_guard: 'Guarded.new.go', bare_guard: 'Guarded.new.go', guard_leaks: 'Unrelated.new.go',
   missing_keyword: 'Keyword.new.go', extra_keyword: 'Keyword.new.go', positional_control: 'Keyword.new.go',
   primitive_typo: 'Primitive.new.go', custom_typo: 'Custom.new.go', inherited_constant: 'Child::LIMIT',
   unrelated_constant: 'Consumer.new.go', missing_constant: 'Consumer.new.go', module_typo: 'Helper.go'
  }.each do |name, expression|
    begin
      value = Module.new.module_eval(fixtures.fetch(name) + "\n" + expression)
      RESULTS[name][:ruby_result] = value
    rescue StandardError => error
      RESULTS[name][:ruby_error] = error.class.name
    end
  end

  with_server(root) do |server, out|
    uri = Ovallsp::UriUtil.from_path(File.join(root, 'rename.rb'))
    source = "class Renamed\n def hello; 1; end\n def go = hello\nend\n"
    open_doc(server, uri, source)
    %w[world world! world? world= end].each { |name| RESULTS["rename_#{name}"] = rename(server, uri, source, 'hello', name) }
  end

  with_server(root) do |server, out|
    uri = Ovallsp::UriUtil.from_path(File.join(root, 'override.rb'))
    source = "class Parent\n def hello = 1\nend\nclass Child < Parent\n def hello = super + 1\nend\nclass Consumer\n def go = Child.new.hello\nend\n"
    open_doc(server, uri, source)
    RESULTS[:override_rename] = rename(server, uri, source, 'hello', 'world')
    [[:before, source], [:after, RESULTS[:override_rename][:source]]].each do |label, text|
      begin
        RESULTS[:override_rename][label] = Module.new.module_eval(text + "\nConsumer.new.go")
      rescue StandardError, SyntaxError => error
        RESULTS[:override_rename][label] = error.class.name
      end
    end
  end

  # Hold the initial source inside ColdIndexer while a newer watcher read lands.
  path = File.join(root, 'cold.rb'); uri = Ovallsp::UriUtil.from_path(path)
  File.write(path, 'class OldVersion; end')
  index = Ovallsp::WorkspaceIndex.new
  parser = Ovallsp::ParserService.new
  cold = Ovallsp::ColdIndexer.new(root: root, parser_service: parser, workspace_index: index,
    document_store: Ovallsp::DocumentStore.new, logger: LOGGER)
  cold.define_singleton_method(:source_for) do |p|
    old = super(p)
    File.write(p, 'class NewVersion; end')
    seq = index.next_read_sequence
    fresh = parser.summarize(document(File.read(p), uri, version: nil)).with(source: :disk, read_sequence: seq)
    index.replace_file(fresh)
    old
  end
  cold.run
  RESULTS[:cold_race] = {disk: File.read(path), indexed: index.declarations_for_uri(uri).map { |d| d.symbol_id.name }}

  # A normal dependent file does not get a new publish when its callee changes.
  with_server(root) do |server, out|
    target_uri = Ovallsp::UriUtil.from_path(File.join(root, 'target.rb'))
    use_uri = Ovallsp::UriUtil.from_path(File.join(root, 'use.rb'))
    open_doc(server, target_uri, "class Target\n def take(x); end\nend\n")
    use = "class Consumer\n def go = Target.new.take(1)\nend\n"
    open_doc(server, use_uri, use)
    before = messages(out).count { |m| m.dig(:params, :uri) == use_uri }
    server.send(:handle_did_change, {textDocument: {uri: target_uri, version: 2}, contentChanges: [{text: "class Target\n def take(x,y); end\nend\n"}]})
    server.send(:drain_settled_analyses)
    after = messages(out).count { |m| m.dig(:params, :uri) == use_uri }
    server.send(:publish_diagnostics, server.instance_variable_get(:@document_store).fetch(uri: use_uri))
    forced = messages(out).select { |m| m.dig(:params, :uri) == use_uri }.last.dig(:params, :diagnostics)
    RESULTS[:dependent_refresh] = {published_before: before, published_after: after, forced_diagnostics: forced}
  end

  # Watcher signatures reload, but no diagnostics publication is scheduled.
  sig_dir = File.join(root, 'sig'); FileUtils.mkdir_p(sig_dir)
  sig_path = File.join(sig_dir, 'typed.rbs')
  File.write(sig_path, "class Typed\n def take: (Integer) -> void\nend\n")
  with_server(root) do |server, out|
    uri = Ovallsp::UriUtil.from_path(File.join(root, 'typed.rb'))
    open_doc(server, uri, "class Typed\n def take(x); end\n def go = take(1)\nend\n")
    before = messages(out).count { |m| m.dig(:params, :uri) == uri }
    File.write(sig_path, "class Typed\n def take: (String) -> void\nend\n")
    server.send(:handle_did_change_watched_files, {changes: [{uri: Ovallsp::UriUtil.from_path(sig_path), type: 2}]})
    server.send(:drain_settled_analyses)
    after = messages(out).count { |m| m.dig(:params, :uri) == uri }
    server.send(:publish_diagnostics, server.instance_variable_get(:@document_store).fetch(uri: uri))
    forced = messages(out).select { |m| m.dig(:params, :uri) == uri }.last.dig(:params, :diagnostics)
    RESULTS[:signature_refresh] = {published_before: before, published_after: after, forced_diagnostics: forced}
  end

  # The disk path has no document-version or analysis-generation rejection.
  with_server(root) do |server, out|
    uri = Ovallsp::UriUtil.from_path(File.join(root, 'stale.rb'))
    range = {start: {line: 0, character: 0}, end: {line: 0, character: 1}}
    finding = Ovallsp::Diagnostics::Finding.new(code: 'unknown-method', message: 'old answer', range: range,
      severity: :warning, confidence: :high, generation: 1)
    old = document('old', uri, version: nil)
    newer = document('new', uri, version: nil)
    server.send(:publish_findings, uri, [], document: newer)
    accepted = server.send(:publish_findings, uri, [finding], document: old)
    RESULTS[:disk_stale_publish] = {old_accepted: accepted, final: messages(out).last.dig(:params, :diagnostics)}
    server.send(:clear_findings, uri)
    accepted_after_clear = server.send(:publish_findings, uri, [finding], document: old)
    RESULTS[:disk_after_clear] = {old_accepted: accepted_after_clear}
  end
  # A file symlink rejected by the cold scan is accepted by the watcher.
  Dir.mktmpdir('ovallsp-review-outside-') do |outside|
    external = File.join(outside, 'outside.rb')
    File.write(external, 'class OutsideSentinel; def secret = 17; end')
    link = File.join(root, 'linked.rb'); File.symlink(external, link)
    uri = Ovallsp::UriUtil.from_path(link)
    isolated = Ovallsp::WorkspaceIndex.new
    Ovallsp::ColdIndexer.new(root: root, parser_service: parser, workspace_index: isolated,
      document_store: Ovallsp::DocumentStore.new, logger: LOGGER).run
    cold_names = isolated.declarations_for_uri(uri).map { |d| d.symbol_id.name }
    with_server(root) do |server, out|
      server.send(:handle_did_change_watched_files, {changes: [{uri: uri, type: 1}]})
      watcher_names = server.instance_variable_get(:@workspace_index).declarations_for_uri(uri).map { |d| d.symbol_id.name }
      RESULTS[:watcher_escape] = {cold_names: cold_names, watcher_names: watcher_names}
    end
  end

  # Backslash is a filename character on the reviewed POSIX host.
  path = File.join(root, 'one\\two.rb')
  uri = Ovallsp::UriUtil.from_path(path)
  RESULTS[:posix_uri] = {filename: File.basename(path), roundtrip_filename: File.basename(Ovallsp::UriUtil.to_path(uri)), roundtrips: Ovallsp::UriUtil.to_path(uri) == path}

  with_server(root) do |server, out|
    uri = Ovallsp::UriUtil.from_path(File.join(root, 'completion.rb'))
    source = "class Completion\n def take(required:); end\n def go\n  item = Completion.new\n  item.ta\n end\nend\n"
    open_doc(server, uri, source)
    items = server.send(:completion_result, {textDocument: {uri: uri}, position: {line: 4, character: 9}})[:items]
    RESULTS[:keyword_completion] = items.find { |item| item[:label] == 'take' }
  end

  # RBS and RBI location URIs should name the file even when the root contains '#'.
  sig_root = File.join(root, 'project#one'); FileUtils.mkdir_p(File.join(sig_root, 'sig'))
  File.write(File.join(sig_root, 'sig', 'location.rbs'), "class LocationRbs\n def take: () -> Integer\nend\n")
  File.write(File.join(sig_root, 'sig', 'location.rbi'), "class LocationRbi\n sig { returns(Integer) }\n def take; end\nend\n")
  env = Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: sig_root) }
  %w[LocationRbs LocationRbi].each do |owner|
    sid = Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::#{owner}", name: 'take', discriminator: nil)
    signature = env.method_signatures(sid)
    uri = signature&.location&.fetch(:uri)
    RESULTS[owner] = {uri_suffix: uri&.split('/').last(3)&.join('/'), decoded_exists: uri && File.file?(Ovallsp::UriUtil.to_path(uri).to_s)}
  end

end
puts JSON.pretty_generate(RESULTS)
