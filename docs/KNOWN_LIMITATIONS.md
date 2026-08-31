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
  loaded. What happens instead — since 0.2.1, and the same path the
  "Ruby version scope" section below describes: the extension checks
  whether the selected Ruby can load `prism` and `rbs` itself. When it
  can (a stock Ruby 3.3+ install carries both), the session runs against
  those with an Output-channel note — an **unverified** configuration,
  not a refused one. When it cannot, an error notification points at the
  Output channel, whose detail names `gem install prism rbs`.
- **Intel Macs, including under Rosetta 2 translation, are not
  supported in this Preview** — unsupported, not refused. An x86_64
  Ruby (even one installed natively on an Apple Silicon Mac via Intel
  Homebrew) takes the same probe path as any other mismatch: with
  `prism`/`rbs` loadable it runs as an unverified configuration, and
  nothing about that combination is tested.
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

**The published extension is built for Ruby 3.4.x**, and only 3.4.5 and
3.4.7 are actually exercised. The VSIX bundles Prism and RBS native
extensions compiled for the exact `major.minor` it was built under, so on
any other Ruby they are not used.

**On another Ruby it does not refuse — it checks.** As of 0.2.1,
`vscode/src/platformCompatibility.ts` asks whether that interpreter can
`require` `prism` and `rbs` itself. If it can, OvalLSP runs against
those and says so in the Output channel; if it cannot, you get an error
notification, and the Output-channel detail names
`gem install prism rbs`. Ruby 3.3 ships both, so a 3.3 user
usually gets the first — **which means an unverified combination, not a
verified one**. Nothing about 3.3 is exercised beyond `core/`'s own suite
under CI, and prism's version there may be older than the gemspec's
floor. Treat it as running at your own risk rather than as supported.

Ruby 3.5.x is unsupported on both counts until it is exercised.

0.2.0's round 22 widened the CI matrix to 3.3 and 3.4, and this section
then said "3.3 and 3.4 are supported" without qualification — which sent
a 3.3 user to install an extension that refuses to start. "The suite
passes under 3.3" and "the artifact runs under 3.3" are not the same
claim, and one does not license the other.

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

## Static analysis limitations (not Apple-Silicon-specific, but worth restating for a Preview)

OvalLSP is a confidence-aware heuristic engine for LSP features, not a
Ruby type checker. By design, it does not track:

- `method_missing`/`define_method`/`alias_method`-based dynamic method
  definition, outside the specific Rails DSLs it already recognizes
  (`enum`, `scope`, `delegate`). This one is not only a gap — see
  "Reports that are wrong today" below, where it produces its own false
  reports.
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
adding to it. **0.2.16 widened where this shows.** `self` has a type
now, so a call written `self.digest` inside such a class is reported
exactly as a bare `digest` in the same file already was — the same
defect, reaching a spelling that used to be invisible because nothing
knew what `self` was. A connected Runtime Agent settles it by reporting
the real ancestry; without one — an untrusted workspace, a plain Ruby
project — there is nothing to ask. <!-- documents: 024.13 -->

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

That same offset rule has a second consequence you meet directly, and it
is the one this document did not name until 0.2.15: **a `.` written
straight after a block answers nothing.** In `[1, 2].map { |x| x }.first`
the cursor after the block gets no hover, no completion and no signature
help — even though the engine can type that receiver perfectly well as
`Array[Integer]`, and does when you ask it anywhere else. It declines
rather than answering wrongly, which is the right way round, but the
answer is one it already has. <!-- documents: 024.20 -->

## Reports that are wrong today

**A namespaced type reported incompatible with itself.** If your `sig/`
declares a parameter inside a namespace — `module App; class Registry;
def fetch: (Key key) -> Key` — and the Ruby that calls it is written
inside that same namespace, the declared type arrives qualified and the
inferred one arrives bare, and the argument-type check compares the two
spellings as different classes. Driven over the `rbs` gem's own 89
hand-written signatures, every argument-type report it produces is this
one shape: ``expects RBS::TypeName here, but TypeName is given``, where
the two names are the same class. Nothing is wrong with your
code. <!-- documents: 024.224 -->


