# frozen_string_literal: true

require_relative "text_document"

module Ovallsp
  # Holds all currently open documents for a single workspace folder's Core
  # Server process. Writes happen on the dispatch thread only; background
  # threads read. What makes that safe is that a `TextDocument` is an
  # immutable snapshot and `#change` swaps the hash entry rather than
  # editing in place, so a reader mid-swap holds a whole document rather
  # than a half-written one.
  #
  # This note used to cite `docs/design/docs/02-architecture.md`'s
  # threading section for "callers serialize mutations onto the main
  # thread" -- a section that said the index is committed on the main
  # thread while HEAD had been committing from background threads under a
  # mutex for several releases. Both were corrected together in 0.2.7,
  # and `docs/DOCUMENTATION_MAP.md` gained the row that pairs them.
  class DocumentStore
    class UnknownDocumentError < StandardError
      def initialize(uri)
        super("no open document for #{uri}")
      end
    end

    def initialize
      @documents = {}
    end

    def open(uri:, text:, version:, language_id:)
      @documents[uri] = TextDocument.new(uri: uri, text: text, version: version, language_id: language_id)
    end

    # Builds the new document and swaps the entry -- one reference
    # assignment, so a reader holding the old one keeps a document whose
    # text, version and offsets all belong together. `TextDocument` is a
    # frozen snapshot for that reason (029's M-2); this is the only place
    # that calls its `#with_*` builders.
    #
    # The intermediate documents from a multi-change batch are never
    # stored: a reader sees the state before the batch or after it, not a
    # half-applied version of it.
    def change(uri:, version:, changes:)
      doc = @documents.fetch(uri) { raise UnknownDocumentError, uri }

      updated = changes.reduce(doc) do |current, change|
        if change.key?(:range) && change[:range]
          current.with_incremental_change(range: change.fetch(:range), new_text: change.fetch(:text),
                                          version: version)
        else
          current.with_full_change(text: change.fetch(:text), version: version)
        end
      end

      @documents[uri] = updated
    end

    def close(uri:)
      @documents.delete(uri)
    end

    def fetch(uri:)
      @documents[uri]
    end

    # Every document the editor currently has open. Copied, so a caller
    # iterating it (republishing diagnostics, for one) cannot be caught
    # out by a didClose arriving mid-loop.
    def open_documents
      @documents.values.dup
    end
  end
end
