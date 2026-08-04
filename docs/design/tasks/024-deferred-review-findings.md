# Task 024: Deferred review findings

Findings from independent review that were deliberately **not** fixed in
the change set they were found in, because fixing them would have widened
that change set beyond what its own goal required.

**This is the single place deferred findings are collected.** Do not open
a second file, and do not scatter `TODO` comments through the source for
them — an item that is worth deferring is worth being findable in one
place. Append new entries here; remove an entry only when it is actually
fixed, and say in the fixing commit which entry it closes.

Each entry states the symptom, who it affects, how to reproduce it, and a
proposed direction. Nothing here is a shipping blocker; every item was
triaged as such by the reviewer that raised it.

Status legend: **open** — not started. **fixed** / **done** — resolved.

A resolved entry is deleted once nothing in the tree cites it. It is
**not** deleted while source or spec comments still name it by number:
those comments say "this is the way it is because of 024.N", and the
number is the only way to reach the reason. Every resolved entry below
was checked against a repo-wide grep and is cited — 024.1 from
`server_views_spec.rb` and `local_inferencer_spec.rb`, 024.6 from
`cold_indexer_spec.rb`, 024.8 from `coreProcess.ts` and its unit test,
024.10 from `extension.ts`, `clientTeardown.ts` and
`clientErrorNotifications.ts`, 024.R5 from fifteen places including
`ancestry_registry.rb`, which says its measurements "are recorded in
024.R5".

The legend previously promised deletion "at the next release" with no
such exception, and four entries — fixed in 0.1.10, so due for deletion
in 0.1.11 — then sat a release past that deadline because deleting them
would have broken live references. Round 5 of the
0.1.12 review reported the entries as stale; the deadline was the part
that was wrong. Run the grep before deleting, not the calendar.

Entries numbered `024.R*` are roadmap items rather than defects: work
that is understood, deliberately not scheduled for the current release,
and too large to fold into one. They live here rather than in a separate
roadmap file for the same reason everything else does — one place.

---

## 024.1 Duplicate, unused implementation of the controller callback chain

**Status:** fixed in 0.1.10 — the unused copy is deleted, along with
`#infer_ivars_for_method`, `#find_static_render_target`, `#find_method_node`
and the `MethodLocator` visitor that existed only to serve it. Its specs
were re-anchored rather than dropped: the ones covering pieces the Server
still calls now go through those pieces (`method_nodes` +
`#infer_ivars_for_method_node`, `#static_render_target_for_node`), and the
seven chain behaviours that had no equivalent on the live path — `except:`
on both sides of it, an action overriding a callback's assignment, an
unresolvable `if:` condition, a conditional `skip_before_action`, a
missing callback method, and the multi-name forms of `before_action` and
`skip_before_action` — were ported into `server_views_spec.rb`, where each
fixture was checked to yield a *different* answer under the opposite
behaviour.
**Area:** `core/lib/ovallsp/local_inferencer.rb`, `core/lib/ovallsp/server.rb`

`LocalInferencer#infer_ivars_for_action` implements the before_action
chain rule (build the effective callback list, evaluate each callback,
then the action, sharing one step budget). `Server#infer_controller_action_ivars`
implements the same rule again, over its own inheritance-aware method
maps. Only the Server copy runs in production; the LocalInferencer copy
has no caller in `lib/`.

Two same-shaped implementations of one rule means a fix to either can
silently miss the other. This was found the expensive way: a regression
spec written against the LocalInferencer copy pinned nothing about the
path that actually runs, and the production budget-sharing decision was
left untested until round 14 caught it.

`#infer_ivars_for_method`, `#find_static_render_target`, `#find_method_node`
and the `MethodLocator` visitor exist only to serve that unused copy and
its specs.

**Direction:** delete the unused copy and re-anchor its specs onto the
Server path, or make the Server call the LocalInferencer copy so there is
one implementation. Deleting cascades into `MethodLocator`, so it is not a
one-line change.

## 024.6 The `seen_uris` spec's comment overclaims

**Status:** fixed in 0.1.10 — the buffer case is now a spec of its own,
so `@seen_uris << uri` sitting above the open-buffer early return is
pinned rather than merely claimed.
**Area:** `core/spec/ovallsp/cold_indexer_spec.rb`

The comment says the spec covers a file already open in a buffer, but no
`DocumentStore` entry is created, so that branch is never exercised.
`@seen_uris << uri` sits above the open-buffer early return and nothing
pins that ordering. No live consequence: the deletion sweep verifies
absence with `File.file?` rather than trusting `seen_uris`.

**Direction:** add the buffer case, or trim the comment to what the spec
actually asserts.

## 024.8 Ownership retirement on `exited() && known.size === 0` is unpinned

**Status:** fixed in 0.1.10 — the two assignments are deleted; the
`ownedSessionId` one is load-bearing and pinned by a new regression test,
and `ownedGroupId` went with it for symmetry (it is set only from a
validated root row whose `pgid === pid`, and such a row also satisfies the
expansion test against `ownedSessionId`, so `known` cannot be empty in the
same pass — no fixture distinguishes that half). The first attempt at this
entry deleted them as unable to change any answer, reasoning that the
branch is only reached with the root absent and the expansion gate
therefore already closed. Independent review disproved both halves:
`rootObservedAbsent` is assigned at the *end* of the pass, and the root
row can be present but untracked, because `known` only takes the root
while the child has not exited. A Core dying inside the ~57ms pre-`setsid`
window reaches the branch with ownership still meaningful — on Darwin
especially, where `sid` is 0 on every row. Since `terminateOnce` and
`waitForAllExit` both refresh after the interval is cleared, retiring
ownership there permanently lost the survivor those later passes exist to
catch. The `clearInterval` in the same branch stays, pinned by its own
test.
**Area:** `vscode/src/coreProcess.ts`

As originally recorded, and wrong in its premise — kept here because the
reasoning is the point: "Clearing `ownedSessionId`/`ownedGroupId` there is
defence-in-depth: the expansion gate already prevents the failure it
guards against, and no concrete failing scenario could be constructed for
its removal. Recorded because unpinned behavioural lines count as defects
in this project." A scenario *can* be constructed; see the status above.

**Direction (superseded, recorded with the premise above):** a test, not a
code change — or delete the lines if the invariant is genuinely carried
elsewhere. Neither applied: the lines were deleted because keeping them
was actively harmful, not because the invariant was carried elsewhere.

## 024.10 Four `extension.ts` behaviours cannot be unit-tested

**Status:** fixed in 0.1.10 — the four decisions moved into
`vscode/src/clientTeardown.ts`, which imports no `vscode` and takes the
lifecycle manager and the per-folder maps as parameters rather than
reading module state. `extension.ts` now delegates to it and keeps only
the `vscode` wiring. Fifteen unit tests cover them, and each decision was
checked by mutating it and confirming the suite goes red.

The fourth took two attempts, and the first one is worth recording:
exporting the two notification strings for `extension.ts` to choose
between pinned the *wording* while leaving the command-to-message pairing
at the call sites, where an independent reviewer swapped it with the
suite still green. What is pinned now is that there is no choice — each
command is registered through a helper that names its id once and looks
the confirmation up from that same id. What a command *does* is still two
hand-written bodies in `extension.ts` — swapping those would still restart
the wrong thing — so the confirmation is what this pins, not the whole
command.
**Area:** `vscode/src/extension.ts`

`extension.ts` imports `vscode`, which the unit suite cannot load, so
these four are covered only by manual verification: awaiting
`client.stop()` rather than firing it off, `stopClient` draining
retirements for an untracked generation, the shutdown-barrier check when
a workspace folder is added, and the restart notification wording.

**Direction:** extract the testable logic out of the `vscode`-importing
module, or add an integration test host.

## 024.34 `attr_*` inside a `def` inside `class << self` is kinded singleton

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`record_attribute_methods`)

`singleton = @singleton_context_stack.last` asks "would an unqualified
`def` here declare a singleton method". Inside a `def` nested in
`class << self` that is still true, but the `attr_accessor` runs when the
method is *called*, with the class object as self — so Ruby defines
**instance** methods:

```ruby
class S
  class << self
    def build
      attr_accessor :attr_x     # Ruby defines S#attr_x, not S.attr_x
    end
  end

  def use = attr_x              # reported: "S has no method named `attr_x`"
end
```