The engine's standing policy is that a wrong report is worse than a
missed one. These are the places it currently says something untrue —
one of them as a colour, the rest as diagnostics. Every one is recorded
and all are visible on ordinary code, so they are listed here rather
than left for you to find.

**The one you will meet first is typing a `.`.** Half of it is fixed in
0.2.1: `a.` at the end of a method no longer reports that your class has
no method named `end`. The other half is not, because there is nothing
to notice — `a.` followed by a line like `b = "str"` is valid Ruby
meaning `a.b = "str"`, and it is reported as such:

```ruby
a = Article.new
a.
b = "str"        # → Article has no method named `b=`
```

A next line of `value`, `if true` or `return 1` does the same; `puts 1`
and `other_thing(1)` do not. The report goes away as soon as you finish
the name. It cannot be told apart from the same code written on purpose,
so the fix is to stop publishing while you are still typing rather than
to add another check, and that is not in this release (024.41). <!-- documents: 024.41 -->

Two that this list used to carry are gone — fixed in earlier releases,
not this one. **A `*_path`/`*_url` call is no longer reported as a
missing route when no routes have been loaded**
(024.24, fixed in 0.2.0) — the case in an untrusted workspace and in any project that is
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

Seven more are older than this release and untouched by it:

- **A class that includes a module the workspace has not read still has
  its class-level macros reported.** `include SomeGem::Model` followed by
  `validate :ensure_ok` is reported, though the Concern installs
  `validate`. Introduced by 0.1.14 and not fixed here (024.35). <!-- documents: 024.35 -->
- **A method a loop defines is reported as unknown.** `EVENTS.each { |id,
  _| alias_method "on_#{id}", :_dispatch_1 }` is idiomatic in generated
  code, and the name is not a literal, so the index records nothing and
  every call to it is reported. `define_method` with a computed name is
  the same shape. It is listed here rather than only under "static
  analysis limitations" because the engine's own policy is that a wrong
  report is worse than a missed one, and this is a wrong report, not a
  missed one. What 0.2.0 changes is the blast radius: diagnostics now
  publish for files nobody opened, so it reaches the Problems panel
  rather than waiting to be found. (This bullet claimed "525 reports in
  one file, prism's `translation/ripper.rb`" and called it the largest
  concentration the engine produces. That was measured before the same
  release removed those reports; the file now produces 10, none of them
  this shape -- and the 7 written here until 0.2.1's last day was itself
  a number taken once and not re-measured. A number recorded and not re-measured after the fix that
  invalidated it.)

## What 0.2.0's new checks deliberately do not cover

Both diagnostics 0.2.0 adds are held to "a wrong report is worse than a
missed one", so each is narrow on purpose. What that costs a user:

- **The number of arguments** is checked, and on the code measured so far
  it now reports nothing at all: **0** over Ruby 3.4.10's standard
  library, five Rails 8.1.3.1 gems and minitest — 2,095 files — where the
  same corpus produced **109** before, every one of them working Ruby.
  Read it the way the argument-*type* bullet below reads: something that
  will not contradict your code rather than something that will catch a
  mistake in it. Two things it will not judge, both of which used to be
  reported: a method defined by `define_method` from a block it cannot
  read, and one a `delegate` or a `scope` generates — those forward their
  arguments, so nothing here states a count. Every earlier report had its
  own cause and each is fixed: `def Const.method` recorded as an instance
  method (024.32), a block's `self` read as the enclosing class (024.31),
  and `define_method(:warn) { |*messages| }` recorded as taking *no*
  arguments, which alone made every `warn` and every `p` the corpus calls
  a report. Reporting nothing on committed code is what this check should
  do — Ruby that runs does not call its own methods with the wrong number
  of arguments, and the mistake this catches is one you make in the editor
  and fix seconds later, which no corpus can contain. Measured the other
  way round, by writing calls that are deliberately wrong: it catches
  **31 of 31** on a class, and **0 of 16** on a module, for the reason the
  "typo in a call on a module" section below gives. So a third of the
  argument-count mistakes in a codebase shaped like this one go
  unreported, all of them on module receivers.
