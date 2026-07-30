# Changelog

[日本語版](CHANGELOG.ja.md)

All notable changes to the OvalLSP VS Code extension are documented here.
Each release leads with what changed; the reasoning, the measurements and
the disproved approaches are kept below it under **Details**.

## 0.1.8 — Deferred corrections

- Fixed: repeatedly restarting the server no longer produces "The OvalLSP
  server crashed 5 times in the last 3 minutes". Those closures were the
  extension's own deliberate stops, reported back to you as crashes.
- Fixed: a container whose element type is unknown now renders the same
  way everywhere. `Hash.new` and a union arriving at the same value
  disagreed — one said `Hash[Unknown]`, the other `Hash`.
- Fixed: a method your own code adds to a container class — a reopened
  `Hash`, say — is now found by go-to-definition and completion on a
  container value (`Hash[Unknown]`, `Array[String]`). Standard-library
  members always worked there; the workspace's own did not.
- Removed: dead reference-indexing code, and a line in process ownership
  that could not affect any decision.

A patch release under the versioning rule in `docs/PUBLISHING.md`: no
capability row is added — the third item is an existing capability that
was not reaching a receiver it should always have reached. It clears four
entries from `docs/design/tasks/024-deferred-review-findings.md` (024.9,
024.2, 024.5, 024.7).

### Details

The crash notice is vscode-languageclient's, and it counts every
connection closure it did not initiate. Some of those are ours: stopping
a client that is still `starting` terminates Core directly, because
calling `client.stop()` in that state is unsafe. The library cannot tell
that from a crash, so the suppression now keys on lifecycle state as well
as on the branded rejection it already recognised — if we asked *that
generation* to stop, the closure is ours. A superseded generation counts
as stopped, since it was torn down to make way for its replacement and
its client can still report the closure afterwards. A client nobody asked
to stop is still reported however it failed.

That decision now lives in a module that imports no `vscode`, so it is
unit-tested rather than manually verified — the first piece of 024.10 to
come out of `extension.ts`.

The container rendering was settled in favour of the generic form, and
the union rule corrected to agree with it. The engine already produced
`Array[Unknown]` for `[]`, so the union rule was the one out of step.
Keeping the generic form also keeps a type argument for the container
rules to dispatch on: collapsing to a plain `Hash` threw away the ability
to resolve anything called on the result.

Independent review then found that settling on the generic form exposed a
gap rather than closing one: the method resolver understood only a plain
class receiver, so a workspace-declared method on a container class was
invisible on any container value — which had always been true, and this
change would have made it reachable more often. The resolver now reads a generic receiver as
the class it is generic over. `Relation` and `CollectionProxy` are
excluded, because they name Active Record shapes rather than classes
anyone declares, and reading them as class names sent every
`Model.where(...)` receiver into whatever a workspace happened to call
`Relation`.

## 0.1.7 — The reopened gem class

- Fixed: a class the workspace *reopens* rather than defines is no longer
  reported as missing the gem's own methods (`test/test_helper.rb`'s
  `parallelize` and `fixtures`). Measured against a real application: 2
  diagnostics before, 0 after.
- Fixed: every test file inheriting from such a class
  (`class FooTest < ActiveSupport::TestCase`) was reporting the gem's
  whole API as unknown.
- Fixed: two test guards that were passing without checking anything —
  capability ids from `G10` up were never compared, and a tempfile-leak
  check counted process-wide file descriptors.

A patch release under the versioning rule in `docs/PUBLISHING.md`: it
removes a wrong report and adds nothing.

### Details

Reopening a class is syntactically identical to defining it, so no amount
of reading the file can tell them apart — the Runtime Agent is asked
instead. It answers with the class's real ancestors, measured against that
same process's own `Object.ancestors` so an application that mixes into
`Object` calibrates the baseline itself; and where the class is not loaded
at all, with the autoload registration, which is the workspace's own
absolute path for an application class and a gem's bare require path for a
gem's.

The question is asked of every workspace-declared class in the chain, not
just the receiver, which is what makes it reach the common case:
reopening `ActiveSupport::TestCase` makes that name the workspace's own,
so every `class FooTest < ActiveSupport::TestCase` inherits a chain that
looks complete.

Nothing is loaded to answer this — `const_get` on an autoload-registered
constant runs the autoload, which in a real application raised
`Gem::LoadError` from a gem outside the bundle. Where there is no Runtime
Agent — an untrusted workspace, or a project that is not a Rails app —
the check behaves exactly as it did.

