# OvalLSP (Preview)

[日本語版 README](README.ja.md)

Semantic Ruby/Rails language features backed by a standalone Core Language
Server, packaged as a VS Code extension.

> **Preview status**: this is an early Pre-Release build. It currently
> targets **macOS on Apple Silicon only** (`darwin-arm64`). See
> [Supported environments](#supported-environments) below before
> installing.

## What OvalLSP does

OvalLSP runs a Ruby-native language server (`ovallsp`) alongside VS Code
and provides:

- Hover, `textDocument/definition`, `documentSymbol`, `workspace/symbol`,
  find references, and guarded rename, backed by real declaration
  extraction (via [Prism](https://github.com/ruby/prism)) and a
  workspace-wide index — not lexical/regex guessing.
- Local type inference (`ovallsp/explainType`) with RBS/RBI signature
  integration.
- Rails-aware completion, signature help, and definition for
  `*_path`/`*_url` route helpers, Active Record column/association
  types, and common Rails DSLs (`enum`, `scope`, `delegate`).
- Controller → view instance-variable propagation for `.erb` templates.
- A Runtime Agent that introspects your Rails app's own routes and
  models in the background (only in a **trusted** workspace — see
  [Security model](#security-model)) to make the above more accurate,
  falling back to static analysis alone if the app can't be introspected.
- Opt-in runtime type observation (`OvalLSP: Run Tests with Type
  Observation`) that records method call shapes actually exercised by
  your own test suite — never argument/return *values*, see
  [PRIVACY.md](PRIVACY.md).
- A Plugin API (static and runtime plugins) for extending the type
  engine, running in an OS-process-isolated sandbox.

This is a Preview: the feature set above reflects what's actually
implemented and tested today, not a roadmap.

## Supported environments

| | Status |
|---|---|
| macOS, Apple Silicon (`darwin-arm64`) | **Supported** |
| macOS, Intel / Rosetta | Not supported in this Preview |
| Linux, Windows | Not supported in this Preview |
| Ruby 3.4.x | **Supported** (tested: 3.4.5, 3.4.7) |
| Ruby 4.0.x | Best effort — the Core's suite is green under 4.0.6, nothing verifies it continuously |
| Ruby 3.3.x, 3.5.x | Not verified |
| Rails 8.1 | **Supported** (tested against the real integration suite) |
| Rails ≤ 7.x | Not verified |
| WSL / Dev Containers / Remote SSH | Not supported in this Preview |

Full detail and rationale: [docs/SUPPORT_MATRIX.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/SUPPORT_MATRIX.md)
and [Known Limitations](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/KNOWN_LIMITATIONS.md).

On a platform this build was not made for, OvalLSP refuses to load its
bundled native dependencies and says so. On a *Ruby* it was not built
for, it asks whether that Ruby carries `prism` and `rbs` of its own: if
it does, OvalLSP runs against those and notes it in the Output channel,
which is a combination nothing here verifies rather than one that is
supported; if it does not, you get a clear diagnostic naming
`gem install prism rbs` (see
[Version and compatibility errors](#version-and-compatibility-errors)).

## Requirements

- macOS on Apple Silicon.
- Ruby 3.4.x, discoverable via one of: an explicit
  `ovallsp.rubyExecutablePath` setting, [mise](https://mise.jdx.dev/),
  [asdf](https://asdf-vm.com/), [rbenv](https://github.com/rbenv/rbenv),
  or [Homebrew](https://brew.sh/) (`/opt/homebrew`). See
  [Ruby resolution](#ruby-resolution) if OvalLSP can't find your Ruby.

No `bundle install`, no repository checkout, and no manual gem
installation is required — the extension bundles Core Server's own
runtime dependencies (Prism, RBS).

### Does it work right after installing, with no extra setup?

**Yes, provided a compatible Ruby is already reachable on your system.**
OvalLSP does not install Ruby itself, and can't — it needs *some* Ruby
3.4.x already present (via mise/asdf/rbenv/Homebrew, or an explicit
`ovallsp.rubyExecutablePath`). Given that one prerequisite, everything
else needed to run — the Core Server itself and its own runtime
dependencies (Prism, RBS) — ships inside the VSIX; there is no second
download, no `bundle install`, and no repository checkout involved.

If no Ruby can be found at all, OvalLSP shows a clear diagnostic
explaining what's wrong and what to do rather than half-starting. If the
Ruby found simply differs from the one this build's native dependencies
were compiled for, see the paragraph above: it runs against that Ruby's
own `prism`/`rbs` when they are there, and tells you in the Output
channel that it is doing so (see [Ruby resolution](#ruby-resolution) and
[Version and compatibility errors](#version-and-compatibility-errors)).

## Quick start

1. Install the extension (Pre-Release channel).
2. Open a Ruby or Rails project.
3. Open any `.rb` file — the Core Server starts automatically.
4. Trust the workspace if prompted, to enable Rails-aware features (the
   Runtime Agent never runs in an untrusted workspace).
5. Run `OvalLSP: Show Version Information` to confirm the Extension and
   Core Server are running compatible versions.

## Commands

| Command | Purpose |
|---|---|
| `OvalLSP: Show Version Information` | Extension/Core version, protocol compatibility, and Ruby environment actually in use |
| `OvalLSP: Restart Server` | Restart the Core Server for every open workspace folder |
| `OvalLSP: Restart Rails Agent` | Restart just the Runtime Agent (routes/model introspection) |
| `OvalLSP: Show Logs` | Open the OvalLSP output channel |
| `OvalLSP: Show Environment Diagnostics` | Which Ruby was selected, and why (mise/asdf/rbenv/Homebrew/PATH) |
| `OvalLSP: Re-index Workspace` | Force a full re-index |
| `OvalLSP: Run Tests with Type Observation` | Opt-in runtime type observation (see [PRIVACY.md](PRIVACY.md)) |
| `OvalLSP: Clear Observed Types` / `Show Type Evidence` | Manage observation data |

## Settings

| Setting | Purpose |
|---|---|
| `ovallsp.enabled` | Enable/disable the extension entirely |
| `ovallsp.rubyExecutablePath` | Explicit Ruby interpreter, skipping auto-detection |
| `ovallsp.server.path` | Explicit Core Server entrypoint (advanced; see [Custom Core Server paths](#custom-core-server-paths)) |
| `ovallsp.observation.testCommand` | Command used by runtime type observation (default: `bundle exec rspec`) |

## Rails projects

When a workspace root contains `bin/rails`, OvalLSP starts a Runtime
Agent in the background (once the workspace is trusted) that introspects
your app's own routes and models to improve completion, definition, and
type inference for Rails-specific code. If the app can't be introspected
(no Rails, Agent crash, etc.), OvalLSP continues with static analysis
only — it never blocks on the Agent.

## Server startup and update model

The Core Server ships **inside** this extension — there is no separate
download or install step, and no independent background updater. When
VS Code updates this extension via the Marketplace, the bundled Core
Server updates atomically along with it: the next time a workspace
activates OvalLSP, it always runs the Core Server that shipped with the
Extension version you now have. A custom `ovallsp.server.path` is never
auto-updated and is only checked for compatibility, never modified.

## Version and compatibility errors

At startup, the Extension and Core Server exchange version, protocol,
build, and Ruby/platform information. If they don't match (a stale
process from a previous Extension version, a payload that didn't install
correctly, an incompatible custom `ovallsp.server.path`, ...), OvalLSP
stops before sending any feature requests and shows a diagnostic instead
of a broken/degraded session. Run `OvalLSP: Show Version Information` to
see exactly what was detected and what to do about it.

## Ruby resolution

OvalLSP looks for a Ruby interpreter in this order: an explicit
`ovallsp.rubyExecutablePath` setting, then mise, asdf, rbenv, Homebrew
(Apple Silicon), then your shell `PATH`. If VS Code was launched from the
Dock/Spotlight rather than a terminal, its `PATH` may not include your
usual shell's additions — in that case, set `ovallsp.rubyExecutablePath`
explicitly, or install Ruby via one of mise/asdf/rbenv/Homebrew (all
detected without relying on `PATH`). Run `OvalLSP: Show Environment
Diagnostics` to see exactly what was tried and why.

## Custom Core Server paths

Setting `ovallsp.server.path` points OvalLSP at a Core Server outside the
bundled one (for development against this repository, for example). A
custom path is checked for protocol compatibility the same way the
bundled Core is, but is never treated as "the standard bundled Core" for
version/build/payload comparisons, and is never auto-updated.

## Known conflicts with other extensions

OvalLSP hasn't been tested against every other Ruby-related extension,
but it *has* been verified side by side with a widely-used one —
[Shopify's Ruby LSP](https://marketplace.visualstudio.com/items?itemName=Shopify.ruby-lsp)
— installed and active in the same window. Result: **no crash or
install-time conflict**, but a real, confirmed overlap in results. Both
extensions register LSP providers (hover, completion, definition) for
the same `.rb` documents, and VS Code combines results from every active
provider rather than picking one. Semantic highlighting, which OvalLSP
added in 0.2.0, is the exception: VS Code resolves document semantic
tokens to a single provider rather than merging them, so with both
extensions active the colours come from one of them and not from both.
Which one is not something either extension chooses. Concretely, in this test: completion
and go-to-definition both returned results from *both* extensions
together at the same position (go-to-definition went from 1 candidate
with OvalLSP alone to 4 with both active) — meaning duplicate or
differing suggestions, and multiple candidate locations shown at once,
which can be confusing even though neither extension actually
malfunctions.

This is an architectural property of VS Code's provider model, not
something specific to Ruby LSP — it would apply to any other Ruby
language server extension you have installed and active (Solargraph,
Sorbet, etc.), not just that one. If you want OvalLSP's own results to
be the only ones shown for a Ruby project, disable other Ruby language
server extensions for that workspace.

## Troubleshooting

1. `OvalLSP: Show Logs` for the raw output channel.
2. `OvalLSP: Show Environment Diagnostics` for Ruby resolution.
3. `OvalLSP: Show Version Information` for Extension/Core compatibility.
4. If Rails-specific features aren't working, try `OvalLSP: Restart Rails
   Agent`, then confirm the workspace is trusted.
5. The status bar shows the current state: Indexing / Ready (static) /
   Ready (Rails) / Agent unavailable.
6. The persistent cache lives under `$XDG_CACHE_HOME/ovallsp/`
   (`~/.cache/ovallsp/` when that variable is unset or empty), keyed per
   workspace/Ruby/Prism/Gemfile.lock/RBS/**OvalLSP version** combination
   — deleting the relevant directory forces a fresh index. The version is
   in that key as of 0.2.1, and was not before: an upgrade kept serving
   the previous release's parse results for every file whose bytes had
   not changed, so its fixes did not reach them. Directories for keys no
   longer in use are swept at startup, the eight most recent kept.

## Privacy and telemetry

OvalLSP collects no telemetry and sends nothing over the network at
runtime. See [PRIVACY.md](PRIVACY.md) for the full statement, including
what opt-in runtime type observation does and does not record.

## Security

See [SECURITY.md](https://github.com/TERUZvxght/OvalLSP/blob/main/SECURITY.md)
for how to report a vulnerability, and the Rails Agent's own security
model above.

## Support

See [SUPPORT.md](https://github.com/TERUZvxght/OvalLSP/blob/main/SUPPORT.md).

## License

MIT — see [LICENSE](LICENSE). Third-party dependency licenses:
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Known limitations

See [docs/KNOWN_LIMITATIONS.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/KNOWN_LIMITATIONS.md)
for this Preview's platform scope, and the design docs for the static
analysis' own principled limits (dynamic `method_missing`/`define_method`
outside known Rails DSLs, `class_eval`/`instance_eval` with string
arguments, and runtime-only constant resolution are all out of scope by
design — OvalLSP is a confidence-aware heuristic engine for LSP features,
not a Ruby type checker).