- **Argument types** are checked so narrowly that on the code measured
  so far they are not reported at all. Over Ruby's standard library, five
  Rails gems and minitest — 2,042 files — this check produces
  **zero** findings, and over prism with its own RBS loaded it produces
  zero as well (024.37). Before 0.2.0's last round of fixes those two
  corpora produced 795 and 151, and every one was wrong. Treat it as
  something that will not contradict your code rather than something that
  will catch a mistake in it; the shapes below say why. <!-- documents: 024.37 -->

  Checked only where every input is *stated*: the
  expected type comes from an RBS/RBI declaration (Ruby source declares
  no parameter types), the signature has exactly one overload, and both
  the declared and the argument's own type are plain classes. A call the
  check cannot judge is left alone rather than guessed at, so a genuine
  mismatch in a union, an interface, a generic, or a method with several
  overloads is not reported.

  One shape is wrong rather than merely silent, recorded as 024.19, and
  it is **narrower than this paragraph said until 0.2.11**. A name you
  write with its namespace — `::Vendor::Gadgets::Widget`, or
  `Vendor::Gadgets::Widget` — no longer reaches the index's last-segment
  fallback at all, and *is* reported unresolvable when nothing declares
  it. What remains is a **bare** name that exactly one class in your
  workspace claims: `Widget.make(1)` is judged against that class's
  signature even where the receiver you meant is a different `Widget`.
  What gives it away is the message naming a type from somewhere the
  receiver's own namespace has nothing to do with. <!-- documents: 024.19 -->
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
  does not produce. <!-- documents: 024.22 -->

  What that leaves reported: a controller written in plain Ruby, whose
  view renders no partial. Two shapes are still wrong rather than merely
  silent, both recorded as 024.18: a view rendered by a *different*
  controller's action (`render "users/show"` from elsewhere) sees only
  its own controller's ivars, and a controller three or more classes deep
  whose topmost workspace class has not been read yet is guarded only at
  the first level. <!-- documents: 024.18 -->
- **Diagnostics for files nobody has opened** stop after 2,000 files in
  one pass, so a workspace larger than that gets no diagnostics for the
  tail. The pass walks in sorted order, so it is always the same tail
  rather than a different one after every save, and the Core logs when
  the cap bites. "Files" here means files it published for: an open file,
  a missing one and one that raised do not count against the cap.
  (Until 0.2.1 this bullet also said workspace-wide diagnostics had no
  end-to-end verification, because an example written for one produced
  nothing in 45 seconds. It reproduces as *working*: on a real Rails
  application a never-opened file is answered 1.4 s from process start.
  The G17 row and its example exist now, and 024.14 records what the
  original measurement most likely hit.)

## A class of yours named after a core class

**If it lives in a namespace, mistakes on it are not reported.**
`Billing::Range`, `Admin::File`, `Reporting::Time` — used the way Ruby
refers to a class from inside its own namespace, by bare name — hover,
go to definition, completion and signature help all answer, but every
diagnostic about such a receiver is silently withheld: a typo like
`r.tagg` on your `Billing::Range` is never flagged, while the same typo
on a class with an unshared name is. The engine cannot tell the `Range`
you wrote from the `String` a literal produced, so the refusal that
protects the literal silences your class too. And a literal of that
same name pays the other half of the cost: with `Billing::Range`
indexed, `(1..5).` completes to `Billing::Range`'s members — `tag`,
not `each` — while hover on `(1..5).each` answers from the real Range.
The readers disagree, and which is right depends on information the
engine does not have (024.47). A literal of an *unshared* name is
untouched (`"hello".` completes String as usual unless some class of
yours is named `…::String`), and a class named after a core one at the
*top* level is unaffected. <!-- documents: 024.47 -->

