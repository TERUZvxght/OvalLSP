# frozen_string_literal: true

require "json"

require_relative "rslsp/version"
require_relative "rslsp/logger"
require_relative "rslsp/io/framed_reader"
require_relative "rslsp/io/framed_writer"
require_relative "rslsp/text_document"
require_relative "rslsp/document_store"
require_relative "rslsp/index/symbol_id"
require_relative "rslsp/index/parameter"
require_relative "rslsp/index/declaration"
require_relative "rslsp/index/file_summary"
require_relative "rslsp/index/source_location"
require_relative "rslsp/index/document_symbol_builder"
require_relative "rslsp/parser_service"
require_relative "rslsp/workspace_index"
require_relative "rslsp/uri_util"
require_relative "rslsp/types"
require_relative "rslsp/local_inferencer"
require_relative "rslsp/server"

module Rslsp
end
