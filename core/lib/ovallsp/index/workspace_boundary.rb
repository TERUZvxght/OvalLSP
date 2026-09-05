# frozen_string_literal: true

module Ovallsp
  module Index
    # **Which files may enter the static index**, asked in one place
    # because it was asked in two and answered differently.
    #
    # `ColdIndexer#index_file` resolves a path and refuses one that leaves
    # the workspace root -- Task 008.6 wrote that after finding both a
    # symlinked *directory* and a symlinked *file* reaching outside. The
    # watcher path never learned it: `Server#reindex_from_disk` checks
    # `File.file?`, which follows the link, and reads what it finds. So a
    # `linked.rb` inside the workspace pointing outside was refused at
    # startup and accepted on the next change notification.
    #
    # Fixing `ColdIndexer` alone would leave the next entrance free to
    # compute its own answer, which is the shape `024.173` records and the
    # 2026-09-05 critical review (R11) names directly.
    #
    # **This is about automatic indexing.** A file the user opened is
    # theirs to open wherever it is, and `didOpen` carries its text rather
    # than a path to read. What this governs is the two paths that go
    # looking: the first walk, and the watcher.
    module WorkspaceBoundary
      module_function

      # `true` when `path` really is under `root`, with every symlink on
      # the way resolved. A `nil` root is a session with no folder open --
      # there is no boundary to enforce, and refusing everything would
      # make such a session index nothing.
      #
      # The root is resolved too: macOS puts `/tmp` behind a link, and
      # comparing a resolved path against an unresolved root refuses every
      # file there.
      def inside?(root:, path:)
        return true if root.nil?
        return false if path.nil?

        real_root = File.realpath(root)
        real_path = File.realpath(path)
        real_path == real_root || real_path.start_with?("#{real_root}#{File::SEPARATOR}")
      rescue SystemCallError
        # A path that cannot be resolved -- gone, a broken link, a loop --
        # is not one to read. `ColdIndexer#safe_realpath` named the same
        # three errnos; `SystemCallError` is their family, and the reason
        # to widen it is that any failed syscall here means the same thing.
        false
      end
    end
  end
end