(Until 0.2.3 this section claimed the opposite — that hover, definition
and completion stopped answering for such a class as of 0.2.1. That
described an arrangement built and rolled back *inside* 0.2.1's review
loop; what 0.2.1 actually shipped is the silence described above.)

## "Go to Symbol in Workspace" is slowest at the moment you open it

A `workspace/symbol` request may carry an empty query, which the protocol
defines as "all symbols", and an empty query matches every symbol in your
workspace by definition. So the picker's opening state, and to a lesser
extent the first character you type, stay proportional to how big the
workspace is — measured at about 17ms and 11ms on a 15,000-symbol
workspace, and growing from there. While that request is running it also
holds the lock indexing needs, so opening the picker on a large workspace
can briefly delay indexing that is running at the same time.

Typing more characters is faster, but not because anything switches on:
0.2.16 replaced a full scan with an index keyed on the names being
matched, and that index is read for **every** query including the empty
one. What a longer query changes is how much the index removes. Measured
over 1,037 files and 14,942 symbols, a two-character query went from
10.4ms to 4.0ms — about 2.6 times — while the empty query is bounded by
the number of results rather than by the query.

Symbol search *within* a file, and go to definition, use a different path
and are unaffected. <!-- documents: 024.137 -->

(Until this was re-measured, this section said the picker "sends an empty
query when it opens" — a claim about the client that nothing in
`docs/CLIENT_BEHAVIOUR.md` showed — and that "once you have typed two
characters or more the picker uses an index", which describes a switch
that does not exist, at "roughly four times" where the measurement says
2.6.)

## The packaged extension is driven on Linux, and smoke-tested on macOS

The Core Server laid out the way a VSIX lays it out — inside the
extension, with its runtime gems vendored — is driven through a full
editor session on every push, alongside the repository copy. That covers
the bundled-Core load path, which is where the packaged build has
actually broken before.

What it does not cover is the platform. That run is on Linux, so the
**darwin-arm64** native extensions you actually install are still only
exercised at publish time, by a smoke test that checks hover, go to
definition and a clean shutdown. A defect specific to the macOS build is
therefore still caught at publish rather than in
review. <!-- documents: 024.283 -->

## What a version mismatch actually does

**It tells you, and then carries on** — for the mismatches found *after*
the Core Server has started. When the Extension and the Core disagree
about version, protocol, build identity or payload hash, you get an error
notification and the detail in the Output channel, and the session keeps
running.

That matters most for the two reasons you cannot see: a payload hash
mismatch means the bundled Core is not the one this build shipped, and a
protocol mismatch means the two sides disagree about the wire. In both
cases OvalLSP goes on answering hover, completion and go to definition.
Treat those answers as unreliable until the mismatch is resolved, and run
`OvalLSP: Show Version Information` to see what was detected.

The check that runs *before* the Core Server starts does stop: as of
0.2.10, a Ruby that cannot load this build's bundled dependencies means
the Core Server is not started at all, and you are told so.

**The difference is deliberate, and 0.2.12 recorded why.** The Core ships
inside the extension, so the only way to reach a post-start mismatch is
to point `ovallsp.serverPath` at a Core of your own — and refusing to
serve a session you deliberately configured is worse than telling you
what does not match.

## How long an edit takes to re-analyse

**Seconds, on a file of a couple of thousand lines.** Measured per
keystroke, with the one-off signature load excluded: `net/http.rb` (2,574
lines) 2.1 s, `rubygems/specification.rb` (2,666 lines) 5.3 s, and it
grows faster than the file does. The Core answers one request at a time,
so hover, completion and signature help wait behind it.

