# Changelog

[日本語版](CHANGELOG.ja.md)

All notable changes to the OvalLSP VS Code extension are documented here.
Each release leads with what changed; the reasoning, the measurements and
the disproved approaches are kept below it under **Details**.

## 0.1.12 — The rule that kept being rewritten, and a privacy list that under-described itself

- Fixed: `send`, `__send__`, `public_send` and `instance_exec` are no
  longer reported as unknown methods.
- Fixed: `::User.find(1)` resolves to `User`, as `User.find(1)` already
  did. A root-scoped model receiver lost its type, and the Active Record
  method check went quiet for it.
- Fixed: signature help no longer shows `()` for a method that takes
  keywords. `Array#shuffle` read as taking nothing.
- Fixed: signature help no longer tells you to type `x:` for a method
  declared in a Sorbet `.rbi` that takes plain positional arguments.
- Fixed: a class written `< ::BasicObject` no longer has its unknown-method
  check silently switched off. As in 0.1.11, a class that was silent may
  now start reporting mistakes it was quietly ignoring.
- Fixed: a namespaced class no longer borrows a same-named top-level
  model's data. `Admin::User#name`, delegated to `:company`, was answered
  from the top-level `User`'s associations — a confident wrong type, not
  a missing one.
- Fixed: `self` and `Widget.new` now have the same type inside `Widget`.
  They did not, so a variable assigned from both became a union and the
  unknown-method check went quiet for it — as it did for `::Widget.new`.
- Fixed: go-to-definition on an Active Record column or association
  reaches models written `module Admin; class Company`, not only those
  written `class Admin::Company`.
- Fixed: a Sorbet `.rbi` declaring `def f(...)`, `def f(**nil)` or a
  destructured `def f(a, (b, c))` keeps its signature. Introduced and
  fixed inside this release; no published version shipped it.
- Fixed: `PRIVACY.md` now describes everything type observation records.
  It recorded more than it said — nothing sensitive, but a privacy
  document that under-describes itself is wrong whichever direction the
  gap runs in.

A patch release under the versioning rule in `docs/PUBLISHING.md`: no
capability is added.

### Details

0.1.11 moved one rule — "an owner name is qualified" — into `SymbolId`
and routed every caller through it. Two copies survived, both because
they build no `SymbolId` at all, and only one of them had a symptom.
`chain_reaches_root?`
asked `entry.name == "BasicObject"`, and a class written
`< ::BasicObject` produces an entry carrying the `::`. Its chain was
judged not to reach the root, the receiver was not "closed", and the
check went quiet for that class without saying so. Written by hand, one
spelling, exactly like the eight before it — and `ROOT_SUPERCLASS_NAMES`
one subsystem over already listed both forms, which is what makes it an
oversight rather than a decision. The second copy was
`Server#find_controller_uri`, prefixing `::` by hand before a lookup;
measured, both of its callers already pass a qualified name, so it never
misbehaved and nothing could ever have caught it if it had. It now
delegates — and the normalisation moved into the lookup itself, which is
the only place that knows what shape its own keys are.

The `send` family is a separate defect the `::BasicObject` fix made
urgent. RBS writes "takes anything" as `(?)`, and models it as a function
object carrying no parameter lists at all. Two different declarations run
into it: `Proc#call` and `Method#call` are `(?)` themselves, while
`send`, `__send__`, `public_send` and `instance_exec` have ordinary
signatures carrying a `(?)` *block* — spelled `?{ (?) -> untyped }` for
the first three, and `{ (?) [self: self] -> U }` for `instance_exec`,
whose block is required and self-bound. Both converters asked
such a function for its positional parameters regardless, the resulting
error was swallowed by the blanket rescue around signature building, and
the method came back as "no signature" — which the unknown-method check
reads as "RBS does not declare this". So `send` was reported on every
closed receiver. It became urgent because `__send__` is
core idiom in exactly the proxy and delegator code people write
`< BasicObject` for: the fix above would have turned a false report on
precisely the classes it un-silenced.