Confirmed against the interpreter: after `S.build`,
`S.new.respond_to?(:attr_x)` is true and `S.respond_to?(:attr_x)` is
false. Reported on 0.1.13, 0.1.14 and 0.1.15 alike — a false positive,
which is the unsafe direction.

This is the same reasoning 0.1.15 applied to `block_self_is_module`, and
the sibling decision two hundred lines away did not get it. It is
recorded rather than fixed because 0.1.15 exists to correct 0.1.14, and
this predates both — 024.29 is the entry about what happens when a
release takes on scope beyond its own purpose.

Real code has the shape:
`activerecord/associations/builder/has_and_belongs_to_many.rb:16-20`,
`csv/parser.rb`, `cgi/core.rb:522`, `devise/models.rb:32`.

**Direction:** the same predicate `block_self_is_module` now uses —
`!@in_method_body && @singleton_context_stack.last`. Cheap, but it is a
behaviour change on its own, so it wants its own corpus run in both
directions rather than a ride on a correction release.

## 024.33 `K.instance_eval { attr_accessor :x }` is reported; `K.class_eval` is not

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`block_self_is_module`)

Both define `x` and `x=` on `K`. The first is reported as
`... has no method named attr_accessor`, the second is not, because
`instance_eval` takes the "explicit receiver means an instance" path and
`class_eval` takes the inherit path.

Not a regression -- 0.1.14 reported it too -- and the receiver rule it
comes from is right for the case it was written for: `o.instance_eval do
helper end` on an object must not resolve against the class's singleton
side.

A three-way split was written and dropped. The visitor tracks *whether*
self is a module, never *which* module, so the "constant receiver means
the class" branch would still resolve against the lexically enclosing
owner rather than the receiver -- and no fixture could tell the two
apart, which is its own reason not to ship it.

**Direction:** the same one 024.31 needs. A block wants a receiver, not a
boolean; with that, `K.instance_eval` opens `K` and this answers itself.
Worth doing with 024.31 rather than separately.

## 024.32 `def Foo.bar` is recorded as an instance method, so both answers are inverted

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`visit_def_node`)

`visit_def_node` treats a `def` as singleton only when its receiver is a
`Prism::SelfNode`. `def Foo.bar` names a constant instead, so it is
recorded as `Foo#bar` — an instance method. Both consequences are wrong,
in opposite directions:

```ruby
class Foo; end
def Foo.bar; end

Foo.bar        # reported: "Foo has no method named `bar`" -- Ruby runs it
Foo.new.bar    # accepted    -- Ruby raises NoMethodError
```

Pre-existing and identical on 0.1.13, 0.1.14 and 0.1.15. **106**
occurrences of `def Const.method` in Ruby 3.4.7's standard library,
counted with Prism. Matching every stdlib `unknown-method` report's
receiver and method name against those declarations, **56** of them are
this -- on 0.1.15 and 0.1.14 alike, 59 on 0.1.13. An earlier draft of
this entry said six, which was a hand count of one file rather than a
measurement, and it understated the case for fixing this by roughly nine
times. Among them `PP.mcall`, `Ripper.lex`, `IRB::Frame.top`,
`IO.console_size`, `Net::HTTP::Proxy`, and `Bundler::Deprecate.skip`
(`bundler/shared_helpers.rb:391`), `CGI::Session.callback`
(`cgi/session.rb:345`) and three in `fiddle/struct.rb`.

**Direction:** the owner is already computed correctly a few lines below
(`constant_full_name(owner_receiver)`); it is only the `kind` that reads
`SelfNode` alone. Both should ask the same question. Worth checking what
else keys on that predicate before changing it — `visit_def_node` also
uses it for the declaration's visibility, which is `nil` for singleton
methods.

## 024.31 A declaration written inside a block has no owner this parser can name

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`record_attribute_methods`,
`visit_def_node`)

A block can change the receiver its body runs against — `Class.new do`,
`Struct.new do`, `included do`, `class_eval do`, `concerning do`,
`instance_eval do` all answer differently, and `builder.call do` answers
something this file cannot see at all. The visitor attributes everything
it finds to the lexically enclosing owner, which is right for some of
those and wrong for others.

**This entry exists because three attempts to be cleverer than that each
made things worse, and each was found by the review round after it.** All
three were confined to `attr_*` while `def` kept the lexical answer, and
a block holds both:

1. **Skip every block.** Turned every ActiveSupport::Concern's
   `included do attr_accessor :tracked_at end` into
   `Order has no method named tracked_at` — a false report on the most
   ordinary Rails code there is.
2. **Skip only anonymous-class builders** (`Class.new`, `Struct.new`,
   `Data.define`, `Module.new`). ActiveRecord builds its
   habtm association class as
   `Class.new(Base) { class << self; attr_accessor :left_model; end; def self.compute_type; left_model; end }`.
   Dropping the `attr_accessor` while `def self.compute_type` kept the
   enclosing owner produced three reports on `activerecord-8.1.3`.
3. **Skip method bodies.** The same shape, written inside a `def`, has
   the same asymmetry for the same reason.

The rule now is the one `def` has always had: **attribute to the
lexically enclosing owner, everywhere, with no exceptions.** Consistency
is what avoids the false reports; the residual cost is a declaration
recorded against an owner that may not be its real one, which offers a
member in completion that is not there and silences a report rather than
inventing one. That is the direction this engine chooses everywhere else,
and it is what shipped in 0.1.14 and every release before it.

Two consequences a user can see, both pre-existing and both now
deliberate:

- `Struct.new(:x) do attr_reader :label end` inside `class Outer` offers
  `label` on an `Outer`, and go-to-definition on it lands in the block.
- `def setup; attr_accessor :never_real; end` records `never_real`, so a
  call to it is not reported. Ruby cannot define it by any path here --
  `attr_accessor` is `Module`'s and `self` inside an instance method is
  not a module, so `setup` raises `NoMethodError` when called. This is
  the one example where the parallel with `def` does *not* hold: a nested
  `def` in the same position really does define the method once `setup`
  runs. The parallel the decision rests on is the block case above, not
  this one.

**Direction:** the fix is not a longer allowlist — that is what these
three attempts were, and the fourth would be too. It needs the visitor to
carry a *receiver* for a block rather than a boolean, so that
`Class.new do` opens an anonymous owner, `included do` opens the
includer, and an unrecognised builder opens an unknown owner whose
declarations are recorded against nothing. That is a change to what an
owner *is*, which is why it belongs to its own task rather than to a
patch release correcting something else.

Until then, do not add a name to any block allowlist without a corpus run
in both directions across ActiveRecord and ActiveSupport, and without
asking what `def` in the same position does.

## 024.30 0.1.15's hunk sweep: three hunks that cannot be pinned, and why

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  A record of which lines no test holds, and the reasoning for leaving
  each. Nothing here changes what the engine answers.
```

Reverse-applying each of 0.1.15's 24 `core/lib` hunks against a green
baseline: **21 caught, 3 survived**, the tree verified byte-identical
after every one. The survivors, and what was done about each:

- **The deleted `new` special case** (`diagnostics/engine.rb`). Restoring
  it changes no answer, because the `Class` tail now resolves `new` for
  every class. It only ever suppressed reports, and no receiver exists
  for which `new` *should* be reported, so there is nothing to assert.
  Deleted rather than tested, which is what CLAUDE.md prescribes for a
  decision that cannot be pinned. The corpus runs are the evidence: zero
  reports introduced over the standard library, ActiveSupport and this
  repository's own `core/lib`. A later round measured a wider Rails set
  and found three reports from a different cause (024.31), so "three
  Rails gems" as this entry first put it was not a claim those runs
  supported.
- **`rbs_resolves?` delegating to `AncestorEntry#declaration_kind`**
  (`diagnostics/engine.rb`). Not a behavioural decision — it is the
  removal of a second, hand-written copy of a rule. The rule itself *is*
  pinned: reverting `declaration_kind` at its source fails three
  examples. The kind only differs for a `:class_object` or `:extend`
  ancestor, and for those the reference resolver answers before this path
  is reached, so no fixture can distinguish the call site. Left as is,
  because deleting the delegation would restore the duplication that made
  both copies wrong.
- **`@anonymous_class_depth = 0` in the visitor's constructor**
  (`parser_service.rb`). Defensive initialisation, not a decision.

