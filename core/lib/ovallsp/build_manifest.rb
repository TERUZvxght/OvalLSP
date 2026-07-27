# frozen_string_literal: true

require "json"

module Ovallsp
  # Reads the same `PLATFORM_MANIFEST.json` that
  # `vscode/scripts/copy-core.js` writes and `VendorCompatibility` already
  # checks (ADR-0005) -- extended (Task 023.2) to also carry
  # extensionVersion/coreVersion/protocol/build/payloadSha256, so the
  # `initialize` handshake can report a packaged VSIX's actual build
  # identity back to the client without a second, separately-synced file.
  #
  # Returns `nil` for a plain dev checkout (no manifest at all) or a
  # manifest that fails to parse -- both treated the same way
  # `VendorCompatibility` treats them: no information, not an error.
  module BuildManifest
    module_function

    def load(path: default_path)
      return nil unless File.file?(path)

      JSON.parse(File.read(path))
    rescue StandardError
      nil
    end

    def default_path
      File.expand_path("../../PLATFORM_MANIFEST.json", __dir__)
    end
  end
end
