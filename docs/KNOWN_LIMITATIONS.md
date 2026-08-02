# Apple Silicon Marketplace Preview — Known Limitations

[日本語版](KNOWN_LIMITATIONS.ja.md)

This document lists what's intentionally out of scope for the first
Marketplace Pre-Release, as distinct from bugs. See
[docs/SUPPORT_MATRIX.md](SUPPORT_MATRIX.md) for the exact,
evidence-based supported/unsupported table this summarizes.

## Platform scope

- **Only macOS on Apple Silicon (`darwin-arm64`) is targeted.** The VSIX
  is built with `vsce package --target darwin-arm64` and bundles native
  extensions (Prism, RBS) compiled specifically for that platform (see
  [ADR-0005](design/adrs/0005-platform-scoped-vsix-with-runtime-compatibility-check.md),
  Japanese).
  On any other OS/CPU, the bundled native dependencies simply aren't
  loaded, and OvalLSP shows a diagnostic explaining why rather than
  attempting to run in a degraded or guessed configuration.
- **Intel Macs, including under Rosetta 2 translation, are not
  supported in this Preview.** An x86_64 Ruby (even one installed
  natively on an Apple Silicon Mac via Intel Homebrew) is rejected by the
  same platform-compatibility check for the same reason.
- **The bundled native extensions embed the packaging machine's own
  absolute Ruby install path, mitigated by the Extension at launch
  time.** `otool -L` on the packaged `prism.bundle`/`rbs_extension.bundle`
  shows an absolute `LC_LOAD_DYLIB` reference to the *packaging
  machine's own* rbenv `libruby` path (e.g.
  `/Users/<packager>/.rbenv/versions/3.4.7/lib/libruby.3.4.dylib`), not a
  relocatable `@rpath` reference -- standard `rbenv`/`ruby-build`
  `--enable-shared` behavior on macOS. Reproduced directly: a
  `prism.bundle` built under one Ruby 3.4.x install raised `LoadError:
  linked to incompatible .../libruby.3.4.dylib` when required under a
  *different* Ruby 3.4.x install at a different absolute path -- which
  would otherwise affect essentially every real end user, since a
  different username alone is enough to trigger it, and this is not
  something ADR-0005's own engine/version/platform compatibility check
  catches. **Fixed**: before spawning Core Server, the Extension queries
  the resolved Ruby's own `RbConfig::CONFIG["bindir"]`/`["libdir"]`
  (`platformCompatibility.ts`'s `queryRubyConfigPaths`) and spawns the
  *real* `<bindir>/ruby` binary directly -- bypassing a version-manager
  shim entirely when the resolved command was one (mise/asdf/rbenv all
  resolve to a shim script) -- with `DYLD_LIBRARY_PATH`/
  `DYLD_FALLBACK_LIBRARY_PATH` set to that real binary's own `libdir`.
  The query itself is run with the *workspace folder's own* working
  directory, not omitted -- a version-manager shim resolves which Ruby
  version to actually run based on the current working directory's own
  `.ruby-version`/`.tool-versions`, so an omitted `cwd` would silently
  query (and then launch) whichever Ruby the *extension host's own*
  ambient working directory happens to resolve to, not the workspace's
  pinned version. Both the real-binary-spawn and the `cwd`-scoped query
  are necessary: setting the env var alone does nothing if the spawned
  command is still a shim script, since macOS strips `DYLD_*`
  environment variables for any process launched through `/bin/bash`
  (confirmed directly -- this is not specific to rbenv's shim, it's a
  general macOS behavior for anything that hops through the system
  shell). Verified by reproducing the exact failure through an actual
  rbenv shim forced to a different Ruby version than the one that built
  the vendored payload, and confirming the fix resolves it end to end,
  using two Ruby 3.4.x installations already present on the same
  development machine (see `docs/design/tasks/023.8-*.md`, Japanese).
  This mitigation only applies on darwin; a query failure (an unusually
  old Ruby, a spawn error) leaves Core Server started with the
  originally resolved command, same as before this fix existed.
- **Linux and Windows are not supported in this Preview.** The Ruby
  resolver includes Windows RubyInstaller detection logic and the Core
  Server itself is platform-agnostic Ruby, but this Preview's packaging,
  testing, and support commitment don't yet cover either OS.
- **WSL, Dev Containers, and Remote SSH are not supported in this
  Preview** — untested, not merely undocumented.

## Ruby version scope

Only Ruby 3.4.x is supported, specifically the patch versions actually
exercised in this project's own test runs (3.4.5, 3.4.7) — not the full
range `core/ovallsp.gemspec`'s `required_ruby_version >= 3.3` would
technically allow to install. That gemspec constraint means "not
rejected," not "verified" — Ruby 3.3.x and 3.5.x are treated as
unsupported until they're actually exercised by this project's test
suite.

## Distribution and update model

- The Core Server ships **inside** the extension and updates atomically
  with it via the Marketplace's own extension update mechanism — see
  [ADR-0006](design/adrs/0006-marketplace-bundled-core-update-atomicity.md)
  (Japanese).
  There is no separate Core Server download, and no independent
  background self-updater. If that model changes in the future (for
  example, to support Core updates independent of Extension releases),
  it will be a new, explicitly-designed feature, not something this
  Preview does implicitly.
- A custom `ovallsp.server.path` is checked for protocol compatibility
  but is never automatically updated, and is never compared against the
  bundled Core's own version/build/payload expectations.

## Static analysis limitations (not Apple-Silicon-specific, but worth
restating for a Preview)