The design document states 300 ms for this, so it is not a matter of
taste — it is a requirement the product misses by an order of magnitude,
and it had no entry here until 0.2.1 (024.45). It is not new in this
release; 0.2.0 measures the same. Files of a few hundred lines, which is
most application code, re-analyse in well under a tenth of a second. <!-- documents: 024.45 -->

**Deferring the report until you stop typing was tried in 0.2.2, rolled
back, and built again in 0.2.10 in a different shape.** The first attempt
was a timed debounce with waiter threads; it produced two races, could
not bound how many analyses of one file run at once, and each of four
consecutive review rounds found another defect in it. What ships now is
not a debounce: there is no interval, no waiter thread, and the question
is only whether anything else is waiting to be read. A burst of edits
faster than one analysis produces a few answers rather than one per
keystroke, and — the part you feel — a hover asked while you are typing
is answered before the pending analysis runs, in about 0.04 s instead of
1.4. What is still per-keystroke is a burst slower than the analysis: an
edit that settles is always analysed, which is the property that matters
more. <!-- documents: 024.57 -->

## What the undefined-method check gets wrong on real code

**Measured, over 213 files of installed gem source: 54 reports, of which
53 were wrong. 0.2.6 brings that to 9.** The measurement is the same one
each time — the same files, the same server, with a category the change
cannot affect held as a control.

The cause that mattered for application code is gone: a class that
`include`d a module **defined in the same file, from inside a nested
namespace** lost that module's methods, and the check reported them
missing. Rails concerns are that shape. So is metaprogramming —
`attr_atomic` and friends — which static analysis cannot see: a class
whose body runs a macro this extension cannot read is now treated as
having a method set it does not know, and the check says nothing about it
rather than guessing.

**What still gets reported wrongly**, and what it looks like:

- **Files for another Ruby implementation.** JRuby-only sources call
  `java`, which your MRI does not have. Seven of the nine. If you are not
  opening JRuby-specific files, you will not see these.
- **A method supplied by a subclass.** An abstract class that calls a
  method its subclasses define — a deliberate template-method pattern —
  is reported, because on that class alone the call really would fail.
  Two of the nine. <!-- documents: 024.76 -->

A module chosen at runtime — `extend`ing whatever is held in a variable
or a constructor argument — used to be a third kind, because an ancestor
this extension cannot name was recorded as no ancestor at all. It is now
recorded as one it cannot name, and nothing is reported about that
class's members.

## A `private` or `module_function` written inside a block

If you write one inside a block whose receiver this extension cannot
vouch for — `SOME_CONST.each { private }`, `helper { private }` — it does
not apply it to the methods that follow, though Ruby may. Written
directly in the class or module body it works, and as of 0.2.15 so does
a block iterating a literal (`[1].each { private }`,
`%w[a b].each { module_function }`, `[1].each { protected }`). Earlier
releases said 0.2.13 here; that was wrong, and the fix landed in 0.2.15.

The remaining case is one this extension cannot decide without knowing
what the call does with the block: `included do ... end` really does run
its `private` against a different module, and treating those alike is
what used to make every method after such a block private — which
removed real answers rather than adding wrong ones, so this is the side
it fails on. <!-- documents: 024.221 -->

## A typo in a call on a module

`PlainClass.nope` is reported and `PlainMod.nope` is not. A module's
ancestor chain is itself, so this extension cannot tell "I have seen
everything this module declares" from "I have seen one file that reopens
it" — and 0.2.10 tried treating the two as the same, which reported
`Rails.application`, `Rails.env` and `Rails.logger` as missing. Declining
is the safer half of that trade until the index can prove the difference.
`module_function` and `extend self` themselves work: their methods appear
in completion, hover and go to definition. <!-- documents: 024.106 -->

## Completion offers methods you cannot call

