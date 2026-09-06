# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# **The read order and the sequence number disagreed.**
#
# `read_sequence` exists so that two disk reads of one file settle by
# *which read happened first* -- `WorkspaceIndex#stale?` compares them and
# keeps the higher. `Server#reindex_from_disk` takes its number before
# reading, which makes the number mean "when this read started".
# `ColdIndexer#index_file` took it *after*, which makes it mean "when this
# read finished" -- and the two are not the same order.
#
# So: the first index starts reading a file and is slow; the file changes;
# the watcher reads the new content and registers it; the first index then
# finishes, takes a *higher* number than the watcher did, and overwrites
# the newer content with the older. The index then answers from content
# that is not on disk, until something else happens to that file.
#
# This is a controlled interleaving, not a frequency measurement: what it
# establishes is that a legal ordering breaks the invariant. Found by the
# 2026-09-05 critical review, R04.
RSpec.describe Ovallsp::ColdIndexer, "the order read_sequence records" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:document_store) { Ovallsp::DocumentStore.new }
  let(:logger) { Ovallsp::Logger.new(io: StringIO.new) }

  def declared?(name)
    !workspace_index.resolve_type_name(name).nil?
  end

  # A parser that blocks in the middle of the cold read, so the "watcher"
  # read below lands between the cold read's start and its finish. A
  # barrier rather than a sleep: the ordering is asserted, not raced for.
  def parser_that_pauses_once(gate)
    real = Ovallsp::ParserService.new
    parser = Object.new
    parser.define_singleton_method(:summarize) do |document|
      gate.call
      real.summarize(document)
    end
    parser
  end

  it "keeps the newer content when a slow first read finishes last" do
    Dir.mktmpdir do |root|
      path = File.join(root, "a.rb")
      File.write(path, "class OldVersion\nend\n")
      uri = Ovallsp::UriUtil.from_path(path)

      released = false
      gate = lambda do
        next if released

        released = true
        # The watcher's read of the *new* content, entirely inside the
        # cold read's own window.
        File.write(path, "class NewVersion\nend\n")
        sequence = workspace_index.next_read_sequence
        document = Ovallsp::TextDocument.new(uri: uri, text: File.read(path), version: nil, language_id: "ruby")
        summary = Ovallsp::ParserService.new.summarize(document).with(source: :disk, read_sequence: sequence)
        workspace_index.replace_file(summary)
      end

      described_class.new(root: root, parser_service: parser_that_pauses_once(gate),
                          workspace_index: workspace_index, document_store: document_store,
                          logger: logger).run

      expect(declared?("NewVersion")).to be(true)
      expect(declared?("OldVersion")).to be(false)
    end
  end

  # **The control.** With nothing racing it, the first index still indexes
  # what it read -- so the example above is the ordering being respected,
  # not the cold index being disabled.
  it "still indexes an ordinary file with nothing racing it" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "a.rb"), "class Ordinary\nend\n")

      described_class.new(root: root, parser_service: Ovallsp::ParserService.new,
                          workspace_index: workspace_index, document_store: document_store,
                          logger: logger).run

      expect(declared?("Ordinary")).to be(true)
    end
  end
end