`Object.const_source_location` was tried first and cannot answer this: it
reports where a constant was *registered*, which for every Zeitwerk-managed
class in `app/` is one line inside Zeitwerk. It would have classified
`ApplicationController` as foreign and silenced the check across the whole
application. The disproof and two other rejected approaches are recorded
in `docs/design/tasks/024-deferred-review-findings.md` (024.R5), along
with what this approach still misses.

## 0.1.6 — Completion and diagnostics that actually fire

- Added: completion after a constant (`User.`, `Article.`, `JSON.`),
  which returned an empty list in every previous release.
- Added: completion of a class's own `def self.` methods.
- Added: completion of Active Record's own API (`save`, `update`,
  `destroy`, `all`, `find`, `where`, `create`), reported by the Runtime
  Agent from the classes the application actually loaded.
- Added: diagnostic for calling a method that does not exist on an Active
  Record model.
- Added: diagnostic for calling a method with the wrong number of
  arguments.
- Changed: accepting a completion now writes the call with tab stops
  (`takes_two(first, second)`), not just the name.
- Changed: hovering a method call shows its parameter list.
- Added: `docs/EXTENSION_CAPABILITIES.md`, with every row verified end to
  end against a real Rails application.
- Fixed: the bundled Core reported `0.0.1` regardless of the release it
  shipped in.
- Fixed: Rails' internal callback methods flooded completion.

A minor release under the versioning rule in `docs/PUBLISHING.md`: five
capabilities moved from "not yet" to verified. Every one of them was
something the extension appeared to offer and did not.

### Details

The two new diagnostics are deliberately narrow. The unknown-method check
stays silent for a model that defines `method_missing` or whose columns
could not be read; the argument-count check reports only for calls that
resolve to a single definition with no splat and no `*rest`. Anything less
certain reports nothing.

A method that takes arguments of a shape Rails does not expose
(`where(*, **, &)`) completes to `where()` with the cursor between the
parentheses; one that takes nothing stays a bare name, because `save()` is
not how Ruby is written.

Verification is two-layered because they are different claims.
`core/spec/e2e/capabilities_spec.rb` drives a real Core over stdio against
a real Rails application, waiting for the Runtime Agent and the cold index
before asking. `vscode/scripts/verify-installed-extension.sh` separately
confirms that a real VS Code installs, activates and runs the packaged
extension, and that nothing survives closing the window — the failure the
first layer cannot see, and the one this project had actually been in.

Known limitation, fixed in 0.1.7: a workspace file that *reopens* a gem
class is indistinguishable from one that defines it, so the unknown-method
check reads its ancestry as complete. `test/test_helper.rb`'s
`class ActiveSupport::TestCase` has exactly this shape in every Rails
application, and its `parallelize` and `fixtures` calls are reported as
unknown. Two per project, in one file.

## 0.1.5 — Lifecycle reliability and deeper semantic coverage

- Fixed: the Core process and its descendant process groups are now
  stopped and reaped on restart, deactivation, overlapping restart
  commands, and initialize hangs (macOS/Linux).
- Added: inference of controller view instance variables assigned by
  conventional `before_action` callbacks.
- Added: cold-indexing of references and Rails generated methods, with
  re-resolution when declarations arrive or disappear.
- Added: RBS/RBI overload return types in local inference, with live
  reload of project signature changes.
- Fixed: Union completion conditional flags, generated-method reopening
  fallback, stale model-dependent method summaries, duplicate Cold Index
  runs, and delayed automatic Agent retries after a manual restart.

### Details

The `before_action` inference covers inheritance, `skip_before_action`,
literal `only:` / `except:` selectors, and callback-to-action type flow.
Opt-in runtime observations are used only as a low-authority fallback for
returns that would otherwise be Unknown.

## 0.1.4 — Actually fixes the false "Payload hash mismatch" warning

- Fixed: the "Payload hash mismatch" warning that appeared on every
  activation. 0.1.3 attempted this and did not succeed.
- Added: `scripts/verify-packaged-payload-hash.js`, wired into
  `release.sh` and CI, so the same divergence cannot reach users again.

### Details

The 0.1.3 diagnosis below (`vsce publish` re-running its own prepublish
hook and rebuilding native extensions) was a real problem and remains
fixed, but it was **not** the cause of this warning.

