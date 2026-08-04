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

A workspace that reopens a *core* class has the same problem one level
out, recorded as 024.13. `lib/core_ext/array.rb` is idiomatic in Rails,
and reopening `Array` makes its whole ancestry look accounted for —
`Array, Object, Kernel, BasicObject`, every one of them known — so the
unknown-method check treats the receiver as closed even though gems keep
adding to it. A connected Runtime Agent settles it by reporting the real
ancestry; without one — an untrusted workspace, a plain Ruby project —
there is nothing to ask.

What this reaches is narrower than it sounds, and worth stating exactly,
because the call a user would try first is the one case that does *not*
reproduce it. A receiver the engine infers as a container — `[1, 2, 3]`,
or a local assigned from one — is outside the unknown-method check
entirely, so `[1, 2, 3].second` and `a = [1, 2, 3]; a.second` are not
reported. What is reported is a call whose receiver is the plain class:
a receiverless call inside the reopening itself.

```ruby
class Array
  def to_sentence_ish
    second        # reported: "Array has no method named `second`"
  end
end
```

**Nothing inside a block gets a type** unless the block's receiver is one
the engine models as a container — an `Array`, an Active Record
`Relation`, a `CollectionProxy`, and what `map`, `select`, `find`, `each`
or `reduce` yields from one. A `Hash` is *not* among them, so nothing
inside `hash.each do |k, v|` is typed, and neither is anything inside a
block on a receiver of your own classes. Hover answers nothing there
rather than guessing, and every diagnostic declines. **0.2.0 changed this
and you may notice it**: through 0.1.13 such a position answered with the
*enclosing call's* type, so hover said something — frequently the wrong
thing. It now says nothing. That is a deliberate trade, because the
alternatives were measured rather than assumed and both were worse: answering with the *enclosing call's* type reported a string
literal inside `opts.on("-x") do` as an `OptionParser`, and reading the
block's body turned a latent offset mis-resolution into 230
unknown-method reports across Ruby's own standard library. Unknown is the
only one of the three that no check acts on. The offset rule those two
depend on is being fixed on its own (024.20, still open), after which
the body can be read.

## Reports that are wrong today

The engine's standing policy is that a wrong report is worse than a
missed one. These are the places it currently says something untrue —
one of them as a colour, the rest as diagnostics. Every one is recorded
and all are visible on ordinary code, so they are listed here rather
than left for you to find.

Two are gone since the last release. **A `*_path`/`*_url` call is no
longer reported as a missing route when no routes have been loaded**
(024.24) — the case in an untrusted workspace and in any project that is
not Rails, where an empty route table used to answer "no such route"
rather than "I do not know". That was 8 reports across Ruby's own
standard library, every one false; it is now none, and 0.2.0's
project-wide pass would otherwise have published each of them for every
file rather than only for open ones.

The largest one this list used to carry is gone too: class-body macros
(`private`, `attr_reader` and their neighbours) reported as unknown
methods, together with the attribute readers those DSLs define. That was
**49 of the 62** reports over this project's own source and 12,134 across
Ruby's standard library, and it was fixed and released as 0.1.14 rather
than carried into this release (024.23).

- **Semantic highlighting colours only the first segment of a qualified
  constant** (024.21). In `Ovallsp::Server`, `Ovallsp` gets a semantic
  colour and `Server` keeps the editor's grammar colour, so the two
  halves of one name do not match. The same module is also coloured as a
  namespace where it is declared and as a class where it is read.

Six more are older than this release and untouched by it:

