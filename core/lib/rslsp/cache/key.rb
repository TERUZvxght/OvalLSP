# frozen_string_literal: true

require "digest"
require "prism"

module Rslsp
  module Cache
    # Computes the single digest that names a cache generation's own
    # on-disk directory (Cache::Store) -- everything the design doc lists
    # as required in the key
    # (docs/design/tasks/021-persistent-cache-and-performance.md
    # "Cache keyへ最低限含める") folds into ONE directory name, so a
    # change to any of them (a Ruby upgrade, a `bundle install`, an RBS
    # collection update, a settings change that affects semantics, an
    # RSLSP schema bump) automatically lands in a *different* directory
    # -- every entry under the old one is simply never looked at again,
    # rather than needing explicit migration/invalidation code for each
    # possible change. Per-*file* staleness within one generation is a
    # separate, cheaper check (Cache::Store, `content_hash` alone) --
    # this key only ever needs to change for something that could affect
    # semantics workspace-wide.
    module Key
      # Bump whenever a FileSummary-reachable shape changes in a way an
      # old cached entry couldn't safely be `Marshal.load`ed back as (a
      # renamed/removed Data field, a changed Declaration/SymbolId
      # shape, ...) -- every entry under the previous schema version's
      # directory is simply abandoned, never migrated.
      SCHEMA_VERSION = 1

      module_function

      def workspace_digest(workspace_root:, gemfile_lock_digest: nil, rbs_digest: nil, settings_digest: nil,
                            ruby_version: RUBY_VERSION, prism_version: Prism::VERSION)
        components = [
          "schema=#{SCHEMA_VERSION}",
          "ruby=#{ruby_version}",
          "prism=#{prism_version}",
          "workspace=#{canonical_root(workspace_root)}",
          "gemfile_lock=#{gemfile_lock_digest}",
          "rbs=#{rbs_digest}",
          "settings=#{settings_digest}"
        ].join("|")
        Digest::SHA256.hexdigest(components)
      end

      def canonical_root(workspace_root)
        File.realpath(workspace_root)
      rescue Errno::ENOENT
        File.expand_path(workspace_root)
      end
    end
  end
end
