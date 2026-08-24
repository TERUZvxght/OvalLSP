# 048 audit — work in progress, NOT committed

Raw agent output from the complexity audit, salvaged from two workflow
runs. Kept outside git (this directory is untracked) so a new session can
pick it up: the workflow cache does **not** replay across sessions, which
is how the first run's results were nearly lost.

- `audit-part1-six-subsystems.json` — LSP dispatch, Parsing/index(part),
  Diagnostics, Semantic query, Runtime Agent, Observation, Plugins
- `audit-part2-four-subsystems.json` — Parsing/index, Type inference,
  Signatures, Cache

**These are unwritten-up findings, and most are unverified.** Only two
subsystems in part 1 and two in part 2 got a challenge pass, and two of
those returned `agrees: false`. The previous triage round in this project
was refuted in five of seven batches, so these counts are not measurements
yet. Verify before promoting anything into `048` or the register.

Two claims I verified myself, with evidence, before stopping:

1. **plugins/ (1,028 lines) is unreachable in the shipped product.** The
   only entry is `Server#load_static_plugins`, which requires
   `initializationOptions[:pluginManifests]`; the shipped extension sends
   only `workspaceTrusted` and `ovallspClient` (`vscode/src/extension.ts:233-239`),
   and `pluginManifests` appears nowhere in `vscode/src`. `README.md:246`
   nevertheless lists "Plugin API (static/runtime), process-isolated
   plugin execution" under `## Status` as implemented, and
   `docs/EXTENSION_CAPABILITIES.md` has no plugin row at all.

2. **`server.rb:1956-2355` is analysis logic in the dispatch layer** —
   17 methods, ~400 lines, ~10% of that file. It touches the LSP protocol
   zero times (the one `respond` match is the string `respond_to do |format|`
   inside a comment) and depends only on analysis collaborators:
   `@local_inferencer` 9, `@document_store` 5, `@workspace_index` 4,
   `@hierarchy_index` 3. Three call sites: server.rb:548, :711, :1917.
   This corroborates register entry `024.63`.

Open question I did **not** settle: `LocalInferencer` has seven `locate*`
walkers, four taking `env` and three rebuilding it (`{}` or
`parameter_env(node)`). That is plausibly *correct* — Ruby's scope rules —
rather than excess. It needs a revert-and-measure before anyone calls it
duplication.