On a class — `Post.`, `Circle.` — and on any receiver in a plain Ruby
project, the list includes private methods. Measured by asking a running
application whether each offered name is actually callable: 91 of 816 on
a Rails model class, 69 of 121 on a class of your own in a plain project,
`initialize` among them. Accepting one raises `NoMethodError`. The
instance-level list in a Rails project with the Runtime Agent connected
is clean. <!-- documents: 024.99 -->

## The four features disagree at the same position

- `<% @posts.each do |post| %>` then `post.titel` in a view: hover says
  `Post` and completion offers Post's columns, and the undefined-method
  check says nothing. Written `<% Post.all.each do |post| %>` it *is*
  reported, and so is the same code in a `.rb` file.
- `p.update`, `p.save!`, `q.destroy`: hover shows nothing and go to
  definition finds nothing, while completion offers them and the check
  accepts them.
- Signature help is silent for `Post.new(`, `Circle.new(`, `Post.find(`
  and `p.update(`, while it answers for a method of your own and for
  `"abc".split(`. A method that overrides another shows its signature
  twice. <!-- documents: 024.100 -->

## Ordinary Ruby the undefined-method check reports anyway

Two shapes, both of them code that runs. Measured over 177 files of
rspec-core, i18n, psych and reline: 16 reports.

- **`alias` to a method that came from an included module.**
  `include Escaping` then `alias safe_escape escape` — calling
  `safe_escape` is reported. Aliasing a `def` in the same class is
  fine. <!-- documents: 024.238 -->
- **`URI(...)` written on your own class.** `Kernel#URI` comes from a
  gem, and this extension does not yet index what gems define, so it
  cannot see it. The same will apply to other `Kernel` methods a gem
  supplies. <!-- documents: 024.R7 -->

This section said *four* shapes and 41 reports until 0.2.16, and two of
the four had stopped happening some releases earlier — the count was
re-measured when the finding behind it was split, and it had gone stale
in both directions. A class made with `Struct.new` or `Data.define` and
then reopened, `define_method` and `attr_reader` inside
`Class.new do … end`, and a method defined inside a loop with a literal
name are all no longer reported. The check now declines on those bodies
instead, which means it also says nothing about a genuine typo written
there — silence rather than a wrong answer, and still a
gap. <!-- documents: 024.237 -->

## What the undefined-method check gets wrong without a Runtime Agent

If your project reopens a core class — an `initializers/core_ext.rb`, or
anything with `class String` in it — this extension treats that class as
one it fully knows, and then reports every method a *gem* adds to it as
missing. `String has no method named squish`. `Integer has no method
named minutes`. Measured over ActiveSupport's and ActiveModel's own
source: 74 such reports.

The same applies to a class that includes a module from a gem whose code
is not in your workspace. `include Singleton` then `.instance`;
`include Sidekiq::Worker` then `sidekiq_options` — 0.2.6 fixed those
particular two, and the family they belong to is only fully answered by
the Runtime Agent, which reports what your classes really respond to.

**So this is loudest exactly where the Agent cannot run**: a plain Ruby
project, which never gets one, and a Rails project in VS Code's
Restricted Mode, which is every Rails project until you trust the
folder. Trusting the workspace is what makes these go
away. <!-- documents: 024.83 -->

## What a constant hovers as

**Its own name, as a class.** `MAX_RETRIES = 3` then `MAX_RETRIES` hovers
`ClassOf[MAX_RETRIES]`, not `Integer` — and the same for a string, a
float, an array or a frozen hash. Completion after a constant offers
nothing, and nothing assigned from one carries a usable
type. <!-- documents: 024.84 -->

## An instance variable set in another method

`@article` assigned by a `before_action` and read in the action has a
type **in the view** and no type **in the controller**: hovering it in
`show.html.erb` says `Post` and offers 408 completions, hovering the same
name in the controller says nothing and offers none. Any ivar written in
one method and read in another behaves this way. <!-- documents: 024.86 -->

## Where a relation stops being a relation