- **A declaration written inside a block belongs to the class the block is
  written in**, whatever the block's real receiver is. `Struct.new(:x) do
  attr_reader :label end` inside `class Outer` offers `label` on an
  `Outer`, and go-to-definition on it lands in the block; `def setup;
  attr_accessor :never_real; end` records `never_real`, so calling it is
  not reported — and here Ruby cannot define it by any path, since
  `attr_accessor` is `Module`'s and `self` inside an instance method is
  not a module. Attributing
  lexically is what `def` has always done, and three attempts to be
  cleverer for `attr_*` alone each produced false reports instead
  (024.31).
- **`def Foo.bar` is recorded as an instance method**, so `Foo.bar` is
  reported as unknown while `Foo.new.bar` is accepted — both answers
  inverted. **56** of Ruby's own standard-library reports are this
  (024.32).
- **A `def self.` the workspace adds to `Object` is not reachable**, so
  `Widget.foo` is reported for a method every class really has. 0.1.14
  did not report this, by an accident of the same mis-kinded lookup that
  made it report `class Object; def blank?; end` — a far more common
  shape — on code that runs. 0.1.15 trades the accident back for the fix,
  which is why this is the one shape it makes *worse* than 0.1.14
  (024.26).
- **A class that includes a module the workspace has not read still has
  its class-level macros reported.** `include SomeGem::Model` followed by
  `validate :ensure_ok` is reported, though the Concern installs
  `validate`. Introduced by 0.1.14 and not fixed here (024.35).
- **`K.instance_eval { attr_accessor :x }` is reported** where
  `K.class_eval { attr_accessor :x }` is not, though both define the same
  methods. The rule behind it is right for `object.instance_eval`, which
  is what it was written for (024.33).
- **`attr_accessor` written inside a `def` inside `class << self` is
  recorded as declaring class-level methods**, where Ruby defines
  instance ones — the macro runs when that method is *called*, with the
  class as `self`. Reading the attribute from an instance method is then
  reported as unknown. Real code has the shape: ActiveRecord's
  `has_and_belongs_to_many` builder, `csv/parser.rb`, `cgi/core.rb` and
  Devise (024.34).

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

  One shape is wrong rather than merely silent, recorded as 024.19. A
  constant the workspace does not declare — `::Vendor::Gadgets::Widget` —
  reaches the index's last-segment fallback, which answers with whatever
  class shares that final name. The argument check then judges against
  *that* class's signature and can report a mismatch against a class the
  receiver is not. There is no accompanying signal to spot it by: the
  constant check skips a name the same fallback resolves, so precisely
  when this misfires, the constant is *not* also reported unresolvable.
  What gives it away is the message naming a type from somewhere the
  receiver's own namespace has nothing to do with.
- **Reading an `@ivar` nothing assigns** is reported in ERB views only,
  and only when the whole set of assignments can be enumerated. That is a
  high bar, and any of these silences the check for a view entirely: the
  controller's immediate superclass has not been read, something uses
  `instance_variable_set`, a module is mixed in, a callback form the
  analysis does not model appears, **any class in the chain has a body
  that calls anything beyond `private`/`protected`/`public`,
  `before_action` and `skip_before_action`** — the whole chain, so
  `ApplicationController`'s own body decides this for every view beneath
  it, and `after_action`, `around_action` and `prepend_before_action` are
  among the forms that silence it. That covers every gem macro too —
  `load_and_authorize_resource`, `expose`, Devise, ActiveAdmin — because
  what such a call installs is invisible until 024.R7 lets the index
  attribute it. The check is also silenced when **the view renders
  anything**, and when **any class in the chain is declared in more than
  one file** (each ancestor resolves to one file, so a second one
  reopening the class is never read). An ivar assigned by a sibling
  action silences it too, deliberately.

  **In an application `rails new` produces, this check never fires**
  (024.22). Railties 7.2, 8.0 and 8.1 all generate an
  `ApplicationController` whose body calls `allow_browser versions:
  :modern`, that call is not one of the five modelled forms, and the rule
  applies to the whole chain — so every view in a default Rails
  application is silenced. The G16 capability row passes against a
  hand-written empty `ApplicationController`, which is a shape `rails new`
  does not produce.

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
  a missing one and one that raised do not count against the cap.
  Workspace-wide diagnostics also have no end-to-end verification against
  a real Rails app: the example written for one produced nothing in 45
  seconds. The cause is diagnosed and the
  fix is scoped to its own task (024.14). The README matrix marks this
  row ⚠️ rather than ✅ for that reason.

## What an editor feature does with a macro-declared method

`attr_accessor :name`, `delegate :title, to: :author`, `enum` and `scope`
declare their methods at a *symbol argument* rather than at an identifier
token. There is no name in the source to point an editor at, and two
features show it:

- **Rename refuses** rather than editing (024.28). Renaming through such
  a declaration would have to rewrite every call site and could not
  rewrite the declaration, leaving a file that does not run — 0.1.14 did
  exactly that, and 0.1.15 refuses instead. VS Code shows its own
  "cannot be renamed" message; the reason reaches the Core log only.
- **The outline lists one entry per declared name** (024.27).
  `attr_accessor :a, :b, :c` declares six methods on one line, so the
  outline shows six children with identical ranges. Every name is right
  and each is genuinely a method, but six identical ranges read as a bug.

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