The actual cause: `scripts/copy-core.js` recorded a sha256 over the staged
`core/` tree (815 files), while `.vscodeignore` independently excluded
`core/vendor/bundle/ruby/*/cache/**` — four Bundler `.gem` archives — from
the VSIX. The installed extension therefore always had 811 files, and
rehashing it at activation could never reproduce the recorded hash, on any
machine, ever. Two independent definitions of "the payload" that silently
disagreed. Confirmed by rehashing a real installed 0.1.3 and diffing the
staged tree against the packaged one.

Fixed structurally rather than by patching the hash: those cache archives
are now deleted during staging (they are pure build byproducts —
`bin/ovallsp` only ever adds `**/gems/*/lib` to `$LOAD_PATH`, never
`cache/`), so the staged tree *is* the shipped tree and hashing it is
meaningful. The `.vscodeignore` rule is gone, with a note against adding
any further `core/**` exclusion there.

The new guard rehashes the *packaged* VSIX and compares it against that
VSIX's own manifest — the same check the extension runs at activation, now
run at build time. Verified by reintroducing the old `.vscodeignore` rule
and confirming the guard fails, then restoring it and confirming it passes.

## 0.1.3 — Fix: `vsce publish` rebuilt the extension instead of publishing the verified build

- Fixed: the Marketplace received a rebuilt, unverified artifact rather
  than the build that had just been smoke-tested and hashed.
- **Correction:** this release was published believing it also fixed the
  false "Payload hash mismatch" warning. It did not — see 0.1.4 for the
  actual cause.

### Details

`vsce publish` runs its own `vscode:prepublish` hook independently of any
earlier `npm run package`, silently rebuilding Core's vendored native
extensions (Prism, RBS) from scratch a second time. Native-extension
compilation isn't byte-reproducible run to run, so what actually reached
the Marketplace was never the artifact that had just been built,
smoke-tested and hashed.

Fixed by publishing the exact already-built VSIX file via
`vsce publish --packagePath <file> --pre-release`. Verified end to end:
after this change a build's on-disk payload hash is provably unchanged by
the publish step, where before the same sequence produced two different
hashes.

## 0.1.2 — Documentation update

- Changed: the README (both languages) now documents that installing the
  extension alone is sufficient, given a compatible Ruby (3.4.x) already
  reachable on the system.
- Changed: the README documents a verified conflict with other Ruby
  language server extensions.

No code or runtime behavior changes.

### Details

VS Code merges results from every active provider rather than picking one,
so running alongside another Ruby language server (tested against
Shopify's Ruby LSP) produces overlapping completion and definition
results. See "Known conflicts with other extensions" in the README.

## 0.1.1 — Fix: published VSIX was missing the bundled Core Server

- Fixed: the published 0.1.0 VSIX shipped without a `core/` directory at
  all and could not start the Core Server.

### Details

0.1.0 was published by running `vsce publish` directly, which does not
vendor the Core Server (`vscode/scripts/copy-core.js`) unless invoked
through this project's own `npm run package` wrapper. Fixed structurally
by adding a `vscode:prepublish` npm script, which `vsce package` and
`vsce publish` both run automatically before packaging regardless of how
they are invoked — this failure mode can no longer happen from any
invocation path.

## 0.1.0 — Apple Silicon Marketplace Preview

- Added: hover, definition, documentSymbol, workspace/symbol, find
  references, guarded rename, completion and signature help, backed by
  real Prism-based parsing and a workspace-wide index.
- Added: Rails-aware completion and definition for routes and Active
  Record models, via an opt-in-trust Runtime Agent.
- Added: RBS/RBI signature integration and opt-in runtime type
  observation.
- Added: a version-compatibility handshake between the extension and its
  bundled Core Server (`OvalLSP: Show Version Information`).
- Added: automatic Ruby interpreter discovery across mise, asdf, rbenv and
  Homebrew, with clear diagnostics when none can be found
  (`OvalLSP: Show Environment Diagnostics`).

First Marketplace Pre-Release, scoped to macOS on Apple Silicon
(`darwin-arm64`) with Ruby 3.4.x.

### Details

The Core Server ships inside the extension itself — no separate install
step, and it updates atomically with the extension. An incompatible or
corrupted Core Server build is reported clearly rather than failing
silently or partially.

See
[docs/SUPPORT_MATRIX.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/SUPPORT_MATRIX.md)
for exactly what has been verified, and
[docs/KNOWN_LIMITATIONS.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/KNOWN_LIMITATIONS.md)
for what is intentionally out of scope in this Preview. This is a Preview
release; see
[SUPPORT.md](https://github.com/TERUZvxght/OvalLSP/blob/main/SUPPORT.md)
for the current state of external feedback and issue intake.