The privacy list said observation records "class/module name, method
identifier, parameter position, call count, and whether the call raised".
It also records the set of classes seen *at* each parameter position, the
set of classes the method returned, a digest of the file the method is in
together with its line number (used only to notice that the method may
have been edited since), an identifier for the run, and the time the run
finished. None of that is a value from your program —
the distinction the document now makes explicitly is class *names* versus
the objects themselves: `User` is recorded, the user is not. The
guarantee never changed; the list of what it covers was incomplete.

A second correction to the same document matters more than the list did.
It said nothing is written to disk beyond the parse cache. An observation
run writes two temporary files, and one of them is where your own test
command's stdout and stderr are redirected — which in a Rails app
routinely contains SQL. OvalLSP neither reads nor keeps that log, and it
is unlinked when the run ends, but "nothing is written to disk" was not
true while it existed. The document now says what those files are, and
draws the line the old text left implicit: the "never records" guarantee
is about what OvalLSP extracts and keeps, not about what your own suite
prints.

The gap was found by an independent check of the project's own website —
which turns out to describe less than the privacy document did, not more.
Neither was right; the website is now on the list of pages this release's
own documentation map says a change like this makes stale, and it still
carries the two claims corrected here. The disk claim was found by a
reviewer reading the observation runner rather than the document.

Rounds 3 and 4 found three more instances of this release's own subject.
`::User` never matched `ModelRegistry`, which is keyed by Rails' bare
`model.name` — normalised in the registry's four lookup methods rather
than at the twenty-two call sites — twenty lines, across five subsystems —
that use them; for the reason 0.1.11 exists. `LocalInferencer` built `::`-prefixed
Nominals in three more places — a constant receiver, the Active Record
class-level finder, and an `is_a?` narrowing. And `MethodAnalyzer` matched a delegate's owner by *simple
name*, so `Admin::User` borrowed the top-level `User`'s associations.
Separately, the signature label, fixed in round 2 for `*rest`, still
asserted zero arity for anything keyword-only.

Round 3 also caught two things this release had said about itself that
were wrong. The newly-written privacy sentence claimed a call that raised
"contributes nothing", when it contributes its count and its parameter
classes and only the return type is withheld. And a note claimed two
fields could not be pinned — written after a mutation that silently never
applied. Both corrected. The second is worth naming: a sweep result is
worth exactly what the edit behind it was, and that one was worth nothing.

Round 5 found two more places carrying the same rule by hand, both in code
the earlier rounds had read, and a third defect of the same family. `MethodAnalyzer` built a
type straight from `::Widget.new`'s source spelling — the exact line
rounds 3 and 4 had fixed in `LocalInferencer`, one subsystem over,
untouched —
and gave `self` the *index's* spelling of its owner, so `self` and
`Widget.new` were two different types inside the same class. Both make a
union where there should be one Nominal, and a union is what switches the
unknown-method check off. Neither had a symptom anyone would report: the
check simply stops finding things.

That third one is the go-to-definition bullet above. `QueryService` looked
a model's class up by rebuilding a `SymbolId` with `owner: nil`, and an
owner is recorded *lexically* — `module Admin; class Company` indexes
under owner `::Admin`, so the reconstructed key matched only the compact
`class Admin::Company` spelling. Jumping to an Agent-backed column or
association silently returned nothing for every model written the ordinary
way. It now asks `WorkspaceIndex` by qualified name, which is the same move
`find_controller_uri` made earlier in this release.

The RBI defect round 5 found is the one worth reading twice, because this
release caused it. Sorbet's `params(x: Integer)` is a name-to-type map;
it describes `def f(x)` and `def f(x:)` identically, and the parser filed
every entry as a required *keyword* with a comment saying this was only
"for arity matching purposes". Nothing rendered keywords, so nothing
showed. Then this release taught the signature label to render them — and
a method declared `def combine(x, y)` began telling the user to type
`x:`. The label was not the bug; it made an existing lie legible. The fix
is the one the comment had deferred: the `def` under the sig is the
authority on parameter shape and the parser has always had that node, so
shape now comes from the def and type from `params(...)`. That also
corrects arity in both directions — a `sig { void }` over a
two-argument method used to claim it took nothing.

