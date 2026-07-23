# frozen_string_literal: true

module Rslsp
  module Index
    # Per-document extraction result. Never holds AST node objects — only
    # normalized declarations and diagnostics, so it can outlive the parse
    # that produced it (docs/02-architecture.md "Incremental Index").
    FileSummary = Data.define(:uri, :content_hash, :document_version, :declarations, :diagnostics)
  end
end