OvalLSP is a confidence-aware heuristic engine for LSP features, not a
Ruby type checker. By design, it does not track:

- `method_missing`/`define_method`-based dynamic method definition,
  outside the specific Rails DSLs it already recognizes (`enum`,
  `scope`, `delegate`).
- `class_eval`/`instance_eval` with string-argument code generation.
- Constant resolution that only resolves at runtime (e.g. `const_get`
  with a dynamic argument).
- Code paths never exercised by a test run, for opt-in runtime type
  observation specifically (evidence only exists for what actually ran).

The third point had a visible consequence in every Rails application
through 0.1.6, fixed in 0.1.7. Reopening a class the workspace does not
define is syntactically identical to defining it, so
`test/test_helper.rb`'s `class ActiveSupport::TestCase` read as a plain
class with no gem parent, and its `parallelize` and `fixtures` calls were
reported as unknown methods. The static reading is now checked against
the running application rather than trusted
(`docs/design/tasks/024-deferred-review-findings.md`, 024.R5) — so it
still applies wherever the running application cannot settle the
question: an untrusted workspace or a non-Rails project, where there is
nothing to ask; a gem the Agent's process does not load, since it boots
in `development` and a `group :test` gem is simply not there; and a gem
class reopened without mixing anything in, whose ancestry carries no
evidence either way. 024.R5 lists each case.

## What 0.2.0's new checks deliberately do not cover

Both diagnostics 0.2.0 adds are held to "a wrong report is worse than a
missed one", so each is narrow on purpose. What that costs a user:

- **Argument types** are checked only where every input is *stated*: the
  expected type comes from an RBS/RBI declaration (Ruby source declares
  no parameter types), the signature has exactly one overload, and both
  the declared and the argument's own type are plain classes. A call the
  check cannot judge is left alone rather than guessed at, so a genuine
  mismatch in a union, an interface, a generic, or a method with several
  overloads is not reported.
- **Reading an `@ivar` nothing assigns** is reported in ERB views only,
  and only when the whole set of assignments can be enumerated. That is a
  high bar, and any of these silences the check for a view entirely: the
  controller's immediate superclass has not been read, something uses
  `instance_variable_set`, a module is mixed in, a callback form the
  analysis does not model appears, **the controller's class body calls
  anything beyond `private`/`protected`/`public` and the callback forms**
  (which covers every gem macro — `load_and_authorize_resource`,
  `expose`, Devise, ActiveAdmin — because what such a call installs is
  invisible until 024.R7 lets the index attribute it), or **the view
  renders anything**, or **any class in the chain is declared in more
  than one file** (each ancestor resolves to one file, so a second one
  reopening the class is never read). An ivar assigned by a sibling action also silences
  it, deliberately.

  What that leaves reported: a controller written in plain Ruby, whose
  view renders no partial. Two shapes are still wrong rather than merely
  silent, both recorded as 024.18: a view rendered by a *different*
  controller's action (`render "users/show"` from elsewhere) sees only
  its own controller's ivars, and a controller three or more classes deep
  whose topmost workspace class has not been read yet is guarded only at
  the first level.
- **Diagnostics for files nobody has opened** stop after 2,000 files in
  one pass, so a workspace larger than that gets no diagnostics for the
  tail. The pass walks in sorted order, so it is always the same tail
  rather than a different one after every save, and the Core logs when
  the cap bites. "Files" here means files it published for: an open file,
  a missing one and one that raised do not count against the cap. They also have no
  end-to-end verification against a real Rails app: the example written
  for one produced nothing in 45 seconds. The cause is diagnosed and the
  fix is scoped to its own task (024.14). The README matrix marks this
  row ⚠️ rather than ✅ for that reason.

## Conflicts with other extensions

See [vscode/README.md](../vscode/README.md#known-conflicts-with-other-extensions)
for a verified finding: OvalLSP installed alongside Shopify's Ruby LSP
produces overlapping (not crashing) LSP results — both extensions'
completion/definition results are shown together by VS Code's provider
model, which merges rather than picks one. This is expected to apply to
any other active Ruby language server extension, not just that one.

## What's tracked as separate, post-Preview work

Expanding beyond this Preview's scope (additional OS/CPU targets, a
Ruby/Rails version matrix, a self-hosted Apple Silicon release runner,
Entra ID-based Marketplace publishing, Extension JS bundling, and a
stable-release readiness bar) is recorded as non-blocking follow-up work
for this Preview — see
[docs/design/tasks/023.1-marketplace-preview-investigation-and-distribution-model.md](design/tasks/023.1-marketplace-preview-investigation-and-distribution-model.md)
(Japanese) and onward for the full task breakdown. This repository is
not currently accepting external issues (see
[CONTRIBUTING.md](../CONTRIBUTING.md)), so this work is tracked
internally rather than via a public issue tracker for now.