Two counts this release published were wrong, both mine. "Its four
callers" counted methods on the registry, not callers. And the
keyword-only signature count was given as 29; it is 26 methods, or 30 if
each overload counts separately, and 29 is neither. Corrected to say
which is being counted — the number was only ever there to show the shape
is common rather than exotic, and a number that needs an unstated filter
to reproduce does not show that.

Round 6 found that round 5's own RBI fix had broken three legal parameter
forms. Reading shape from the `def` means meeting the whole of Ruby's
parameter grammar, and `def f(...)`, `def f(**nil)` and a destructured
`def f(a, (b, c))` all put a node in the list that answers no `#name` at
all. Asking raised; `handle_sig`'s blanket rescue turned that into a
warning; the method's signature was dropped entirely. A `.rbi` that
parsed before this release stopped producing hover, signature help and a
declaration for those methods. This is the one genuine regression in
0.1.12 and it existed only between rounds 5 and 6. `...` now opens both
rest slots, `**nil` closes the keyword one, and a destructured parameter
keeps its positional slot typed Unknown.

Round 6 also read the release's own title and found it false. "The last
copy of the rule" was written when one copy was thought to remain, and
later rounds kept finding more. It corrected two attributions with it —
the `LocalInferencer` fix credited to round 1 belongs to rounds 3 and 4,
and "round 3 found two more instances" was three — and routed three more
`LocalInferencer` sites through the shared helper. Two of those three
were byte-equivalent refactors; the third had no normalisation at all,
and could not change an answer only because every consumer normalises on
its own.

Round 7 then falsified the *replacement* title. "Every remaining copy"
lasted a day: a grep found ten hand-written copies of one direction of
the rule or the other still in the tree, and one of them — `ModelRegistry`'s
`lookup_key` — had been written by this very release. Four were
byte-identical copies of a lexical-qualify method, in `ParserService`,
`LocalInferencer` twice, and `RbiParser`. So the title no longer claims a
count, and `Index::SymbolId` now owns all three directions:
`qualify_owner`, `bare_name`, and `qualify_within`. Every one of the ten
delegates to it, including `ReceiverResolution.canonical_receiver_name`,
whose old body was one of the one-liners. Nothing changed behaviour —
1275 examples green across the consolidation — which is the point: the
copies were not wrong, they were waiting to be.

Round 7 also found the fifth wrong number this release has published.
"Twenty-one call sites" was mine, written one round after correcting
"four callers", and it is twenty-two expressions across twenty lines.
And it found something better than a wrong number: a normalisation site I
had personally declared unobservable was observable. Hovering `k` in
`k = ::Widget` read `ClassOf[::Widget]` where `k = Widget` read
`ClassOf[Widget]` — a user-visible difference no test could see. Pinned
now, along with `class_declarations`' untested `module` branch. Two lines
went the other way and were deleted rather than pinned: a nil guard and a
ternary whose two arms produce the same string.

## 0.1.11 — One rule, restated everywhere and remembered nowhere

- Fixed: a method your project declares only in its own `sig/` is no
  longer reported as an unknown method.
- Fixed: a root-scoped constant reference (`::JSON`, `::Rails`) is no
  longer reported as unresolvable.
- Fixed: the unknown-method check was silently switched off for any class
  written with `include ::SomeModule`. It now runs there, so such a class
  may start reporting mistakes it was quietly ignoring.
- Fixed: a method your workspace adds by reopening a core class
  (`lib/core_ext/object.rb`) is resolved, offered in completion, and no
  longer reported as unknown — while a private one there stays out of
  completion.
- Fixed: two threads publishing at the same moment could put one
  message's `Content-Length` in front of another message's body.

A patch release under the versioning rule in `docs/PUBLISHING.md`: no
capability is added. None of these is a regression — they trace back to
before 0.1.5, so every release so far has shipped with them. They were
found while building 0.2.0 and are fixed here rather than left waiting
for it.

