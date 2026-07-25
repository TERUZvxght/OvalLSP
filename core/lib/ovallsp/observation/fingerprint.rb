# frozen_string_literal: true

require "digest"

module Ovallsp
  module Observation
    # One algorithm, used on both sides of the fork boundary, so a
    # fingerprint the Collector computed inside the isolated observation
    # runner (from a plain file path + line number, all it has) and one
    # Server computes later from a live Declaration (to call
    # Store#invalidate_changed) are actually comparable.
    #
    # Deliberately coarser than "just this one method's own body text":
    # any change anywhere in the file changes its digest, so any edit
    # invalidates every observed method in that file, not just the one
    # actually touched. That's a correctness trade in the safe direction
    # -- "source変更後に古い観測を使用しない" only needs no *false*
    # freshness, never the reverse, and computing a real per-method
    # source span consistently on both sides (parsed once via Prism in
    # Core, but the isolated runner has no Prism dependency of its own by
    # design) would be real added complexity for a difference that only
    # ever shows up as an unnecessary re-observation prompt.
    module Fingerprint
      module_function

      def for_file_and_line(path, line)
        digest = file_digest(path)
        return nil unless digest

        "#{digest}:#{line}"
      end

      # Used when a live open buffer exists for the file -- this
      # codebase's own "Open Buffer優先" rule (WorkspaceIndex, Task
      # 008.6-3) applies here too: an unsaved edit must invalidate stale
      # observed evidence immediately, not only after the next save,
      # which #for_file_and_line's on-disk read alone could never see.
      def for_content_and_line(content, line)
        "#{content_digest(content)}:#{line}"
      end

      def file_digest(path)
        Digest::SHA256.file(path).hexdigest
      rescue StandardError
        nil
      end

      def content_digest(content)
        Digest::SHA256.hexdigest(content)
      end
    end
  end
end
