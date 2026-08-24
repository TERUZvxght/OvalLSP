# frozen_string_literal: true

module Ovallsp
  # Reading a file the editor does not have open.
  #
  # Three unrelated paths need this — hover documentation for a
  # declaration in an unopened file, the cold index, and view inference —
  # and 0.2.16 nearly gave the third its own copy by moving the method
  # out with `Views::ControllerIvars`. One module function, so the three
  # cannot drift about what "not open" means.
  module DocumentFromDisk
    module_function

    def load(uri, logger:)
      path = UriUtil.to_path(uri)
      return nil unless path && File.file?(path)

      TextDocument.new(uri: uri, text: File.read(path, encoding: Encoding::UTF_8),
                       version: nil, language_id: "ruby")
    rescue StandardError => e
      # **Contained**: `nil` is what an unreadable file gives, and every
      # caller already treats a missing document as "cannot say" —
      # documentation shows none, the cold index skips the file, view
      # inference declines the context.
      logger.error("failed to read #{uri} from disk: #{e.class}: #{e.message}")
      nil
    end
  end
end
