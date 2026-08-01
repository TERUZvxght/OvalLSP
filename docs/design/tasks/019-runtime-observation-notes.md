# Task 019 implementation notes: overhead and privacy

Companion to `019-runtime-observation.md` — the design doc states the
constraints; this records how the implementation actually satisfies them
and what was measured.

## Privacy

`Ovallsp::Observation::TypeNormalizer` is the only place an observed Ruby
*value* is ever touched, and it only ever calls `#nil?`, `#is_a?`, and (on
a Class/Module value only) `#name` — never `#inspect`/`#to_s`/`#to_str` on
application data, never reads instance variables, never serializes an
argument. `spec/ovallsp/observation/type_normalizer_spec.rb`'s "never calls
#inspect or #to_s" example asserts this directly against a poisoned test
double whose `#inspect`/`#to_s` raise if ever invoked.

What crosses the process boundary is the fields of `ObservedSignature`,
carried from `Observation::Collector` in the isolated runner process to
`Observation::Runner` in Core via `Marshal.dump`/`Marshal.load` of an
`Array<ObservedSignature>`. **`vscode/PRIVACY.md` is the single source of
truth for what those fields are; do not restate the list here.** The
enumeration that used to sit in this paragraph was itself incomplete —
it omitted `run_id` and `created_at` — which is the whole reason the rule
above exists. The invariant this file *does* own is that no argument
value, `#inspect` output, SQL, environment variable, or file content is
ever read or held: names and counts cross, values do not.

It does *write* two files, and 0.1.12 corrected the claim that it wrote
none: the `Marshal`'d results the boundary above is described in terms of
(`Harness.dump`), and a log the observed test command's own stdout and
stderr are redirected to for the length of the run. Nothing reads,
indexes or surfaces that log — the redirect exists only because in
`--stdio` mode Core's file descriptor 1 is the live LSP transport, so the
child's output must not land there. Both are deleted when the run ends,
though not guaranteed to be — `vscode/PRIVACY.md` owns that qualification
and states it. While the log exists it contains whatever the suite
printed; in a Rails app, routinely SQL.

`Observation::Collector#workspace_method?` filters to methods whose own
*definition* — not merely their call site — is under the workspace root,
so a Gem/stdlib method invoked from workspace test code is never observed
("workspace外Gemイベントを既定で収集しない").

## Overhead

The collector only ever runs inside the isolated runner process
(`Observation::Runner`, a genuinely separate OS process spawned only for
an explicit `ovallsp/runObservedTests` request) — Core's own LSP-serving
process never installs a `TracePoint` and pays zero runtime cost for this
feature unless a user explicitly triggers an observation run.

Within the runner process itself, `Collector#handle_call` memoizes every
per-method computation (workspace-eligibility check, `SymbolId`,
`code_fingerprint`, parameter name list) in `@method_cache`, keyed by
`[defined_class, method_id]` — all of it is invariant across repeated
calls to the *same* method within one run, so the (comparatively
expensive) full-file `SHA256` digest behind `code_fingerprint` only
actually runs once per distinct method, not once per call. Only the
per-call argument *values* (via `Binding#local_variable_get`, one per
`:req`/`:opt` parameter) are read fresh every time, since those
necessarily differ call to call. This caching was added after this
module's own overhead benchmark
(`spec/ovallsp/observation/overhead_spec.rb`) caught the pre-caching
version taking ~32s for 3,000 calls to one method; with it, the same
benchmark runs in well under a second.

Server-side (`invalidate_stale_observations`), the added per-`#reindex`
cost is exactly zero whenever the observation store is empty (the default
— "observation disabled by default"): `Observation::Store#tracked_symbol_ids`
returns `[]` immediately for a store nobody has ever populated, and
`Server#invalidate_stale_observations` returns before doing any file I/O
at all in that case. Only once at least one method has actually been
observed does this cost anything, and even then it's bounded by however
many *methods were observed* (typically a small fraction of the whole
codebase), not the size of the workspace.
