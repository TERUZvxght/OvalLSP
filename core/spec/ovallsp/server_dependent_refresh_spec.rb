# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

# **The index knew, and nothing asked it to say so.**
#
# Change a method's arity in one open file and the caller in another open
# file keeps its old diagnostics. `#apply_file_summary` invalidates the
# method summaries and marks the reference index dirty -- the *engine* can
# tell, and a forced re-analysis proves it: `takes 2 arguments, but 1
# given` appears the moment anything asks. Nothing does, so the warning
# waits for the caller's next edit, and a warning that goes away waits the
# same way.
#
# `#republish_open_diagnostics` already existed. What was missing is
# anything calling it when a *dependency* changed.
#
# **Through the settled-analysis queue**, not immediately: that queue
# exists because analysis is expensive and drains when the input is quiet,
# so a keystroke does not re-analyse every open file. And only when the
# declarations actually changed -- re-indexing a file whose method set is
# the same says nothing about anyone else.
#
# Found by the 2026-09-05 critical review, R05. The reproduction is that
# review's `dependent_refresh` and `signature_refresh` probes, turned into
# assertions.
RSpec.describe Ovallsp::Server, "re-analysis when a dependency changes" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  around do |example|
    Dir.mktmpdir("ovallsp-refresh-") do |root|
      @root = File.realpath(root)
      example.run
    end
  end

  let(:server) do
    described_class.new(input: StringIO.new(""), output: output, logger: logger, workspace_root: @root)
  end

  def uri_for(name) = Ovallsp::UriUtil.from_path(File.join(@root, name))

  def open_doc(name, text)
    path = File.join(@root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    server.send(:handle_did_open,
                { textDocument: { uri: uri_for(name), text: text, version: 1, languageId: "ruby" } })
    # **Drained here**, because `didOpen`'s own publish is queued too:
    # without this every `before` count was zero, and the first example
    # passed on the *opening* publish rather than on a refresh -- an
    # assertion that cannot fail, arriving through the setup.
    server.send(:drain_settled_analyses)
    uri_for(name)
  end

  def publishes_for(target_uri)
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    begin
      loop { messages << reader.read_message }
    rescue Ovallsp::IO::FramedReader::EOF
      nil
    end
    messages.select { |m| m[:method] == "textDocument/publishDiagnostics" && m[:params][:uri] == target_uri }
  end

  it "republishes the caller when the callee's arity changes" do
    target = open_doc("target.rb", "class Target\n  def take(x); end\nend\n")
    use = open_doc("use.rb", "class Consumer\n  def go = Target.new.take(1)\nend\n")
    before = publishes_for(use).length

    server.send(:handle_did_change,
                { textDocument: { uri: target, version: 2 },
                  contentChanges: [{ text: "class Target\n  def take(x, y); end\nend\n" }] })
    server.send(:drain_settled_analyses)

    expect(publishes_for(use).length).to be > before
    expect(publishes_for(use).last[:params][:diagnostics]).not_to be_empty
  end

  # **This passes on the parent tree too**, which a cold review measured:
  # undoing the change republishes because the *edited* file's own path
  # publishes, and the caller's stale warning is then compared against a
  # tree where nothing had put one there. Kept as the round trip it
  # describes, with the count asserted rather than only the content, so it
  # says something the parent does not.
  it "republishes it again when the change is undone" do
    target = open_doc("target.rb", "class Target\n  def take(x); end\nend\n")
    use = open_doc("use.rb", "class Consumer\n  def go = Target.new.take(1)\nend\n")
    before = publishes_for(use).length

    server.send(:handle_did_change,
                { textDocument: { uri: target, version: 2 },
                  contentChanges: [{ text: "class Target\n  def take(x, y); end\nend\n" }] })
    server.send(:drain_settled_analyses)
    server.send(:handle_did_change,
                { textDocument: { uri: target, version: 3 },
                  contentChanges: [{ text: "class Target\n  def take(x); end\nend\n" }] })
    server.send(:drain_settled_analyses)

    expect(publishes_for(use).length).to eq(before + 2)
    expect(publishes_for(use).last[:params][:diagnostics]).to be_empty
  end

  # **The control.** An edit that changes no declaration must not queue
  # every open file: without this, a rule that republished on every
  # re-index would pass both examples above while making each keystroke
  # re-analyse the workspace.
  it "does not republish the caller for an edit that declares nothing new" do
    target = open_doc("target.rb", "class Target\n  def take(x); end\nend\n")
    use = open_doc("use.rb", "class Consumer\n  def go = Target.new.take(1)\nend\n")
    before = publishes_for(use).length

    server.send(:handle_did_change,
                { textDocument: { uri: target, version: 2 },
                  contentChanges: [{ text: "class Target\n  def take(x); 1; end\nend\n" }] })
    server.send(:drain_settled_analyses)

    expect(publishes_for(use).length).to eq(before)
  end

  # The file that was edited is republished by the ordinary path, which
  # this must not disturb.
  it "still republishes the file that was edited" do
    target = open_doc("target.rb", "class Target\n  def take(x); end\nend\n")
    before = publishes_for(target).length

    server.send(:handle_did_change,
                { textDocument: { uri: target, version: 2 },
                  contentChanges: [{ text: "class Target\n  def take(x, y); end\nend\n" }] })
    server.send(:drain_settled_analyses)

    expect(publishes_for(target).length).to be > before
  end

  # The same gap on the signature side: `sig/` reloads and the summary
  # cache is emptied, and nothing publishes -- so an open file's
  # argument-type report waited for that file's own next edit. A signature
  # change has no bounded dependency set, so every open document is
  # queued.
  describe "a project signature that changes" do
    it "republishes an open file when its RBS changes under it" do
      FileUtils.mkdir_p(File.join(@root, "sig"))
      sig = File.join(@root, "sig", "typed.rbs")
      File.write(sig, "class Typed\n  def take: (Integer) -> void\nend\n")
      use = open_doc("typed.rb", "class Typed\n  def take(x); end\n  def go = take(1)\nend\n")
      before = publishes_for(use).length

      File.write(sig, "class Typed\n  def take: (String) -> void\nend\n")
      server.send(:handle_did_change_watched_files,
                  { changes: [{ uri: Ovallsp::UriUtil.from_path(sig), type: 2 }] })
      server.send(:drain_settled_analyses)

      expect(publishes_for(use).length).to be > before
    end

    # The control: a watched change that is not a signature must not queue
    # every open file.
    it "does not republish every open file for an unrelated watched change" do
      use = open_doc("typed.rb", "class Typed\n  def take(x); end\nend\n")
      other = File.join(@root, "notes.txt")
      File.write(other, "hello")
      before = publishes_for(use).length

      server.send(:handle_did_change_watched_files,
                  { changes: [{ uri: Ovallsp::UriUtil.from_path(other), type: 2 }] })
      server.send(:drain_settled_analyses)

      expect(publishes_for(use).length).to eq(before)
    end
  end

  # **What a caller depends on is more than the declarations.** A
  # superclass changed, an `include` removed or an `alias_method` deleted
  # alters what a caller may call while every declaration in the file is
  # byte-identical -- a cold review measured all three leaving the caller
  # stale, with a forced re-analysis showing the report the whole time.
  describe "a change that is not a declaration" do
    it "republishes the caller when the callee's superclass changes" do
      open_doc("base.rb", "class Base\n  def helper; end\nend\nclass Other\nend\n")
      target = open_doc("target.rb", "class Target < Base\nend\n")
      use = open_doc("use.rb", "class Consumer\n  def go = Target.new.helper\nend\n")
      before = publishes_for(use).length

      server.send(:handle_did_change,
                  { textDocument: { uri: target, version: 2 },
                    contentChanges: [{ text: "class Target < Other\nend\n" }] })
      server.send(:drain_settled_analyses)

      expect(publishes_for(use).length).to be > before
    end

    it "republishes the caller when an include is removed" do
      open_doc("mixin.rb", "module Mixin\n  def m; end\nend\n")
      target = open_doc("target.rb", "class Target\n  include Mixin\nend\n")
      use = open_doc("use.rb", "class Consumer\n  def go = Target.new.m\nend\n")
      before = publishes_for(use).length

      server.send(:handle_did_change,
                  { textDocument: { uri: target, version: 2 },
                    contentChanges: [{ text: "class Target\nend\n" }] })
      server.send(:drain_settled_analyses)

      expect(publishes_for(use).length).to be > before
    end

    it "republishes the caller when an alias is removed" do
      target = open_doc("target.rb", "class Target\n  def take; end\n  alias_method :grab, :take\nend\n")
      use = open_doc("use.rb", "class Consumer\n  def go = Target.new.grab\nend\n")
      before = publishes_for(use).length

      server.send(:handle_did_change,
                  { textDocument: { uri: target, version: 2 },
                    contentChanges: [{ text: "class Target\n  def take; end\nend\n" }] })
      server.send(:drain_settled_analyses)

      expect(publishes_for(use).length).to be > before
    end
  end

  # **The first index does not queue dependents.** A file it has not seen
  # has no previous declarations, so every cold summary with a `def` in it
  # read as a declaration change -- and `#run` drains whenever the input
  # is quiet, so during a cold index of a large repository every client
  # message cost a full re-analysis of everything open. A regression this
  # queueing introduced, found by cold review.
  it "does not queue open documents for each file the first index reads" do
    use = open_doc("use.rb", "class Consumer\n  def go = 1\nend\n")
    before = publishes_for(use).length

    3.times do |n|
      text = "class Cold#{n}\n  def m#{n}; end\nend\n"
      path = File.join(@root, "cold#{n}.rb")
      File.write(path, text)
      document = Ovallsp::TextDocument.new(uri: Ovallsp::UriUtil.from_path(path), text: text,
                                           version: nil, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document).with(source: :disk, read_sequence: n + 1)
      server.send(:apply_cold_summary, document.uri, document, summary)
      server.send(:drain_settled_analyses)
    end

    expect(publishes_for(use).length).to eq(before)
  end

  # Its control: an *edit* to an open file still queues, so the example
  # above is the cold path being exempt and not the queueing being dead.
  it "still queues for an ordinary edit while the same files exist" do
    target = open_doc("target.rb", "class Target\n  def take(x); end\nend\n")
    use = open_doc("use.rb", "class Consumer\n  def go = Target.new.take(1)\nend\n")
    before = publishes_for(use).length

    server.send(:handle_did_change,
                { textDocument: { uri: target, version: 2 },
                  contentChanges: [{ text: "class Target\n  def take(x, y); end\nend\n" }] })
    server.send(:drain_settled_analyses)

    expect(publishes_for(use).length).to be > before
  end
end
