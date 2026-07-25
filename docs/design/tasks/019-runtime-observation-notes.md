# Task 019 implementation notes: overhead and privacy

Companion to `019-runtime-observation.md` — the design doc states the
constraints; this records how the implementation actually satisfies them
and what was measured.

## Privacy

`Rslsp::Observation::TypeNormalizer` is the only place an observed Ruby
*value* is ever touched, and it only ever calls `#nil?`, `#is_a?`, and (on
a Class/Module value only) `#name` — never `#inspect`/`#to_s`/`#to_str` on
application data, never reads instance variables, never serializes an
argument. `spec/rslsp/observation/type_normalizer_spec.rb`'s "never calls
#inspect or #to_s" example asserts this directly against a poisoned test
double whose `#inspect`/`#to_s` raise if ever invoked.

What actually crosses the process boundary (`Observation::Collector` in
the isolated runner process → `Observation::Runner` in Core, via
`Marshal.dump`/`Marshal.load` of an `Array<ObservedSignature>`) is
exclusively: class/module names (as plain Strings, already public
constant names — not application data), `Index::SymbolId` values, sample
counts, and a source-file content digest + line number (`code_fingerprint`
— a fingerprint, never the source text itself). No argument value,
`#inspect` output, SQL, environment variable, or file content is ever
read, held, or written anywhere in this feature.

`Observation::Collector#workspace_method?` filters to methods whose own
*definition* — not merely their call site — is under the workspace root,
so a Gem/stdlib method invoked from workspace test code is never observed
("workspace外Gemイベントを既定で収集しない").

## Overhead

The collector only ever runs inside the isolated runner process
(`Observation::Runner`, a genuinely separate OS process spawned only for
an explicit `rslsp/runObservedTests` request) — Core's own LSP-serving
process never installs a `TracePoint` and pays zero runtime cost for this
feature unless a user explicitly triggers an observation run.

Within the runner process itself, `Collector#handle`'s per-event cost is
dominated by one `Method#source_location` call (to filter by workspace
path and compute the fingerprint) and, for `:call` events, one
`Binding#local_variable_get` per `:req`/`:opt` parameter — no full
argument serialization, no full-file re-parsing. `Fingerprint#file_digest`
caches nothing itself but is only invoked once per `:call` event; a
production-quality follow-up could memoize it per source file within one
run to cut redundant digest work when one file's methods are called
repeatedly, which the current implementation does not yet do.

Server-side (`invalidate_stale_observations`), the added per-`#reindex`
cost is exactly zero whenever the observation store is empty (the default
— "observation disabled by default"): `Observation::Store#tracked_symbol_ids`
returns `[]` immediately for a store nobody has ever populated, and
`Server#invalidate_stale_observations` returns before doing any file I/O
at all in that case. Only once at least one method has actually been
observed does this cost anything, and even then it's bounded by however
many *methods were observed* (typically a small fraction of the whole
codebase), not the size of the workspace.
