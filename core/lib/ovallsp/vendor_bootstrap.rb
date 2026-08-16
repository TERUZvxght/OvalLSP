# frozen_string_literal: true

require "rbconfig"

require_relative "vendor_compatibility"

module Ovallsp
  # ADR-0004/0005: `bin/ovallsp` puts a packaged VSIX's vendored gems on
  # `$LOAD_PATH` without Bundler, because whatever Ruby `resolveRuby`
  # picked may not have Bundler at all. This is that bootstrap, extracted
  # so it can be tested -- the script itself runs only as a subprocess,
  # and the one integration spec that drives it cannot construct the
  # payload layouts that matter.
  #
  # `VendorCompatibility` answers *whether* a payload may be loaded.
  # This answers *which directories that permission covers*, which is a
  # separate question and used to have no answer at all: the script
  # globbed `vendor/bundle/**/gems/*/lib`, and Bundler lays a payload out
  # one directory per ABI (`ruby/3.4.0`, `ruby/4.0.0`). A packaged VSIX
  # has exactly one, so the glob was right by accident. A development
  # checkout that has run `bundle install` under two Rubies has one each,
  # and the glob put the other ABI's native extensions ahead of this
  # interpreter's own -- `LoadError: linked to incompatible libruby`,
  # from the very payload ADR-0005 exists to keep off `$LOAD_PATH`.
  #
  # That configuration is not hypothetical: `docs/SUPPORT_MATRIX.md` asks
  # a contributor to run the suite under both 3.4 and 4.0 by hand, and
  # the second `bundle install` is what creates it.
  module VendorBootstrap
    module_function

    # Returns the directories added, in the order they were added.
    def activate!(vendor_root:, manifest_path:, load_path: $LOAD_PATH, warner: method(:warn),
                  abi: RbConfig::CONFIG["ruby_version"], engine_scope: RUBY_ENGINE)
      return [] unless Dir.exist?(vendor_root)

      compatibility = VendorCompatibility.check(manifest_path: manifest_path, vendor_root: vendor_root)
      unless compatibility.compatible?
        warner.call("ovallsp: #{compatibility.reason}")
        return []
      end

      # No ABI-matching directory means the payload was built for a Ruby
      # this one cannot load. That is the same answer as "no payload":
      # add nothing, and let ordinary gem resolution decide. Falling back
      # to the unscoped glob here would reinstate the crash above for
      # exactly the case the manifest could not catch -- a payload with
      # no manifest, which `VendorCompatibility` deliberately permits.
      Dir.glob(File.join(vendor_root, engine_scope, abi, "gems", "*", "lib"))
         .each { |lib| load_path.unshift(lib) }
    end
  end
end