`Post.where(published: true)` is understood. `Post.where(published:
true).where(user_id: 1)` is not, and neither are `.order`, `.limit`,
`.includes`, `.count` or a second scope. Hover goes blank at the second
link, and so does the undefined-method check —
`Post.published.where(user_id: 1).titel` is not
reported. <!-- documents: 024.87 -->

## Completion on a value that could be two things

`x = cond ? "s" : 1` offers you every method of `String` *and* every
method of `Integer`. Picking one of them fails on the other branch.

As of 0.2.15 the list at least says which is which: the methods **both**
branches have come first, and the ones only one branch has sort after
them. That is ordering, not a warning — the list still offers `upcase`
on a value that may be an `Integer`.

*An earlier version of this paragraph said the undefined-method check
"takes the opposite and safer view of the same value, so the two
features disagree". Measured at that position, it takes no view at all:
it is silent on `String | Integer` even when neither branch has the
method, and silent on a plain `String` too, for the separate reason
recorded below about core-library receivers. The contrast it described
is real only on a class of your own.* <!-- documents: 024.88 -->

## What signature help shows

The highlight does not advance as you type arguments: the popup stays on
the first parameter for the whole call. That is a capability this
product has not claimed yet rather than something behaving wrongly —
`docs/ROADMAP.md` carries it under 0.4.0, "Signature help highlights the
argument the cursor is in".

*Until 0.2.15 the parameters themselves were also shown stripped —
`def simple(a, b = 2, *rest, key:)` presented as
`simple(a, b, rest, key)`, implying `key` was the fourth positional
argument. That is fixed; the signature is now spelled the way you wrote
it.*

## Smaller things

- A typo on a core-library receiver is not reported: `"hello".upcse` and
  `[1,2].siz` are silent, though completion at the same spot knows the
  type exactly. <!-- documents: 024.129 -->
- A scope defined inside a concern's `included do` has no type. <!-- documents: 024.132 -->
- **On Ruby 4.0 only**, `instance_variables_to_inspect` is reported
  missing on your own class. Ruby 4.0 gives it to every object and the
  bundled signatures do not declare it, so the check reads it as absent.
  The three names with the same problem on 3.3 and 3.4 were fixed in
  0.2.16; this one is not, because silencing it everywhere would also
  silence a genuine typo of that name on the Ruby versions that do not
  have it. Ruby 4.0 is best-effort — see the support
  matrix. <!-- documents: 024.288 -->

## What a partial's local resolves to

**Nothing.** In `_article.html.erb`, `article` is supplied by whatever
called `render`, and the engine does not read the call site — so hovering
it answers an empty popup and `article.` completes to nothing, while an
`@ivar` in the same template resolves through the controller action that
assigned it. A local the template assigns itself (`<% post = Post.new %>`)
does resolve. This is the commonest shape in a scaffolded app's views
(024.44). <!-- documents: 024.44 -->

## What the signature popup shows for a stdlib or gem method

Four, and only the first is about the *label* rather than about which
method was found:

- **A return type RBS writes as `self`, `void` or `untyped` reads
  `Unknown`**, and a method's own type variable leaks (`map() ->
  Array[U]`). The engine has one word for "nothing can be concluded from
  this" and uses it in a place meant to be read by a person, where the
  word RBS actually wrote would be better (024.42). <!-- documents: 024.42 -->
- **Inside a `module`, a call to a method only a stdlib ancestor
  declares gets no popup** — `puts(` written in a concern or a helper
  module, in an instance method rather than a `def self.`. A module's
  ancestors really are just itself, so the chain this extension walks
  never reaches `Kernel`; Ruby reaches it at run time through whatever
  object the module was mixed into. **Completion is not silent here** —
  typing `put` in a module body offers `puts` and `putc`, because
  completion asks `Kernel` unconditionally rather than walking the
  enclosing scope's chain. So the asymmetry this entry is about is still
  exactly true in a module body: completion answers, signature help and
  hover do not. In a `class` body, and in a `def self.` inside a module,
  all three answer as of 0.2.16. <!-- documents: 024.243 -->
- **At the top level of a file, outside any class, signature help says
  nothing at all** — `puts(` written in a script rather than in a class
  body. There is a fix for this that passes every test and makes things
  worse: it would answer a call to *your own* top-level method with the
  stdlib method of the same name, and `open` is the name that collides
  most. It is being fixed properly rather than
  quickly (024.229). <!-- documents: 024.229 -->
- **A method you define at the top level of a file, outside any class,
  is not found by anything** — no hover, no completion, no signature
  help, no go to definition, from anywhere. Ruby puts such a method on
  `Object`; this extension records it with no owner at all, so nothing
  can look it up (024.230). <!-- documents: 024.230 -->

## Rename refuses on a method a macro declared

`attr_accessor :name`, `delegate :title, to: :author`, `enum` and `scope`
declare their methods at a *symbol argument* rather than at an identifier
token. The outline points at that argument: every name a macro declares
gets its own entry, and each entry selects the token it was declared
from — which is not always its own name. `attr_accessor :alpha` writes
one token and declares two methods, so `alpha=` selects `alpha`; an
`enum` predicate `active?` selects the label `active` it is derived
from. **Rename does not edit that token, and refuses instead.**

That argument is source the macro reads, not the method's name, so
rewriting it is a different edit from renaming. `attr_reader :name` also
names the `@name` it reads, so a rewrite gives you a reader of an ivar
nothing assigns — a file that still runs and answers `nil`.
`attr_accessor :name` declares `name=` from the same token, so one edit
renames two methods and only one method's call sites are in the plan. In
`enum status: { active: 0 }`, `active` is the label and `0` is what the
column stores; the same label is also the scope `Order.active` and the
key in `Order.statuses`. `delegate :name, to: :company` names
*`Company`'s* method, which the rename must leave alone.

`scope :recent` and `define_method(:calc)` are the two shapes where the
argument really is just the name, and they are refused with the rest:
nothing at the point of refusal says which macro declared what. VS Code
shows its own "cannot be renamed" message; the reason reaches the Core
log only (024.28). <!-- documents: 024.28 -->

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

## What rename does that it should not

Rename and Find References are listed as working, and there are shapes
where they are not. Most of these were found in 0.2.16's closing
measurement by driving the product, and none of those had been reported
before; the first three below were found in 0.2.17, by renaming every
local in a thousand files of real gem source and running what came out.

- **Renaming a local that is a method or block parameter leaves the
  parameter behind**, so the renamed method stops working — and where
  the body assigns before it reads (`names = names || []`), nothing
  raises and the method quietly answers something else. This is the
  largest of the shapes here by a long way: renaming every local across
  1,043 files of Rails and i18n source leaves 58 renames that change
  what the file means, and 57 of them are
  this. <!-- documents: 024.273 -->
- **Renaming a local bound by a regexp named capture leaves the capture
  behind**, and this one fails silently: `/(?<where>...)/ =~ line` binds
  `where`, the capture inside the regexp is not rewritten, and the
  renamed name becomes a defined-but-nil local — so a guard on it goes
  false and nothing raises. It is the 58th of the
  58. <!-- documents: 024.280 -->
- **A binding whose name begins with an underscore is left behind**
  when it is written as a multiple-assignment target, a `for`
  variable, a `rescue => _e` or a pattern. Ruby lets one pattern bind
  such a name twice, and two edits that are each correct would then
  make the file stop parsing, so none is
  made. <!-- documents: 024.274 -->
- **The first rename of a session is refused if nothing else has been
  asked yet**: press F2 straight after opening a file and the rename does
  not start, while using Find All References once makes the same position
  work. That is one line away from being fixed
  and is being kept on purpose until the shapes above are, because it is
  what stops a local-variable rename being one keystroke
  away. <!-- documents: 024.245 -->