That sweep was of a change set that no longer ships -- it ran before
024.31 withdrew the `attr_*` block rule -- and two unpinned decisions
inside `add_generated_method` were invisible to it, because reverse-
applying a hunk that adds a whole method only asks whether the method
exists. Both are pinned now.

**The shipped diff was swept at `3dc0011`: 25 hunks, 20 caught, 5
survived**, baseline green before and after, every file verified
byte-identical between hunks. The five:

- Two are **comment-only** (`MethodCandidate`'s origin list, and
  `WorkspaceIndex`'s note about which collections keep insertion order).
  A comment hunk changes the file, so the script scores it; it holds no
  behaviour to pin.
- Two are the ones above and unchanged in character: the **deleted `new`
  special case**, which is redundant-code removal, and **`rbs_resolves?`
  delegating to `declaration_kind`**, which removes a duplicated rule
  that is pinned at its source.
- One is **`@inline_attribute_visibility = nil` in the constructor**.
  Defensive: the ivar is read as `@inline_attribute_visibility ||
  @visibility_stack.last`, so an unset ivar and an explicit `nil` answer
  the same. Kept for the same reason as any other constructor default.

The diff has grown since: rounds six and seven each added a hunk to
`argument_count_findings` and `extract_parameters`, neither covered by
that run. Those were swept at the decision level instead -- each entry of
`declares_keywords`, the forwarding-parameter branch, and the
double-splat branch -- and each is pinned by an example that fails when
it is reverted. A hunk count is only true of the commit it was measured
at; this one is `3dc0011`'s.

One decision was unpinned, and is not any more. `block_self_is_module`'s
`node.receiver.nil?` term survived an 18-mutation sweep a later round
ran, because the example written for it put the explicit receiver inside
a `def` -- where `!@in_method_body` already answers, so the receiver term
never ran. The fixture writes it directly in `class << self` now, and
fails when the term is removed. Two sweeps missed it: the hunk-level one
because the term lives inside a method the diff adds wholesale, and the
decision-level one because its own fixture could not distinguish the
branches. Both blind spots are named in CLAUDE.md; meeting them together
is what let this line through twice.

**A fourth sweep guard, learned here.** A sweep that is *killed* mid-hunk
leaves the tree mutated. One run hit a timeout, left `engine.rb` missing
nine lines, and the next run's baseline check refused to score -- which
is guard 2 working, but only after the damage. The three guards detect a
broken tree; none of them stops a run from leaving one. The script traps
`EXIT INT TERM` and restores now. Budget for it too: 25 hunks at a
4.5-minute suite is nearly two hours, which is worth knowing before
starting rather than after.

## 024.29 Two features were written for 0.1.15 and cut from it

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Nothing shipped either way. What is open is whether these are worth
  building at all, which is a question about a future release rather than
  about anything a user can see today.
```

**Area:** was `core/lib/ovallsp/parser_service.rb` (`module_function`) and
`core/lib/ovallsp/server.rb` (`setter_suffix`, the writer completion
snippet), both removed before 0.1.15 shipped.

0.1.15 exists to correct 0.1.14. These two were written during it and are
not corrections of anything — they are new scope that rode along, and
each shipped a defect of its own that a review round then had to repair.
That pattern, not a wrong fix, is what made the release unstable. An
independent analysis of the thread recommended cutting them rather than
invoking CLAUDE.md's two-rounds rollback, on the grounds that the
corrections themselves had survived two review rounds untouched — the
rounds repaired only what had been *added*, never what had been
*corrected*, which is the opposite of 024.15's shape.

**`module_function` modelling.** Measured before cutting, over the 47
standard-library files that actually call it: this release and 0.1.14
produce **byte-identical output, 1,564 findings**, `comm` empty in both
directions. It changed nothing on real code. What it did do was introduce
a report neither 0.1.13 nor 0.1.14 makes:

```ruby
module Sample
  module_function
  def helper(a, b); [a, b]; end
end
Sample.helper(1, 2, 3)   # reported only with module_function modelling
```

It also leaked out of every construct it was written in — a later
`private` did not close the section, `class << self` pushed no frame, and
neither a method body nor a block was guarded — and recorded the instance
copy public where Ruby makes it private.

The one real report it removed, `::JSON.load(source, proc, opts)`, was
never `module_function`'s to fix: that report comes from the *ancestry
tail* 0.1.15 models, and it is fixed at that end instead, by declining to
judge arity against a declaration reached through a synthesised ancestor.
`module_function` was covering a symptom whose cause is elsewhere — which
is the clearest evidence it was the wrong shape.

**Hover and completion for writer methods.** `w.name = "y"` hovering as
the reader, and the writer completing as `w.name=(value)`. Small, real,
and it shipped `setter_suffix`, whose `rstrip` crossed newlines so that a
comment ending in a period made the next line's assignment look
receiver-qualified: go-to-definition on `LIMIT = 10` under
`# The maximum row count.` found nothing.

**Direction:** whichever release takes either up must justify it on a
corpus first. `module_function` in particular needs a measurement showing
it changes an answer a user sees; the one taken here says it does not.

## 024.26 A workspace `def Object.foo` is reachable from every class in Ruby and from none here

**Status:** open.

**Area:** `core/lib/ovallsp/semantic/hierarchy_index.rb`

Ruby's real singleton chain for a class `W` is
`[#<Class:W>, #<Class:Object>, #<Class:BasicObject>, Class, Module, Object, Kernel, BasicObject]`.
0.1.15 models the tail from `Class` onward, which is what class-body
macros need. It does not model `#<Class:Object>` or `#<Class:BasicObject>`
— the singleton classes of the root classes — because an `AncestorEntry`
names a type and has no way to say "the singleton class of that type".

A workspace that writes `def Object.foo` declares something every class
can call, and the check does not know it, so `Widget.foo` is reported.
That is a **false positive**, not a missed report — for an unknown-method
check a missing ancestor is the unsafe direction, and an earlier draft of
this entry had that backwards.

The fixture has to be `class Object; def self.foo; end; end`, not
`def Object.foo` -- the latter is recorded as an *instance* method
(024.32), which the new tail then resolves, so it is not reported at all
and demonstrates nothing about this entry.

It is not a 0.1.15 regression. Measured on the `def self.` form across
three revisions: 0.1.13 reports it, 0.1.14 does not, 0.1.15 reports it
again.
0.1.14's silence was an accident of the same mis-kinded lookup that made
it report `class Object; def blank?; end` — idiomatic Rails — on code
that runs. 0.1.15 trades the accident back for the fix. Nothing in the
standard library or the gems measured for it hits this shape.

**Direction:** the entry type needs a singleton flag before this can be
expressed at all. Worth doing with 024.13 rather than alone, since both
are about what a chain says when the workspace has reopened a core class.

## 024.27 `documentSymbol` lists one outline entry per name a macro declares

**Status:** open.

**Area:** `core/lib/ovallsp/server.rb` (`document_symbol_result`)

`attr_accessor :a, :b, :c` declares six methods, all at the same source
range, so the outline shows six children with byte-identical `range` and
`selectionRange` on one line. The names are right and each is genuinely a
method, so this is noise rather than a wrong answer — but an outline is
read by eye and six identical ranges read as a bug.

**Direction:** either group the methods a single macro call declares under
one outline node, or narrow each declaration's `selectionRange` to its own
symbol argument. The second would also give 024.28's rename something to
edit.

## 024.28 Rename refuses on a macro-declared method rather than editing it

**Status:** open, and **deliberately so** as of 0.1.15.

**Area:** `core/lib/ovallsp/rename/planner.rb`

`attr_accessor :name` declares `name` and `name=` at a symbol argument,
not at an identifier token, so there is nothing for an in-place edit to
rewrite. 0.1.14 emitted a `WorkspaceEdit` that renamed every call site and
left the declaration behind, producing a file that does not run; 0.1.15
refuses instead, which is what `#prepare`'s own comment had always
claimed happened.

The reason reaches the Core log only. `prepare` answers `null`, so the
editor shows its own "cannot be renamed" message and never asks for the
edit; nothing in this codebase sends `window/showMessage`. The W4 row's
E2E example calls `textDocument/rename` directly and asserts an empty
edit set, so the refusal is verified and the *explanation* is not.

Refusing is correct and is not the end state. The same applies to `enum`,
`scope` and `delegate`, and has since those shipped.

**Direction:** give a macro-declared declaration a `name_location`
covering its symbol argument, so `attr_reader :name` can be rewritten to
`attr_reader :title`. The writer is the hard half: `name=` and `name` are
one token in the source, so renaming `name=` to `title=` has to write
`:title`, not `:title=`. That asymmetry is why this is its own entry
rather than a line in 0.1.15.

## 024.23 The singleton chain did not model `Class`/`Module`

**Status:** fixed in 0.1.14.

**Area:** `core/lib/ovallsp/semantic/hierarchy_index.rb`,
`core/lib/ovallsp/parser_service.rb`

Found by driving the engine over real corpora during the 0.2.0 review and
fixed ahead of it, because it was the largest single source of wrong
reports the engine produced and it fired on the most ordinary Ruby there
is: `private`, `attr_reader`, `private_constant`, `alias_method`,
`include` and their neighbours, reported as unknown methods whenever
written in the body of a workspace class whose ancestry was otherwise
fully known.

Two independent causes, either of which alone still produced the report:

1. `HierarchyIndex#ancestors(singleton: true)` walked the superclass
   chain and appended no tail, so `Class`, `Module`, `Object`, `Kernel`
   and `BasicObject` were not in the chain and `Module#private` could not
   be found. The instance side has always had `DEFAULT_OBJECT_CHAIN`.
2. `ParserService` used one flag for two questions — "does an unqualified
   `def` here declare a singleton method" (true only inside
   `class << self`) and "is `self` here a Class/Module object" (also true
   in a class body and inside `def self.x`). Receiverless calls took the
   first, so they were resolved against the instance chain.

