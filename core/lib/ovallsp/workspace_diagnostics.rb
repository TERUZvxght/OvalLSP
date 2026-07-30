# frozen_string_literal: true

module Ovallsp
  # Diagnostics for files nobody has open (0.2.0).
  #
  # Until now `publish_diagnostics` was wired only into didOpen/didChange,
  # on the reasoning that a file with no client-side buffer has nothing to
  # attach the notification to. LSP does not work that way -- a client
  # shows `publishDiagnostics` for any URI in its Problems panel -- so the
  # effect was that a mistake three directories away stayed invisible
  # until somebody happened to open the file.
  #
  # Three properties this has to hold, and they are the whole design:
  #
  # - **Never on the request path.** A pass is O(workspace) and each file
  #   needs the index; running one inline would stall every hover behind
  #   it. Callers hand the work here and it runs on a caller-supplied
  #   background thread.
  # - **Never for an open file.** An open buffer's diagnostics belong to
  #   didOpen/didChange, which knows the buffer's version and its unsaved
  #   text. Answering from disk for the same URI reports on text the user
  #   is not looking at, and races the buffer path for the last word.
  # - **Supersedable.** The pass is re-run whenever the answers could have
  #   changed (the Runtime Agent becoming ready is the big one, since the
  #   unknown-method check defers without it). A newer request must be
  #   able to abandon an older pass mid-flight rather than queue behind it.
  class WorkspaceDiagnostics
    # Bounds one pass, not the workspace: a file this far into the walk is
    # already past the point where a user would have opened it themselves,
    # and an unbounded pass on a monorepo is a background thread that
    # never ends. `truncated?` records that it bit, so a caller can say so
    # rather than quietly under-reporting.
    DEFAULT_MAX_FILES = 2000

    Outcome = Data.define(:analyzed, :truncated, :superseded)

    # `analyze` receives a TextDocument and returns its findings.
    # `publish` receives (uri, findings). Both are the Server's, injected
    # rather than reached for, so a pass can be tested without a Server.
    def initialize(analyze:, publish:, open_in_buffer:, logger:, max_files: DEFAULT_MAX_FILES)
      @analyze = analyze
      @publish = publish
      @open = open_in_buffer
      @logger = logger
      @max_files = max_files
      @generation = 0
      @closed = false
      @mutex = Mutex.new
    end

    # Invalidates any pass currently running and returns the token the new
    # one must carry. Called on the dispatch thread; the pass itself is
    # not.
    def begin_pass
      @mutex.synchronize { @generation += 1 }
    end

    # Invalidates the running pass and refuses every later one. Shutdown
    # calls this rather than `begin_pass`: a pass is *started* from inside
    # another background thread (the cold index, on completion), so a
    # plain `begin_pass` at shutdown could be undone a moment later by
    # that thread starting a fresh, valid pass -- which then had to be
    # killed by the join instead of returning.
    def close
      @mutex.synchronize do
        @generation += 1
        @closed = true
      end
    end

    def current?(generation)
      @mutex.synchronize { !@closed && @generation == generation }
    end

    # Analyzes and publishes for each of `uris`, skipping any that is open
    # in a buffer. Checks `current?` between files rather than only at the
    # start: a pass over a large workspace outlives several reasons to
    # restart it, and finishing a stale one means publishing answers that
    # were already known to be out of date.
    def run(uris, generation)
      return Outcome.new(analyzed: 0, truncated: false, superseded: true) unless current?(generation)

      analyzed = 0
      truncated = false

      uris.each do |uri|
        return Outcome.new(analyzed: analyzed, truncated: truncated, superseded: true) unless current?(generation)

        if analyzed >= @max_files
          truncated = true
          break
        end

        # Open files are skipped by `publish_for` itself, which has to
        # decide it anyway for the single-file path. A second check here
        # would be two statements of one rule, and neither could be
        # removed without the other silently covering for it.
        analyzed += 1 if publish_for(uri)
      end

      Outcome.new(analyzed: analyzed, truncated: truncated, superseded: false)
    end

    # One file. Also the whole of what a disk-change notification needs,
    # which is why it is public: a watcher reporting one changed file
    # should not start a workspace pass to report on it.
    def publish_for(uri)
      return false if closed?

      path = UriUtil.to_path(uri)
      # Asked before reading rather than left to the rescue below: a URI
      # with no file behind it is the ordinary result of a file being
      # deleted between the index recording it and this pass reaching it,
      # and logging an error for each one turns a normal race into a wall
      # of noise that hides the failures worth reading.
      return false unless path && File.file?(path)
      return false if @open.call(uri)

      document = TextDocument.new(uri: uri, text: File.read(path, encoding: Encoding::UTF_8),
                                   version: nil, language_id: language_id_for(path))
      findings = @analyze.call(document)
      # Asked again after the analysis, which takes long enough for a
      # `didOpen` to arrive inside it. The buffer path publishes correct
      # diagnostics for that URI on the dispatch thread, and this would
      # then overwrite them with disk-derived ones -- for text the user is
      # not looking at, with nothing to correct it until the next edit.
      return false if @open.call(uri)

      @publish.call(uri, findings)
      true
    rescue StandardError => e
      # One unreadable or unparseable file must not end the pass: the
      # other several hundred are still worth reporting on.
      @logger.error("failed to compute workspace diagnostics for #{uri}: #{e.class}: #{e.message}")
      false
    end

    def closed?
      @mutex.synchronize { @closed }
    end

    private

    def language_id_for(path)
      File.extname(path) == ".erb" ? "erb" : "ruby"
    end
  end
end
