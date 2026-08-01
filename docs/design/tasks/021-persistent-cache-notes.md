# Task 021 implementation notes

Companion to `021-persistent-cache-and-performance.md` — records what was
actually built, the concrete performance numbers measured, and what's
deliberately deferred.

## What's cached

`Ovallsp::Cache::Store` persists one `Index::FileSummary` per on-disk file
(declarations, ancestor/alias facts, reference candidates, generated
method facts — everything `ColdIndexer` produces per file), under
`$XDG_CACHE_HOME/ovallsp/<workspace_digest>/<sha256(path)>.cache`, falling
back to `~/.cache` when that variable is unset or empty. `MethodSummary`
(Task 010's per-method body-summary/call-chain cache) is **not**
persisted in this pass — it's already cheap to recompute on first query
(one method body, not a whole-workspace walk), and Cold Index warming is
the dominant startup cost this task targets. A future pass could extend
the same `Cache::Store` mechanism to it if profiling shows it's actually
worth the added complexity.

## Cache key

`Cache::Key.workspace_digest` folds every dimension the design doc lists
(schema version, Ruby version, Prism version, workspace canonical path,
Gemfile.lock digest, an RBS-affecting-files digest, a settings digest)
into one directory name — any change to any of them lands in a fresh,
empty directory rather than needing per-dimension migration/invalidation
code. See `Cache::Key`'s own docs for why this is deliberately coarser
than per-file precision at this level (workspace-wide only) — per-file
staleness is a separate, cheaper `content_hash` check inside
`Cache::Store#load`'s caller (`ColdIndexer#cached_or_parsed_summary`).

## Measured numbers

`Ovallsp::Benchmark::ColdIndexBenchmark` (spec/ovallsp/benchmark/cold_index_benchmark_spec.rb)
runs a 50-synthetic-file corpus on every CI run (kept small deliberately,
see the spec's own comment) and writes a report to
`core/tmp/cold_index_benchmark_report.json`. A representative run on this
development machine:

```json
{
  "file_count": 50,
  "cold_seconds": 0.0144,
  "warm_seconds": 0.008,
  "warm_speedup": 1.81
}
```

The design doc's own targets (1k files cold in 5s, 5k warm-usable in 3s)
were **not** independently verified at that exact scale in this pass —
`ColdIndexBenchmark#run(file_count:)` supports running at any scale
(pass 1000/5000 directly), but a multi-second-per-invocation benchmark
isn't run on every commit; per this task's own "目標を満たせない場合も
数値を隠さず記録する" instruction, that gap is recorded here rather than
silently assumed to be fine. Linear extrapolation from the 50-file number
above (0.0144s / 50 files ≈ 0.29ms/file cold) suggests 1k files would
land well under the 5s target, but this is an extrapolation, not a
measurement, and Ruby/Rails-shaped real-world files (larger, more
declarations per file) will differ from the synthetic corpus's
minimal fixture shape.

## Deferred / explicitly out of scope for this pass

- **Concurrent workspace instances**: the cache key already includes the
  workspace's own canonical path, so two different workspaces never
  collide on disk — genuinely concurrent *writes to the same workspace's*
  cache directory from two Core Server processes (e.g. two VS Code
  windows on the same folder) were not specifically tested. `Cache::Store#save`'s
  atomic rename means a torn write can't happen, but a benign race
  (two processes both computing and writing the same entry) isn't
  covered by a dedicated test in this pass.
- **Full-scale (1k/5k file) benchmark run**: supported by
  `ColdIndexBenchmark`, not run as part of the default suite (see above).
- **Backpressure/cancellation** for the cache-warming walk itself: Cold
  Index already runs on its own background thread and never blocks LSP
  responses; explicit cancellation of an in-flight Cold Index run (e.g.
  workspace closed mid-walk) isn't separately implemented in this pass.
