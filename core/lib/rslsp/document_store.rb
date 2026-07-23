# frozen_string_literal: true

require_relative "text_document"

module Rslsp
  # Holds all currently open documents for a single workspace folder's Core
  # Server process. Not thread-safe by itself; callers are expected to
  # serialize mutations onto the main thread per docs/02-architecture.md ("state
  # generation" section).
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

    def change(uri:, version:, changes:)
      doc = @documents.fetch(uri) { raise UnknownDocumentError, uri }

      changes.each do |change|
        if change.key?(:range) && change[:range]
          doc.apply_incremental_change(range: change.fetch(:range), new_text: change.fetch(:text), version: version)
        else
          doc.apply_full_change(text: change.fetch(:text), version: version)
        end
      end

      doc
    end

    def close(uri:)
      @documents.delete(uri)
    end

    def fetch(uri:)
      @documents[uri]
    end
  end
end
