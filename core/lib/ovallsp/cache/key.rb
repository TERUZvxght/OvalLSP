# frozen_string_literal: true

require "digest"
require "prism"
require_relative "../version"

module Ovallsp
  module Cache
    # Computes the single digest that names a cache generation's own
    # on-disk directory (Cache::Store) -- everything the design doc lists
    # as required in the key
    # (docs/design/tasks/021-persistent-cache-and-performance.md
    # "Cache keyへ最低限含める") folds into ONE directory name, so a
    # change to any of them (a Ruby upgrade, a `bundle install`, an RBS
    # collection update, a settings change that affects semantics, an
    # OvalLSP schema bump) automatically lands in a *different* directory
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
      #
      # It is not the version that protects the *contents*: see
      # `ovallsp=` below.
      # 2 since 0.2.6, when `FileSummary` gained `open_surface_owners`:
      # a 0.2.5-shaped entry no longer loads at all ("struct size
      # differs"), and `Store#load` rescues that into a silent
      # whole-cache miss against a directory that then lingers.
      # `core/spec/ovallsp/cache/schema_version_spec.rb` is what notices
      # next time -- this constant and that shape are one decision, and
      # keeping them in two files is why the bump was missed.
      # 3 since 0.2.12, when `FileSummary` gained `module_function_names`;
      # 4 in the same release, when it gained `buffer_id` (`024.118`).
      SCHEMA_VERSION = 4

      module_function

      # `ovallsp_version` is in the key because a cache entry is not data,
      # it is the *output of this build's parser*, and the file's own
      # content hash cannot notice that the rules changed. 0.2.1 moved the
      # position a call site records its receiver at -- the release's
      # largest fix -- and for every file already in an upgrading user's
      # cache the old position was served back unchanged: same bytes, same
      # Ruby, same Prism, same `Gemfile.lock`. On a real Rails application
      # that left one wrong diagnostic that survived restarts and
      # `Re-index Workspace` alike, and the only cure was deleting
      # `~/.cache/ovallsp` by hand.
      #
      # `SCHEMA_VERSION` did not cover it and should not: it is about
      # whether an entry can be *loaded*, this is about whether it is
      # still *true*. Keyed on the constant rather than on a remembered
      # bump, so a release cannot forget.
      def workspace_digest(workspace_root:, gemfile_lock_digest: nil, rbs_digest: nil, settings_digest: nil,
                            ruby_version: RUBY_VERSION, prism_version: Prism::VERSION,
                            ovallsp_version: Ovallsp::VERSION)
        components = [
          "schema=#{SCHEMA_VERSION}",
          "ovallsp=#{ovallsp_version}",
          "ruby=#{ruby_version}",
          "prism=#{prism_version}",
          "workspace=#{canonical_root(workspace_root)}",
          "gemfile_lock=#{gemfile_lock_digest}",
          "rbs=#{rbs_digest}",
          "settings=#{settings_digest}"
        ].join("|")
        Digest::SHA256.hexdigest(components)
      end

      # The workspace alone, which names the *directory* every generation
      # for this project lives under. Deliberately not the full digest:
      # that one changes with Ruby, Prism, `Gemfile.lock`, RBS and the
      # OvalLSP version, and a project's cache directory must not move
      # when any of those do -- otherwise pruning cannot tell one
      # project's abandoned generations from another project's live cache,
      # which is what it could not do until 0.2.1.
      def workspace_scope(workspace_root:)
        Digest::SHA256.hexdigest("workspace=#{canonical_root(workspace_root)}")
      end

      def canonical_root(workspace_root)
        File.realpath(workspace_root)
      rescue Errno::ENOENT
        File.expand_path(workspace_root)
      end
    end
  end
end