### Details

The first two are the report this check exists not to make: one on code
that runs. The signature environment resolves a *qualified* name, and the
names reaching it arrive both ways — `HierarchyIndex` returns a class's
own ancestry entry already qualified (`::Widget`) and its inherited ones
bare (`Object`), while a constant reference carries whatever the source
wrote. Prepending `::` rather than normalising it asked for `::::Widget`
and matched nothing. Describing a class in RBS without also writing the
method in Ruby is ordinary practice, and `::JSON` is ordinary Ruby; both
were reported.

The rule was written out in eight places across the codebase. Three of
them had it inverted, and two more places that needed it did not have it
at all — those two were found by review, after the first fix, in the index
and in the method resolver.

It is now stated once, on `SymbolId`, which is the thing that knows what
an owner is, and every other place delegates to it. The lesson is worth
stating plainly: a rule restated at each call site is a rule that will be
written wrong somewhere, and counting how many places had it wrong is how
this release found the ones nobody had reported yet.

The second was reachable whenever diagnostics were republished from a
background thread — the Runtime Agent becoming ready, a restart, a routes
or models refresh, a deferred ancestry answer landing — while the
dispatch thread was answering a request. A frame left the writer as two
`write` calls with nothing serialising them, so the header of one message
could land in front of the body of another. That is the one framing error a client cannot recover
from: it resynchronises by guessing.

A frame is now both serialised and written in one call, which are two
different requirements. The mutex gives the first, and is what makes a
partially-written frame unobservable to a client. The single call gives
the second, which a mutex cannot: it is no defence against `Thread#kill`,
and the bounded join at shutdown kills exactly the threads that publish.

## 0.1.10 — One implementation, and four behaviours brought under test

- Fixed: the controller `before_action` chain has one implementation
  again. A second, unused copy of the same rule sat next to the one that
  runs, so a fix to either could silently miss the other.
- Changed: the extension's client shutdown logic moved out of the module
  that cannot be unit-tested, and is now covered by tests.
- Fixed: on macOS, a Runtime Agent left behind by a Core that died during
  its first ~57ms is now terminated instead of leaking.
- Changed: the Cold Index test now actually covers a file open in a
  buffer.

A patch release under the versioning rule in `docs/PUBLISHING.md`: no
capability is added. It clears the last four defect entries from
`docs/design/tasks/024-deferred-review-findings.md` (024.1, 024.6,
024.8, 024.10), leaving only roadmap items and 024.13.

### Details

The duplicate callback chain was the expensive kind of duplication: both
copies were correct, so nothing was visibly wrong, and a regression test
written against the wrong one pinned nothing about the path that
actually runs. Deleting it cascaded through `#infer_ivars_for_method`,
`#find_static_render_target`, `#find_method_node` and the `MethodLocator`
visitor, which existed only to serve it.

Its tests were not deleted with it. Those covering pieces the server
still calls were re-anchored onto exactly those pieces. Seven behaviours —
`except:` on both sides of it, an action overriding a callback's
assignment, an `if:` condition that cannot be resolved statically, a
conditional `skip_before_action`, a missing callback method, and the
multi-name forms of `before_action` and `skip_before_action` — had no
equivalent on the live path at all, so they were rewritten as end-to-end
tests against the server. Each of those seven fixtures was then checked
to produce a *different* answer under the opposite behaviour, because a
fixture that cannot tell the two apart passes either way.

The macOS leak was found while trying to *remove* the two lines that
cause it, on the belief that they could not change any answer. They can —
removing them is the fix. When Core exits, the tracker retires its
polling; it used to retire its pid-derived ownership at the same moment,
and the argument for deleting that was that the branch is only reached
once the root is known absent, by which point ownership grants nothing.
Neither half is true — the absence flag is set at the end of the pass,
and the root row can be present and still untracked, since a root is only
tracked while the child is alive. A Core that dies before
`core-session.rb` reaches `setsid` lands exactly there, and on macOS
nothing else identifies its rows (`ps -o sess=` reports 0 for every
process). Ownership was then retired permanently, while the passes that
do the actual killing run afterwards. The removal stands, with a
regression test that fails if the session-id retirement returns. (Its
group-id twin was removed alongside it for symmetry; that half provably
cannot change an answer, so no test can pin it.)

