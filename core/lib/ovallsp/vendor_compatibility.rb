# frozen_string_literal: true

require "json"

module Ovallsp
  # ADR-0005: a packaged VSIX's `vendor/bundle` (ADR-0004) contains
  # *native* extensions (prism, rbs' own rbs_extension) built for whatever
  # Ruby engine/version/OS/CPU ran `bundle install` at packaging time
  # (`vscode/scripts/copy-core.js`). Loading them under a different Ruby
  # doesn't degrade gracefully -- it produces an undiagnosable crash deep
  # inside the process (`TypeError: superclass mismatch for class
  # Prism::ParseResult`, reproduced across a Ruby engine/version/platform
  # mismatch), because a native extension compiled against one Ruby's ABI
  # is simply the wrong machine code for another.
  #
  # This module is the one place that question gets asked, so `bin/ovallsp`
  # can refuse to add an incompatible vendor directory to `$LOAD_PATH` at
  # all, with a clear, actionable diagnostic, rather than adding it and
  # letting the mismatch surface however Ruby's own loader happens to
  # discover it.
  module VendorCompatibility
    Result = Struct.new(:compatible?, :reason, keyword_init: true)

    module_function

    # `manifest_path` is `vscode/scripts/copy-core.js`'s own
    # `PLATFORM_MANIFEST.json`, written alongside `vendor/bundle` at
    # packaging time. Two cases are treated as "compatible" without
    # actually comparing anything, both deliberately permissive rather
    # than fail-closed:
    #
    # - No `vendor_root` at all: there's nothing to protect against
    #   loading incompatibly -- this is the plain dev-checkout case
    #   `bin/ovallsp`'s own bootstrap has always supported, with no
    #   vendoring involved.
    # - A `vendor_root` with no manifest: an older VSIX, packaged before
    #   this check existed. Refusing to load it would regress every
    #   already-built artifact's own working behavior for a check that
    #   didn't exist when it was built; the manifest's absence carries no
    #   information about compatibility either way.
    #
    # Anything else -- a manifest that parses but doesn't match, or one
    # that fails to parse at all -- is treated as **incompatible**,
    # deliberately fail-closed: this module exists precisely to avoid an
    # unconditional load, and a manifest Ruby can't even read is exactly
    # as untrustworthy as one that says "no match".
    def check(manifest_path:, vendor_root:, ruby_engine: RUBY_ENGINE, ruby_version: RUBY_VERSION,
             ruby_platform: RUBY_PLATFORM)
      return Result.new(compatible?: true, reason: nil) unless Dir.exist?(vendor_root)
      return Result.new(compatible?: true, reason: nil) unless File.file?(manifest_path)

      manifest = JSON.parse(File.read(manifest_path))
      current_major_minor = ruby_version.split(".").first(2).join(".")

      if manifest["rubyEngine"] == ruby_engine &&
         manifest["rubyVersionMajorMinor"] == current_major_minor &&
         manifest["rubyPlatform"] == ruby_platform
        Result.new(compatible?: true, reason: nil)
      else
        Result.new(compatible?: false, reason: mismatch_message(manifest, ruby_engine, current_major_minor, ruby_platform))
      end
    rescue StandardError => e
      Result.new(compatible?: false, reason: "could not read vendor platform manifest (#{e.class}: #{e.message})")
    end

    def mismatch_message(manifest, ruby_engine, current_major_minor, ruby_platform)
      expected = "#{manifest["rubyEngine"]} #{manifest["rubyVersionMajorMinor"]} (#{manifest["rubyPlatform"]})"
      actual = "#{ruby_engine} #{current_major_minor} (#{ruby_platform})"
      <<~MSG.chomp
        bundled native dependencies were built for #{expected}, but the running interpreter is #{actual}. \
        These are incompatible and will not be loaded from vendor/bundle.

        To use OvalLSP with this Ruby, either:
          - install ovallsp's own runtime dependencies for this Ruby yourself (gem install prism rbs), or
          - configure "ovallsp.rubyExecutablePath" in VS Code to point at a #{expected} interpreter \
        matching this VSIX build.

        See docs/design/adrs/0005-platform-scoped-vsix-with-runtime-compatibility-check.md for details.
      MSG
    end
  end
end
