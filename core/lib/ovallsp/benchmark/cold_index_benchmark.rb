# frozen_string_literal: true

require "benchmark"
require "fileutils"
require "time"
require "tmpdir"

module Ovallsp
  module Benchmark
    # Measures Cold Index's own cold (no persistent cache) and warm
    # (cache already populated by a prior run) timing against a
    # synthetic, generated corpus -- "benchmark corpus" / "profiling"
    # (docs/design/tasks/021-persistent-cache-and-performance.md).
    # Report-only by design: this never asserts a pass/fail threshold
    # itself ("目標を満たせない場合も数値を隠さず記録する" -- the numbers
    # are always reported, a miss against the design doc's own targets is
    # never hidden by a green test, and it's on whoever reads the report
    # to decide whether a regression is acceptable) -- see
    # `spec/ovallsp/benchmark/cold_index_benchmark_spec.rb` for the
    # "report-only regression threshold" this produces input for.
    class ColdIndexBenchmark
      DEFAULT_FILE_COUNT = 300

      def initialize(logger: Logger.new(io: $stderr))
        @logger = logger
      end

      # Returns a plain Hash report (JSON-serializable) -- never raises;
      # a failure to even generate/run the corpus degrades to a report
      # noting the failure, the same "never hides a number, never crashes
      # the caller" posture the rest of this feature has.
      def run(file_count: DEFAULT_FILE_COUNT)
        Dir.mktmpdir do |workspace_root|
          generate_corpus(workspace_root, file_count)

          cold_seconds = time_cold_index(workspace_root, cache_store: nil)

          cache_dir = File.join(workspace_root, ".bench-cache")
          cache_store = Cache::Store.new(cache_dir: cache_dir)
          time_cold_index(workspace_root, cache_store: cache_store) # populates the cache
          warm_seconds = time_cold_index(workspace_root, cache_store: cache_store)

          {
            file_count: file_count,
            cold_seconds: cold_seconds.round(4),
            warm_seconds: warm_seconds.round(4),
            warm_speedup: cold_seconds.positive? ? (cold_seconds / [warm_seconds, 0.0001].max).round(2) : nil,
            generated_at: Time.now.utc.iso8601
          }
        end
      rescue StandardError => e
        { error: "#{e.class}: #{e.message}" }
      end

      private

      def generate_corpus(root, file_count)
        file_count.times do |i|
          path = File.join(root, "app", "models", "generated_model_#{i}.rb")
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, <<~RUBY)
            class GeneratedModel#{i}
              def method_a(x)
                x.to_s
              end

              def method_b(y)
                y + 1
              end
            end
          RUBY
        end
      end

      def time_cold_index(root, cache_store:)
        workspace_index = WorkspaceIndex.new
        document_store = DocumentStore.new
        parser_service = ParserService.new

        ::Benchmark.realtime do
          ColdIndexer.new(root: root, parser_service: parser_service, workspace_index: workspace_index,
                          document_store: document_store, logger: @logger, cache_store: cache_store).run
        end
      end
    end
  end
end