`extension.ts` imports `vscode`, which the unit suite cannot load, so
anything living there was verified only by hand. Four decisions were in
that position — three about not leaving an orphaned Core process behind
(awaiting the client's stop rather than firing it off, draining
outstanding process retirements when a folder has no tracked generation,
and refusing to start a server for a workspace folder added while the
host is already shutting down), and one about which restart the user is
told about. They now live in a module that imports nothing from `vscode`.
Each was verified by mutating it and confirming the suite goes red.

The last of those took two attempts worth recording. Exporting the two
notification strings for `extension.ts` to pick between pinned the
wording and nothing else: the pairing of command to message stayed at the
call sites, where swapping it left the suite green. What is pinned now is
the absence of a choice — each command names its id once, and its
confirmation is looked up from that same id. Which *action* each command
runs is still ordinary `vscode` code, verified by hand like the rest of
it.

## 0.1.9 — Three corrections in the type engine

- Fixed: a hash literal renders like every other container. `{}` and
  `{a: 1}` said `Hash` while `[]` said `Array[Unknown]` and `Hash.new`
  said `Hash[Unknown]` — spellings of the same kind of value, two
  answers.
- Fixed: a project signature that says `untyped` no longer switches the
  method off. Writing `def self.build: (...) -> untyped` in your own
  `sig/` made every call to `build` resolve to nothing, instead of
  falling through to what the source says.
- Fixed: reading a `before_action` no longer consumes its own
  `only:`/`except:` selector.

A patch release under the versioning rule in `docs/PUBLISHING.md`: no
capability is added. It clears three entries from
`docs/design/tasks/024-deferred-review-findings.md` (024.12, 024.3,
024.4).

### Details

The container rendering is fixed in two places, not one. Correcting only
the literal would have moved the inconsistency a single call away —
hovering `{}` and hovering a method that returns `{}` would then have
disagreed — so the method-summary analyzer produces the generic form too.

The `untyped` case was already handled correctly for `.new`, which
filtered a no-information answer out and carried on. Every other
singleton call returned it. Nothing reaching that point can carry
information, because the guard above it already returned every signature
answer that did, so the fix is to stop returning there at all.

Rendering a hash literal as a container has one consequence worth
stating: the unknown-method and argument-count checks ask for a plain
class name, so a hash-literal receiver is no longer checked. On a
workspace that reopens `Hash`, `h = {}; h.totally_bogus_method` was
reported and now is not. The same gate also reported
`{}.deep_symbolize_keys` — ActiveSupport's, absent from stdlib RBS — as
unknown, so the false reports go with the true ones. Admitting these
receivers properly needs to tell "the workspace declares part of this
class" from "the workspace owns it", which is tracked as 024.13.

The `before_action` mutation was harmless today and only today: `pop`
operates on the array Prism owns, so reading a declaration destroyed its
own selector, and nothing noticed because every caller happens to re-parse
the document first. That is a property of the callers, not of the code —
the first thing to cache or re-walk a tree would have inherited a silent
wrong answer. It is pinned through the consequence rather than by
inspecting the node: visited twice, the same tree must say the same thing,
and it did not.

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
rules to dispatch on, which matters for `Array` and the Active Record
collections — the rules have no entry for `Hash` or `Set`, so for the two
types this correction is named after that was not the reason.

One consequence is worth stating because it changes what you see: a value
that may be one of several types now counts a container member honestly.
`x = flag ? User.new : []` followed by `x.name` is a call the receiver may
not have, so it no longer appears in Find References and is not rewritten
by Rename. 0.1.7 listed it, on the strength of ignoring the `[]` branch.

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