A third cause had to be closed in the same release rather than recorded.
Reading a `define_method` body as an instance -- which cause 2's fix
makes correct -- surfaced that `attr_reader`/`attr_writer`/`attr_accessor`
were never recorded as declarations at all, so Thor's
`attr_accessor :options` became a *new* wrong report. A fix that hands a
user a report they did not have before is not a fix, so the parser now
records what those DSLs define (`ATTRIBUTE_DSLS`), with a dynamic
argument recording nothing.

Measured with `scripts/corpus_diagnostics.rb`, each revision against one
fixed corpus: `core/lib` 60 → 4 `unknown-method` findings, ActiveSupport
8.1.3 785 → 265, Ruby 3.4.7's standard library 15,982 → 3,848, **and no
report introduced anywhere in it**. (0.1.14's own entry quoted 62 and 776
for the "before" side, from a different tree; 0.1.15 corrected both.)

0.1.14's fix was itself wrong in five ways, each found by independent
review of the released code and fixed in 0.1.15: the tail was looked up
for singleton methods rather than instance ones, it was keyed on the
terminating ancestor rather than the receiver, `define_method` inside
`class << self` was read as instance-self, and `instance_eval`/
`instance_exec` were listed with it for no stated reason. A fifth --
`attr_*` recorded from inside method bodies and blocks -- was attempted
three times and withdrawn; 024.31 records why the shipped parser
attributes `attr_*` lexically, exactly as 0.1.14 did. Wrong `argument-count` fell 36 → 13 and `unknown-route-helper`
48 → 8, the latter because a `*_path` name that resolves to a declaration
is no longer guessed at -- which reduces 024.24 without fixing it.

## 024.R1 Rails-specific behaviour has no explicit boundary (roadmap, 1.0.0)

**Status:** open — roadmap
**Area:** `core/lib/ovallsp/server.rb`, `core/lib/ovallsp/parser_service.rb`,
`core/lib/ovallsp/local_inferencer.rb`

Rails detection gates exactly one thing: whether `RailsBootstrap.start`
spawns the Runtime Agent (`bin/rails` + `config/environment.rb` must both
exist). Everything downstream is not branched on "is this Rails" at all —
the same code runs either way, and in a plain Ruby project the
Rails-derived registries are simply empty, so those features contribute
nothing.

That part is a good property: a wrong Rails guess degrades to static
analysis instead of breaking, and it is the same path an untrusted
workspace takes when the Agent deliberately does not start.

The gap is that several Rails *conventions* are applied on filename and
method-name shape alone, with no Rails gate anywhere:

- controller-to-view ivar propagation matches
  `app/views/<dir>/<action>.*.erb`
- file-change classification matches `app/models/*.rb`, `db/schema.rb`,
  `db/structure.sql`, `db/migrate/`
- `before_action` is recognised by method name
- `enum`/`scope`/`delegate` generated-method facts are recorded by method
  name

So a plain Ruby project that happens to use those names or that directory
layout gets Rails semantics applied to it. No incorrect behaviour has
been observed — the registries those paths feed are empty without an
Agent — but the boundary is implicit, and nothing tests what a non-Rails
project experiences.

**Direction:** give the Rails conventions one explicit boundary (a
capability/profile decided once at initialize, from the same detection
that gates the Agent) rather than re-deriving "this looks like Rails"
from a path pattern at each site. Add a plain-Ruby workspace to the E2E
capability suite so the non-Rails experience is specified and verified
rather than assumed.

Deferred out of 0.1.6 deliberately: it is an architectural change across
three files, and 0.1.6's goal is that the capabilities already claimed to
work actually do.

One of the two things 1.0.0 requires (`docs/PUBLISHING.md`, "0.x, and
what 1.0.0 requires"): a plain Ruby project must be guaranteed, not only
a Rails one. Until then README's capability matrix carries ⚠️ for that
column and this entry is why.

## 024.R2 Argument *type* checking (roadmap, 0.2.0)

**Status:** open — roadmap
**Area:** `core/lib/ovallsp/diagnostics/engine.rb`

0.1.6 added an argument *count* check (capability G5). Nothing inspects
what the arguments actually are: passing a String where the parameter is
only ever used as an Integer is not reported.

Doing it honestly needs more than the count check did. Parameter types
are not declared in Ruby source, so the expected type has to come from
RBS/RBI where one exists, or from inference over the method body where it
does not — and a wrong "expected Integer, got String" on code that runs
is worse than saying nothing, the same standard G5 was held to.

**Direction:** start where the expected type is stated rather than
inferred (RBS/RBI-declared parameters, and the built-in container rules),
and report only when the argument's own inferred type is a concrete
Nominal that cannot match. Leave everything else silent.

Referenced from README's capability matrix as the version this is planned
for, so the table's promise and this entry stay in step.

---

## 024.R3 Feature parity roadmap, measured against Pylance

**Status:** open — roadmap

Pylance is the closest well-known reference point for "what a language
server is expected to do" in a dynamically typed language with optional
type declarations, so it is a useful yardstick — not a target to copy.
Rows Pylance has that make no sense here (Jupyter support, IntelliCode's
ranked completions, Python-specific stub packaging) are deliberately
absent rather than listed and dismissed.

Current OvalLSP capabilities were read from the `initialize` response and
the code, not assumed: `hoverProvider`, `documentSymbolProvider`,
`definitionProvider`, `referencesProvider`, `renameProvider`,
`workspaceSymbolProvider`, `completionProvider`, `signatureHelpProvider`.
Everything else below is absent.

| Pylance capability | OvalLSP today | Planned for | Notes |
|---|---|---|---|
| Diagnostics across the whole project | Open files only | **0.2.0** | The first thing a user noticed as missing. `publishDiagnostics` fires from `reindex`, which only runs for open buffers, so a mistake in a file you are not looking at is invisible. Needs a workspace-wide pass plus a budget, or LSP pull diagnostics. |
| Docstrings in hover and completion | Type, origin and definition location only | **0.2.0** | Ruby has RDoc/YARD comments directly above a `def`. Nothing reads them. Hover shows what a thing *is* but never what it is *for*, which is most of hover's value. |
| Semantic highlighting (semantic tokens) | None | **0.2.0** | Unusually valuable in Ruby, where `foo` alone is ambiguous between a local variable and a method call on self — the engine already knows which, and the editor currently does not. Covers ERB templates' Ruby regions too, which the shared extraction path now makes free. Distinct from shipping a TextMate grammar, which is a non-goal: VS Code already associates `.erb`, and another grammar would only collide. |
| Inlay hints (inferred types, parameter names) | None | **0.3.0** | The type engine's answers are only visible on hover today. Inlay hints put them where the code is, which is the difference between a feature people use and one they remember exists. |
| Code actions / quick fixes | None | **0.3.0** | Each existing diagnostic implies one: define the missing method, correct the route helper name, fix the argument count. A diagnostic that only complains is half a feature. |
| Go to type definition | Go to definition only | **0.3.0** | Cheap given `explainType` already resolves the type: jump from an expression to the class it evaluates to, rather than to the method being called. |
| Document highlight (occurrences in file) | None | **0.3.0** | Small and self-contained: the reference index already answers this workspace-wide, so scoping it to one file is nearly free. |
| Call hierarchy | Find references only | **0.3.0** | An incremental step on the same index. Callers/callees of a method, navigable, rather than a flat list. |
| Auto-import / add `require` | None | **0.4.0** | Much weaker payoff than in Python: Rails autoloads, and plain Ruby projects mostly `require` at the entry point. Worth revisiting only after the plain-Ruby story (024.R1) exists. |
| Type checking strictness levels | One fixed set of checks | **0.4.0** (as per-check severity) | Pylance's basic/strict switch matters because its checks are numerous and opinionated. With four checks, a per-check severity setting would cover the same need more simply. |
| Signature help with active parameter tracking | Signature label only | **0.4.0** | Already useful; highlighting which argument the cursor is in is a refinement, not a gap. |
| Generating type stubs from source | RBS/RBI are read, never written | not planned | Interesting for library authors, irrelevant to the Rails application developer this Preview targets. |

Not planned, and listed only so their absence is a decision rather than
an oversight: unreachable-code dimming (RuboCop covers the same ground
for Ruby users), refactoring extractions beyond rename, and anything
notebook-shaped.

Ordered by what a user notices soonest rather than by effort:
whole-project diagnostics, then documentation in hover/completion, then
semantic tokens, then inlay hints and code actions. The first two are
noticed in the first ten minutes.

These versions are also carried in README.md and README.ja.md's
capability matrix, which is the user-facing statement of them; this
section is the reasoning behind each. Keep the two in step.

---

## 024.R4 Only one platform is published or verified (roadmap, 1.0.0)

**Status:** open — roadmap
**Area:** `vscode/package.json` (`--target darwin-arm64`),
`.github/workflows/apple-silicon-release.yml`, `vscode/scripts/copy-core.js`

One VSIX is published, for `darwin-arm64`, and it is the only environment
any capability has been verified in. On every other platform the
situation is not "probably fine" but "unpublished": VS Code filters
Marketplace results by target, so there is nothing to install on Windows,
Linux, or an Intel Mac.

The obstacle is the vendored payload rather than the code. `prism` and
`rbs` ship as native extensions built for the packaging machine's Ruby
ABI, OS and CPU, so a VSIX is only valid for the combination
`PLATFORM_MANIFEST.json` records. Sideloading the darwin-arm64 build
elsewhere does not crash — `Ovallsp::VendorCompatibility` and
`platformCompatibility.ts` refuse the payload and explain why (ADR-0005)
— but it then depends on the user's own Ruby having prism/rbs, which is
unverified.

`.github/workflows/apple-silicon-release.yml` deliberately asserts an
arm64 interpreter before building, so it cannot be pointed at another
target as-is.

**Direction:** a per-target build matrix producing one VSIX per platform,
each built on that platform (never cross-compiled or emulated, for the
reason above), each running the capability suite against its own bundled
Core, and each published. `docs/SUPPORT_MATRIX.md`'s tiers then become
statements about verified artifacts rather than about one artifact and
several unknowns.

The other of the two things 1.0.0 requires (`docs/PUBLISHING.md`, "0.x,
and what 1.0.0 requires").

---

## 024.R5 A reopened gem class still looks closed (done, 0.1.7)

**Status:** done — shipped in 0.1.7. Measured against the same real
application that reported it: 2 diagnostics before, 0 after.
**Area:** `core/lib/ovallsp/diagnostics/engine.rb`,
`core/lib/ovallsp/runtime_agent/agent.rb`

0.1.6 stopped the unknown-method check firing on classes whose ancestry
the workspace cannot see: a chain that does not reach BasicObject is
treated as open, which covers a gem superclass named by constant and a
superclass that is an expression (`ActiveRecord::Migration[8.1]`).

One case is left, and it is not a gap in the rule but a limit of static
analysis. Reopening a class the workspace does not define looks identical
to defining it:

```ruby
module ActiveSupport
  class TestCase          # a reopen: the real class lives in a gem
    parallelize(workers: :number_of_processors)
  end
end
```

Ruby keeps the original superclass when a class is reopened, but nothing
in this file says so, so the declaration reads as a plain class with no
parent — Object, Kernel, BasicObject, complete. `parallelize` and
`fixtures` are then reported as undefined. Every Rails application's
`test/test_helper.rb` has exactly this shape, so this is the common case,
not an exotic one.

Distinguishing the two needs to know where the constant was really
defined, which only the running application knows.

**Direction (superseded — kept because the disproof is the useful part):**
ask the Runtime Agent for `Object.const_source_location`, and treat a
constant defined outside the workspace root as one whose real method set
is unknown here.

**`const_source_location` cannot answer this.** Measured against the same
application, in the environment the Agent actually boots:

| Constant | `const_source_location` |
|---|---|
| `ActiveSupport::TestCase` | `activesupport-8.1.3/lib/active_support/dependencies/autoload.rb:41` |
| `ActiveRecord::Base` | the same `autoload.rb:41` |
| `ApplicationController` | `zeitwerk-2.8.2/lib/zeitwerk/cref.rb:47` |
| `ApplicationRecord` | the same `cref.rb:47` |
| `Ovaldev::Application` | `config/application.rb:10` |
| `String` | `[]` |

It reports where the constant was *registered*, not where the class was
written. Every `ActiveSupport::Autoload` constant points at one line of
`autoload.rb`, and every Zeitwerk-managed constant — which is every class
in `app/` — points at one line of `cref.rb`. So the rule "defined outside
the workspace root means not ours" would classify `ApplicationController`
and `ApplicationRecord`, the application's own classes, as foreign. That
is the same bug pointed the other way, and worse: it would silence the
check across all of `app/` instead of misfiring twice in one file.

Two further approaches were measured and rejected:

- **Walk every constant and record its origin** (the cheap precursor to
  024.R7). `Module#const_get` on an autoload-registered constant *runs
  the autoload*: the walk raised `Gem::LoadError: listen is not part of
  the bundle` in `active_support/evented_file_update_checker` before
  finishing. Enumerating constants is not a read-only operation, and an
  Agent that loads arbitrary code to answer a diagnostic question is not
  one worth having.
- **Report the runtime's method set for the class**, the way model
  methods already are. It fixes `parallelize` and not `fixtures`: the
  Agent boots `config/environment.rb`, not `rails/test_help`, so
  `ActiveSupport::TestCase.respond_to?(:fixtures)` is genuinely `false`
  in the process being asked. Runtime truth is the wrong instrument when
  the truth differs per environment, and the file in question is the one
  file that only ever loads in a different one.

**Direction (measured, and what 0.1.7 implements):** ask the Agent for
the class's **ancestors**, and compare them against `Object.ancestors`
taken in the same process. The static claim being tested is precisely
"this class's ancestry is complete", so test it against the ancestry:

```
PlainWorkspaceThing      8 ancestors,  0 beyond Object's
ActiveSupport::TestCase 28 ancestors, 20 beyond Object's
```

Using the running process's own `Object.ancestors` as the baseline is
what makes this robust: an application that mixes into `Object` (this one
mixes in four modules, from Active Support and JSON) calibrates the
baseline itself, so no list of "expected" ancestors has to be maintained
or guessed. A class carrying ancestors beyond it that the workspace does
not declare and RBS does not know is one the workspace did not write
alone — so the chain the static index believes is complete is not, and
the check stays silent for that receiver.

The question is asked of **every workspace-declared link in the chain**,
not just the receiver. Reopening `ActiveSupport::TestCase` makes that name
workspace-declared, so every `class FooTest < ActiveSupport::TestCase`
then has a static chain that reaches BasicObject *through* it — while the
subclass itself is a genuine workspace class the Agent rightly cannot
place. Asking only about the receiver left every test file in the project
reporting the gem's whole API as unknown: the same false positive, one
level down. The implicit `Object`/`Kernel`/`BasicObject` tail is skipped,
since those are not links the workspace wrote.

Cache per class; ancestors cannot change without a restart. Ask lazily,
for the names the check is actually about to report on, rather than
enumerating anything — that is a handful of names per session, and it
avoids both the load-everything hazard above and any dependency on the
index being built before the Agent answers.

Modules need no special case: a module's static chain never reaches
BasicObject, so `chain_reaches_root?` already treats every module as
open. Confirmed against the same fixture — `module ActiveSupport` indexes
as the single ancestor `::ActiveSupport`, and nothing is reported for it.

A second, currently latent instance of the same mistake is answerable
from the Agent too, though not by the same request.
`unresolved-constant` reports any constant that is neither in
the workspace nor in RBS, which in a Rails application means every gem
constant: measured against `config/application.rb`, it reports `Rails`
and `Bundler` as unresolvable. It does not reach users today because the
check only runs in `standard` mode and the extension never sends
`diagnosticsMode`, so `safe` is the only mode reachable -- but the check
is unusable as written, and enabling it without this would repeat the
false-positive flood the unknown-method check just came out of.
`Object.const_defined?` from the Agent settles it exactly.

**What shipped**, and the one part the measurement above did not predict:
the ancestor comparison alone does not fix the reported case.
`ActiveSupport::TestCase` is not loaded in the environment the Agent
boots — `config/environment.rb`, not `rails/test_help` — so there are no
ancestors to compare, and the first working version of this still
reported both calls. The autoload registration is what settles it:
Zeitwerk registers the application's own classes by absolute path under
the workspace root, while a gem's `autoload` registers the bare require
path it was written with (`"active_support/test_case"`). So the Agent
answers one of three things per name — the real ancestors, "registered
from outside this workspace", or nothing — and the third leaves the
static reading standing, which is the right answer for a class the
workspace genuinely owns but has not loaded.

**What it still misses**, found by independent review rather than by the
change set's own tests, and worth stating precisely because the ancestor
comparison is the part this entry leads with: a reopened gem class whose
ancestry carries nothing foreign is invisible to it. `class String; def
to_bool; end; end` in an initializer gives `[String, Comparable, Object,
Kernel, BasicObject]` — `Comparable` is RBS-known, so no ancestor
disqualifies it, and a call to an Active Support core extension defined
directly on `String` is still reported. The same holds for any gem class
reopened without mixins (`class Faraday::Connection`). The reported
`ActiveSupport::TestCase` case is fixed by the autoload branch, not by
the ancestor comparison — the comparison covers the loaded-and-mixed
case, which is a different one.

Four further cases the Agent cannot settle, all reported by independent
review and all leaving the check firing where it should be silent:

- **The Agent's process is not the test environment.** It boots
  `config/environment.rb` with no `RAILS_ENV` set, so `development`. A gem
  in `group :test`, or one with `require: false`, is neither loaded nor
  autoload-registered there, so its classes answer `:absent` and the
  static reading stands.
- **A top-level name the workspace and a gem both use.** `resolve_owner`
  starts every walk at `::Object` with no notion of the workspace, so a
  workspace PORO called `Configuration` or `Response` resolves in the
  Agent to whichever gem owns that constant, and *that* class's foreign
  ancestors silence the check for the workspace's own.
- **Engines and monorepos.** `workspace_path?` compares against
  `Rails.root`, so a class autoloaded from `/repo/engines/billing` while
  `Rails.root` is `/repo/backend` reads as defined outside the workspace.
- **Singleton-only provenance.** The Agent reports `Module#ancestors`,
  the instance chain, so a class whose gem origin shows only in its
  singleton class is invisible to the ancestor comparison. Mostly moot in
  practice: a statically visible `extend` already puts the module in the
  singleton chain, where `ancestor_known?` opens the receiver anyway.

A crash-looped Agent is not on this list, and deliberately: once
`AgentSupervisor` gives up, `AncestryRegistry#deactivate!` puts the check
back on the static reading, exactly as if no Agent had ever existed.
Without that the check would defer forever to an answer that cannot come,
which is not degrading gracefully — it is going silent.

Closing all of these needs to know where each *method* came from, not
where the class did, which is 024.R7's territory.

The check remains silent for gem-derived classes reached by superclass
(024.R7 is what lifts that), and behaves exactly as it did in 0.1.6
wherever there is no Runtime Agent to ask.

---

## 024.R6 Reading an instance variable that is never assigned (roadmap, 0.2.0)

**Status:** open — roadmap
**Area:** `core/lib/ovallsp/diagnostics/engine.rb`

Nothing reports `@usr` where the code meant `@user`. Ruby returns `nil`
for an unassigned instance variable rather than raising, so this is a
mistake the language itself never surfaces: the view renders empty and
nobody is told why.

The information is already here. Controller-to-view propagation infers
the set of instance variables an action assigns, including through the
`before_action` chain (capability H3). A read of an `@ivar` that no
assignment in the effective chain produces is reportable with high
confidence.

**Direction:** report an `@ivar` read when the enclosing method, its
callback chain, and its ancestors contain no assignment to it. Stay
silent where assignments could come from somewhere unmodelled --
`instance_variable_set`, a concern the workspace cannot see -- on the
same standard as every other check here.

## 024.R7 Index what the gems actually define, and keep it fresh (roadmap, 0.3.0)

**Status:** open — roadmap
**Area:** `core/lib/ovallsp/runtime_agent/agent.rb`,
`core/lib/ovallsp/cache/`, `core/lib/ovallsp/diagnostics/engine.rb`

Today the unknown-method check only fires on a *closed* receiver, and a
class is closed only when the workspace can see its whole ancestry. In a
Rails application that is a minority of classes: a controller inherits
from `ApplicationController`, whose parent is in a gem, so the check
stays silent there — correctly, but silently. The result is that the
check works where it is least needed and says nothing where most code is
written.

The running application knows all of it. Measured against a small Rails 8
app: 3027 named modules loaded, 2204 of them attributable to one of 63
gems, contributing 15868 methods defined directly on them. Names only,
that is roughly 365KB — small enough to persist, far too much to send on
every query.

**Direction:**

- the Agent walks loaded modules once, attributing each to a gem through
  `Object.const_source_location` and the `…/gems/<name>-<version>/` path,
  and reports, per class: its own methods, its ancestors, and whether it
  defines `method_missing`;
- Core persists that per gem-version, in the cache store that already
  exists for file summaries. `Gemfile.lock` already contributes to the
  cache key, so the invalidation shape is in place — but it should become
  per gem rather than whole-index, so a single bumped gem re-indexes one
  gem and not sixty-three;
- with that, "closed" stops meaning "declared in this workspace" and
  starts meaning "we know its full method set", which is the honest
  question. Most receivers in a Rails app become closed, and the check
  becomes useful where the code actually is.

It also subsumes several entries above: 024.R5's reopened-gem-class case
(the index knows `ActiveSupport::TestCase` is a gem class), and the
latent `unresolved-constant` flood (the index knows `Rails` exists).
024.R5 stays as the narrow, cheap version for 0.1.7 — one question per
constant, no persistence — and is a stepping stone to this rather than a
competing design.

**Risks to settle when building it, not after:**

- what is loaded depends on the environment and on eager loading, so the
  index describes *a* boot, not the gem in the abstract. It must be
  recorded as such and never treated as proof a method is absent unless
  the class was actually seen;
- classes that define methods at runtime (`define_method` in an included
  hook, `method_missing`) are already handled by the existing
  `method_missing` rule, which must apply to gem classes too;
- the walk costs real time on a large app and must not block the first
  query — the same background/degrade-to-static shape the Agent already
  uses.


---

## 024.R8 Completion does nothing until you type a dot (roadmap, 0.2.0)

**Status:** open — roadmap
**Area:** `core/lib/ovallsp/server.rb` (`completion_result`),
`core/lib/ovallsp/semantic/query_service.rb`

`completion_result` matches a bare prefix against the route registry and
nothing else; every other candidate comes from
`member_completion_items`, which returns immediately unless
`receiver_type_before_dot` finds a receiver. So typing `A` offers
`article_path` and stops. The workspace's own classes, the locals in
scope, and the methods callable on self at that position — most of what
anyone types — appear only after the name is already written, at which
point completion has nothing left to do.

This is the most-used completion in any editor, and its absence is the
kind of gap that reads as "the extension does nothing", the same
impression 0.1.6 was written to correct.

**Direction:** a fourth source alongside the route helpers, assembled
from what is already indexed:

- constants the workspace declares (`WorkspaceIndex#search` already
  answers this for `workspace/symbol`, by simple name, case-insensitively);
- locals in scope at the position — `LocalInferencer` already builds the
  environment it would need, but exposes only the type of one expression,
  not the set of names it knows;
- methods callable on self, which is `members_of` against the enclosing
  class's `self` type — the same call `member_completion_items` makes,
  with the receiver taken from lexical scope rather than from before a
  dot;
- RBS-known `Kernel` methods, so `pu` offers `puts`.

**The trap, and why this is not just "call the existing pieces":** a bare
prefix matches far more than a receiver does. `a` in a large workspace
matches thousands of symbols, and an editor that answers with all of them
sorted alphabetically is worse than one that answers with nothing —
VS Code will show them, the right answer will be on page four, and the
user learns to stop pressing the key. So the work is mostly *ranking and
bounding*, which is a different problem from the one the receiver-based
path solves and has no existing answer here:

- locals before methods on self before workspace constants before
  `Kernel`, because that is roughly the order of how close the
  declaration is to the cursor;
- a hard cap, with `isIncomplete: true` so the editor re-asks as the
  prefix narrows;
- and a decision about a one-character prefix, where the honest answer
  may be to return only locals and enclosing-class methods.

None of that is settled, and settling it needs measurement against a real
workspace rather than reasoning — which is why this is scoped as its own
roadmap entry rather than folded into another release's work.

---

## 024.16 The capability E2E suite can skip in full while CI stays green

**Status:** fixed in 0.1.13 -- `ci.yml`'s skip guard now checks both
`spec/integration/real_rails_spec.rb` and `spec/e2e/capabilities_spec.rb`,
by table rather than by a second copy of the check.

Two things the one-line direction below did not anticipate. First, a
guard that failed on *any* pending example would have made this
document's own `NOT YET` status -- "specified, has an E2E row, currently
failing or pending", which `capability_coverage_spec.rb` accepts --
unexpressible; the guard therefore exempts a pending message that says
`NOT YET`, and `spec/meta/ci_skip_guard_spec.rb` asserts that neither
suite's environment-skip message says it. That exemption is an authoring
rule -- a pending row has to *say* `NOT YET` -- so both language versions
of `EXTENSION_CAPABILITIES.md` state it, and the meta spec asserts they
do: a CI-enforced rule recorded only in a YAML comment is one an author
meets as a red build with no way to find out why. Second, the guard was itself
pinned by nothing: deleting the capability row leaves every check in this
repository green, which is the same shape as the gap it closes. That is
what the meta spec is for, following `versionPairing.test.ts`.
**Area:** `.github/workflows/ci.yml`, `core/spec/e2e/capabilities_spec.rb`,
`core/spec/meta/ci_skip_guard_spec.rb`

`docs/EXTENSION_CAPABILITIES.md` states two rules. "A capability with no
E2E row is not a capability" is enforced by
`core/spec/e2e/capability_coverage_spec.rb`. "A capability whose row is
skipped is not shipped" is enforced by nothing.

`capabilities_spec.rb` skips every example when its real-Rails fixture
cannot be prepared (`before(:all)` → `skip` when `available?` is false).
CI has exactly the right guard — "Fail if the real-Rails integration
suite was skipped instead of run" — but it filters on
`spec/integration/real_rails_spec.rb` and does not cover the e2e path.
Measured: forcing `available?` false gives `45 examples, 0 failures, 41
pending` and **exit status 0**, with `capability_coverage_spec.rb` still
green, because it scans the spec file's source text for `it "C5: …"` and
cannot tell a row that ran from a row that was skipped.

Latent rather than live today: `real_rails_spec.rb`'s own guard
incidentally forces the fixture's gems to exist. But nothing states that
dependency, and the two suites reach the fixture by different code paths.

**Direction:** widen the existing CI step's file filter to both paths.
One line. Recorded rather than fixed in 0.1.12 because it is a CI gap,
not a defect in the release, and 0.1.12 has already been rolled back once
for widening past its own subject.

## 024.17 `vscode/src/extension.ts` is covered by no test that runs anywhere

**Status:** fixed in 0.1.13 for the two decisions a user notices --
`documentSelectorFor` and `statusPresentation` moved into
`vscode/src/clientPresentation.ts`, which imports no `vscode`, with
fifteen unit tests -- thirteen behavioural, plus two that assert
`extension.ts` actually calls them (024.10's first attempt exported the
strings but left the choice between them at the call site, so the tests
described code the extension did not reach). `resolveStatus` was added in a second pass: the
extraction had left the "no client" / "the client did not answer"
decision at the call site, where a mutation reporting a failure as "no
client" passed all 167 tests.

Three of the extracted decisions were then found unpinned, all the same
shape: the specs compared the render against the very table it renders
from, and the constant against itself. Relabelling `indexing`, deleting
`agent-unavailable` and emptying the error text each left the suite
green, and a deleted key falls through to the raw-state branch -- the
status bar would read `OvalLSP: agent-unavailable`. The literals are
asserted now, and a further example -- `labels exactly the states the
Core emits` -- reads the four states out of `Server#status_result` rather
than restating them, so a state added on the Core side without a label
here fails the extension's own suite. The remaining
`vscode` wiring -- command registrations, the client bootstrap, the poll
loop's timer -- is still integration-only; running that suite in CI is
the part not done.
**Area:** `vscode/src/extension.ts`, `.github/workflows/ci.yml`

Nine of the extension's ten modules have unit tests. `extension.ts` — the
largest at 812 lines — has none. What covers it is
`vscode/src/test/integration/`, and `npm run test:integration` appears in
no workflow; `ci.yml` runs `test:unit` only.
`vscode/scripts/verify-installed-extension.sh` is likewise manual.

The uncovered surface is exactly the layer `EXTENSION_CAPABILITIES.md`
says the E2E suite structurally cannot see: the `documentSelector`, all
nine command registrations, the `ovallsp/status` poll loop, and the
client bootstrap. No defect was found in it by reading — the `.erb`
selector, the watcher glob and the version handshake are all correct —
but "the extension's tests are meaningful" is true only of the nine
modules that have them.

**Direction:** either run the integration suite in CI, or extract the
remaining decisions the way 024.10 extracted `clientTeardown.ts`.

---

## 024.15 The index's answers depend on which file was edited last

**Status:** fixed in 0.1.13 by option 1 below, in the half of it that
carries the cost. Option 1 called for both collections to be maintained
sorted at write time; `@by_symbol`'s entry lists are, and
`@by_simple_name` is still an unordered Set sorted per read -- but by one
centralised reader rather than by each of eleven, which is the property
the option was chosen for. Sorting a Set on insert would have cost every
`replace_file` a sort of every bucket its declarations touch, against a
read path that filters first and so sorts a handful of elements.

Entry lists are sorted by `[uri, line, character]` in `replace_file`, and
`ordered_symbol_ids` is the one place a query reads `@by_simple_name`, ordered
by `[name, kind, owner]` because one class has several SymbolIds that
share a name. `search`'s `rank` keeps exact-match-first and gains a tail,
since a truncated result cannot have ties decided by index order.
Measured as the entry asked: 2,000 files with one class reopened in 500
of them goes 7ms -> 61ms in `replace_file`, negligible against Cold
Index. The *read* paths needed measuring too and were not measured at
first: a bucket is keyed on the simple name, so `resolve_type_name`
sorting a whole bucket before its caller filtered it cost 3.7ms per call
in a workspace of 1,200 service objects each defining `call`. Filtering
before sorting -- the two commute here -- restores 51us with the same
order.

`search`'s ranking key grew from one element to seven, which is the
largest cost this change adds to a read: the picker opens with an empty
query, so every declaration in the workspace is a match, and the index
mutex is held throughout. Ranking the 32,000 matches an empty query
returns for 2,000 files that each declare a class and fifteen methods
measures 68ms sorting
all of them, 17ms with `min_by(limit)` -- which answers identically
because the key is total -- against 10ms for the one-element key it
replaced. About 7ms more per query, for an answer whose membership no
longer depends on which file was saved last.

The first version of that paragraph claimed parity, measured end to end
through `search`, where building the 32,000-entry match list dominates
and hid the difference. A cost claim about a sort has to time the sort.

Neither that nor the filter-before-sort above is a *behavioural* line, so
no example in the suite fails when either is reversed -- which is exactly
why they need `spec/meta/workspace_index_cost_spec.rb`. Both read as
tidying: a `select` after a `sort` looks no worse than before it, and
`sort_by { }.first(n)` is the more familiar idiom.

Every spec that could regress on re-index re-indexes, and all
twenty-three decisions are pinned by mutation -- deletions and
*permutations* both, which is a distinction the count did not make until
four keys turned out to survive having their elements reordered.

Reaching that took several passes, and
the misses are the instructive part: the `search` tail first shipped
behind a fixture whose eight files shared a single SymbolId; the ranking
key's `uri` and `line` elements were satisfied by fixtures that ordered
files and lines the same way; `find_by_simple_name`'s spec used one name
in two files, which is one SymbolId, so it never walked the collection it
was written for; the ambiguous-name spec asserted only an absolute answer
while re-indexing the first-inserted file, which lands on that answer by
accident -- and correcting it went one step too far, gaining a
before/after assertion *and* moving to the second-inserted file, which
leaves the collection in the order it already had, so the new assertion
could not fail either. Which file to re-index depends on the assertion
shape, and an example carrying both needs the first-inserted one. And
the `line`/`character` pair went the same way as the `uri`/`line` pair
had, each fixture holding one of the two at zero while varying the other,
which any order of the pair satisfies. Then the same again one level up:
deleting an element of a key is not the only way to break it, and
`[kind, name, owner]`, `[name, owner, kind]`, `rank` with uri before the
name and `rank` with owner before kind each passed the whole suite while
changing where go-to-definition lands. Every element of a sort key is two
decisions -- that it is there, and where. The
last of those was then made twice: the fixture written for the ordering
key's `kind` element re-indexed the second-inserted file, so it could not
fail either, and the round that added it published "all fifteen decisions
are pinned" on its strength. A fixture that passes has not shown that
anything is tested.
**Area:** `core/lib/ovallsp/workspace_index.rb`

`@by_symbol` maps a SymbolId to a list of `[uri, declaration]`, and
`@by_simple_name` maps a name to a Set of SymbolIds. Both are in
*insertion* order, and `replace_file` removes a uri's entries and then
appends the new ones — so re-indexing a file moves its entries to the
back of every list they are in. Editing a file, without changing a single
declaration, changes the order.

These readers then take `.first` of such a list, or truncate it. The list
was miscounted twice before it was written one reader per row, and a
later review found four more (`Server#current_observation_fingerprint`,
`MethodResolver#names_for_type`'s visibility lookup,
`Server#route_helper_definitions`, `Rename::Planner#locations_for`) — so
it is a sample, not an inventory. That is an argument *for* the storage
fix rather than against it: ordering the storage covers readers nobody
enumerated, which is exactly what converting a subset does not.

| reader | what changes |
|---|---|
| `Server#find_controller_uri` | which controller file supplies a view's instance variables |
| `QueryService#model_definition_locations` | where go-to-definition on a column or association lands |
| `find_by_simple_name` | where go-to-definition on a bare constant lands |
| `resolve_type_symbol_locked` | which class an ambiguous bare name resolves to — and with it the ancestry chain, the unknown-method check, find references and rename |
| `QueryService#source_signatures` | whose parameters signature help shows |
| `MethodResolver#build_candidate` | whose visibility gates the private-method check |
| `search` | which symbols survive `workspace/symbol`'s result limit |

All measured, all reproducible by adding one comment line to a file. This
predates 0.1.12 and has shipped in every published version.

### Why it is deferred rather than fixed

0.1.12 tried to fix it four times and produced three incomplete fixes and
two regressions:

- round 8 pinned `.first` with a spec asserting the current answer, which
  turned out to be an accident rather than a behaviour;
- round 9 sorted `class_declarations` by uri — which backs two of the
  seven rows above and leaves five, and
  `sort_by` is not a stable sort, so entries sharing a uri were still
  arbitrary, and the *source* order that insertion had at least preserved
  within a file was lost;
- round 10 replaced that with a per-SymbolId `ordered_entries`, which
  dropped the cross-SymbolId ordering round 9 had added — a straight
  regression of the same bug, in the same method;
- round 11 added a second sort on top to restore it.

Each attempt bolted an ordering onto a *reader*. That is fixing the
symptom: the readers are not wrong to want a stable answer, the storage
is wrong to have an unstable one. Every reader added is a new place to
forget, which is the same structural mistake 0.1.11 was spent on for
qualification.

### The fix this actually needs

One of these two, decided before any code is written:

1. **Make the storage ordered.** `@by_symbol`'s per-SymbolId list and
   `@by_simple_name`'s Set are maintained sorted by `[uri, line,
   character]` at write time in `replace_file`. Every reader then
   inherits the order without knowing about it, and there is exactly one
   place that knows what the order is. Cost: `replace_file` does an
   insertion sort per declaration; measure it against Cold Index on the
   real Rails fixture before committing to it.
2. **Stop taking `.first` of a collection with no order.** Go-to-definition
   and find-references are `Location[]` in LSP — a class reopened across
   four files genuinely has four definitions, and answering with all of
   them is a better answer than answering with an arbitrary one. This is
   a larger behavioural change and needs the `.first` callers examined
   one at a time; `find_controller_uri` cannot return several, so it
   would still need a stated rule.

Option 1 is the smaller change and the one that matches this codebase's
own habit of putting a rule in the one place that owns the data. Option 2
is the better answer for the three readers that are LSP list responses.
They are not exclusive.

Whichever is chosen, the spec has to exercise **re-indexing** — every
0.1.12 attempt was pinned by a spec that built the index once, which is
exactly the state in which the bug is invisible.

---

## 024.13 A reopened core class looks closed, in both directions (0.3.x)

**Status:** open
**Area:** `core/lib/ovallsp/diagnostics/engine.rb`

`closed_nominal?` calls a receiver closed when every ancestor is
workspace-declared or RBS-known. A workspace that reopens a core class —
`lib/core_ext/array.rb`, idiomatic in Rails — satisfies that: `Array`'s
chain is `Array, Object, Kernel, BasicObject`, all known. But the
workspace does not own `Array`, and gems keep adding to it, so the check
is wrong in both directions on such a receiver:

```ruby
class Array
  def to_sentence_ish = "x"     # any reopening closes the chain
end

a = [1, 2, 3]
a.second                        # ActiveSupport's; reported as unknown
a.totally_bogus_method          # genuinely unknown; correctly reported
```

This is 024.R5's problem one level out — the class is *partly* the
workspace's — and 024.R5's machinery already solves it when a Runtime
Agent is connected: the Agent reports `Array`'s real ancestors, the check
sees ancestors it cannot account for, and stays silent. Without an Agent
(an untrusted workspace, a plain Ruby project) there is nothing to ask.

0.1.9 made this concrete. Array literals already inferred as `Generic`
and so were never in either check; **hash literals were `Nominal("Hash")`
and were**. Rendering them as `Hash[Unknown]` (024.12) takes them out,
because the engine's gates ask for a plain class name.

Teaching the gates to read a container receiver — correct everywhere
else, and what `Types.base_nominal` exists for — would have put both
literals in, array ones for the first time. Independent review measured
what that costs: `[1,2,3].second` reported as unknown against a workspace
that reopens `Array`, because ActiveSupport defines it and stdlib RBS does
not. So the gates keep asking for a plain class name.

What 0.1.9 therefore changes, and it is a change rather than a
preservation: a hash-literal receiver is no longer checked. On a workspace
that reopens `Hash`, `h = {}; h.totally_bogus_method` was reported and now
is not, and so is an argument-count mismatch on such a receiver. The same
gate previously reported `{}.deep_symbolize_keys` — ActiveSupport's —
as unknown, which is the false positive this direction avoids. Fewer
reports either way, which is the direction this check is meant to err in,
but the true positives are lost with the false ones.

**Direction:** treat "the workspace declares part of this class" as
distinct from "the workspace owns this class", which is what the Agent
already answers for 024.R5. Scheduled with 024.R7, since a gem index is
what makes the answer available without an Agent too.
