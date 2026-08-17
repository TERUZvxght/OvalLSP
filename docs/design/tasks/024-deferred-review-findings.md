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

Every entry opens with a fenced `yaml` block, directly under its
heading, and that block is the entry's status — the prose beneath it adds
narrative and does not restate it:

```yaml
status: open        # open | fixed | done. Anything else reads as open.
kind: defect        # defect | roadmap. Roadmap items are plans, not faults.
released-in: 0.1.14 # only on a resolved entry
user-visible: yes   # on an open defect: does a user see this?
```

An open defect with `user-visible: yes` must be cited by number in
`docs/KNOWN_LIMITATIONS.md` **and** `.ja.md`, so a finding recorded here
reaches the people it affects. An entry with no user-visible half says
`user-visible: no` and a `user-visible-note` giving the reason.
`core/spec/meta/deferred_findings_spec.rb` checks all of that, and fails
on an entry whose heading carries no block rather than skipping it.

The block exists because the previous attempt at this check parsed the
file's *prose* and had to be rolled back — 024.25 records why, and this
format is the direction that entry recommended.

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

```yaml
status: fixed
kind: defect
released-in: 0.1.10
```

the unused copy is deleted, along with `#infer_ivars_for_method`, `#find_static_render_target`, `#find_method_node` and the `MethodLocator` visitor that existed only to serve it. Its specs were re-anchored rather than dropped: the ones covering pieces the Server still calls now go through those pieces (`method_nodes` + `#infer_ivars_for_method_node`, `#static_render_target_for_node`), and the seven chain behaviours that had no equivalent on the live path — `except:` on both sides of it, an action overriding a callback's assignment, an unresolvable `if:` condition, a conditional `skip_before_action`, a missing callback method, and the multi-name forms of `before_action` and `skip_before_action` — were ported into `server_views_spec.rb`, where each fixture was checked to yield a *different* answer under the opposite behaviour.

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

```yaml
status: fixed
kind: defect
released-in: 0.1.10
```

the buffer case is now a spec of its own, so `@seen_uris << uri` sitting above the open-buffer early return is pinned rather than merely claimed.

**Area:** `core/spec/ovallsp/cold_indexer_spec.rb`

The comment says the spec covers a file already open in a buffer, but no
`DocumentStore` entry is created, so that branch is never exercised.
`@seen_uris << uri` sits above the open-buffer early return and nothing
pins that ordering. No live consequence: the deletion sweep verifies
absence with `File.file?` rather than trusting `seen_uris`.

**Direction:** add the buffer case, or trim the comment to what the spec
actually asserts.

## 024.8 Ownership retirement on `exited() && known.size === 0` is unpinned

```yaml
status: fixed
kind: defect
released-in: 0.1.10
```

the two assignments are deleted; the `ownedSessionId` one is load-bearing and pinned by a new regression test, and `ownedGroupId` went with it for symmetry (it is set only from a validated root row whose `pgid === pid`, and such a row also satisfies the expansion test against `ownedSessionId`, so `known` cannot be empty in the same pass — no fixture distinguishes that half). The first attempt at this entry deleted them as unable to change any answer, reasoning that the branch is only reached with the root absent and the expansion gate therefore already closed. Independent review disproved both halves: `rootObservedAbsent` is assigned at the *end* of the pass, and the root row can be present but untracked, because `known` only takes the root while the child has not exited. A Core dying inside the ~57ms pre-`setsid` window reaches the branch with ownership still meaningful — on Darwin especially, where `sid` is 0 on every row. Since `terminateOnce` and `waitForAllExit` both refresh after the interval is cleared, retiring ownership there permanently lost the survivor those later passes exist to catch. The `clearInterval` in the same branch stays, pinned by its own test.

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

```yaml
status: fixed
kind: defect
released-in: 0.1.10
```

the four decisions moved into `vscode/src/clientTeardown.ts`, which imports no `vscode` and takes the lifecycle manager and the per-folder maps as parameters rather than reading module state. `extension.ts` now delegates to it and keeps only the `vscode` wiring. Fifteen unit tests cover them, and each decision was checked by mutating it and confirming the suite goes red.

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

## 024.40 Every `argument-count` report on the measurement corpus is false

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`argument_count_findings`,
`sole_source_declaration`)

G5 has been a ✅ row since 0.1.6. A reviewer read all 17 reports it
produced at `6f5e86a`; after round 22's fixes there were 15, and all 15
were read again. At 0.2.1 the count is **14**, re-measured over Ruby
3.4.7's standard library, five Rails 8.1.3 gems and minitest 6.0.6, and
**10** of them are the `def Const.method` shape. The table below is the
0.1.6 reading and is kept for the shapes rather than the counts:

| shape | count | cause |
|---|---|---|
| `def HTTP.get_response` calling `start(...)`, judged against the instance `def start` | 8 | 024.32 |
| `def CStructEntity.malloc(types, func = nil, size = size(types))` | 1 | 024.32 |
| `def Runnable.run_suite` | 1 | 024.32 |
| `create(name, nil, arg)` where `create` is `alias_method :create, :new` in `class << self` | 2 | the alias is resolved, the singleton `new` is not |
| `run Rails.application` inside `Rack::Builder.new do` | 1 | block self is the enclosing class (024.31) |
| `readline(@prompt, false)`, `Configuration.instance(:must_exist).load do` | 2 | receiver resolved by substitution |

**What this is not.** It is not "the check is wrong". Every one of these
is a case where the *declaration* the check found is not the one the call
reaches, and each has its own recorded cause. Nor is it a 0.2.0
regression: `main` produces 22 on the same corpus.

**What it is.** A corpus of gems is close to the worst case for this
check — dependencies absent, so names resolve by substitution; heavy use
of `def Const.method`, which the parser mis-files. A user's own workspace
is the opposite: their classes are declared, their names are theirs. The
honest statement is that the check's precision is unmeasured on the code
it is actually for, and measured at zero on the code we have.

**What 0.2.0 changes** is the blast radius, exactly as 024.24 argued for
the route check: diagnostics now publish for files nobody opened, so
these reach the Problems panel rather than waiting to be found.

**Direction:** the three causes are already recorded — 024.32 (`def
Const.method`'s kind and owner), 024.31 (a block's self), and the
index's substitution, which round 22 refused for the *receiver* and for
a *superclass* but not for an aliased singleton. Fixing 024.32 alone
removes 10 of the 15. Then re-measure, on a real application rather than
on gems.

## 024.38 `scope_at` copies the whole environment once per descent step

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  A cost, not an answer. It is quadratic in the number of locals in one
  scope, which real code keeps small -- 1.2ms at 100 locals, where the
  measurable curve starts. Recorded rather than fixed because the fix is
  in the inference core and the round that found it was already
  repairing the round before it.
```

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`locate`, `capture_scope`)

`locate` calls `capture_scope(env)` at the top of *every* step, and
`capture_scope` builds a new Hash of the whole environment. Only the last
one survives. 0.2.0 is what makes it matter: `PrefixCompletion#items`
calls `scope_at` for every bare-prefix completion, so this runs on the
request path per keystroke.

Measured by a reviewer, same document, 10 iterations, parse cache warm,
against `infer_at` on the same document and position as an in-process
reference:

| locals in scope | `scope_at` | `infer_at` |
|---|---|---|
| 50 | 0.24 ms | 0.03 ms |
| 100 | 1.17 ms | 0.04 ms |
| 200 | 3.93 ms | 0.10 ms |
| 400 | 14.78 ms | 0.19 ms |
| 800 | 56.10 ms | 0.36 ms |

Four times per doubling, bounded only by `max_steps: 5000`.

**Direction:** capture on *write*, not on step. Keep the `env` reference
and the self type, and materialise the snapshot at the moment the
environment is about to be mutated -- there are nine such sites and most
are on fresh child environments. Taking the snapshot at the end instead
is wrong: `x = <cursor>` would then see `x`, because
`LocalVariableWriteNode` assigns after descending into its value.

It wants `spec/meta/workspace_index_cost_spec.rb`'s treatment -- a
source assertion -- since reversing it changes no answer.

## 024.39 `LocalInferencer` keeps per-request state, and 0.2.0 gave it a second thread

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  No wrong answer has been produced. A reviewer ran 2,000 concurrent
  `infer_at` pairs and 400 `scope_at`/`infer_at` pairs in both size
  directions and got zero wrong answers, zero leaked locals and zero
  exceptions. What is recorded is that the reason it holds is not an
  invariant.
```

**Area:** `core/lib/ovallsp/local_inferencer.rb`, `core/lib/ovallsp/server.rb`

`@steps`, `@step_budget`, `@self_type_stack`, `@scope_capture`,
`@capturing_scope` and `@parse_cache` are instance state reset at the top
of each entry point. `publish_diagnostics` and `workspace_findings_for`
both hold `@index_mutation_mutex`, so those two are serialised — but
`hover_result` and `completion_result` do not take it, and 0.2.0 is the
release that put `analyze` on a background thread.

`@capturing_scope` is the sharpest edge: a background `infer_at` running
inside a foreground `scope_at` would call `capture_scope` and overwrite
the completion's answer with another document's locals.

What makes it safe today is that the GVL rarely preempts inside one walk.
That is a probability, not an invariant, and nothing states it.

**Direction:** the state belongs in a per-call object rather than on the
inferencer, which is also what would let `@parse_cache` be shared safely
instead of being the one piece of it that wants to be.

## 024.37 The argument-type check reports nothing on measured real Ruby

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`argument_type_findings`,
`sole_declared_overload`)

G15 is one of the six capability rows 0.2.0's minor bump is justified by.
Measured at `ca66774`, after this round's fixes, with
`scripts/corpus_diagnostics.rb`:

| corpus | files | `argument-type` |
|---|---|---|
| Ruby 3.4.7 stdlib + activerecord/activesupport/actionpack/actionview/activemodel 8.1.3 + minitest 6.0.6 | 2,042 | **0** |
| prism 1.6.0, with its own `sig/` loaded | 41 | **0** |

Before those fixes the same two corpora produced **795** and **151**, and
every one of them was wrong: a call judged against a signature it does
not bind to. So the check's entire measured output, over every corpus
this project has pointed it at, was false positives — and removing them
left zero. Both diffs are by position and introduce nothing.

The second row is the one that matters, because it answers the objection.
The harness loads signatures from `Dir.pwd`, so a corpus of gems is
measured with none of its own types stated, which is the check's floor by
construction. `OVALLSP_SIGNATURE_ROOT` (added with this entry) lifts that:
pointed at a gem that ships extensive RBS, the check found 151 things to
say and all 151 were wrong, and with those fixed it says nothing.

It is not inert — making `argument_type_findings` return `[]`
unconditionally fails 9 of `argument_type_spec.rb`'s examples, and the
E2E row passes. (An earlier version of this entry said 25, which was a
guess dressed as a count; a reviewer measured it.) What it is, is narrow to the point where real code
does not meet it: an RBS/RBI declaration with exactly one overload and no
`*rest`, both the declared and the inferred type a plain class with no
ancestor relation, and no operator expression in the argument. Each of
those refusals was added to remove a false positive, and each was right
on its own.

**What is open:** whether a capability whose measured yield on real code
is zero should carry a README ✅ and a capability row. Both are defensible
today — the row is verified by an example that fails if the check breaks,
which is what ✅ is defined to mean — but a user reading the matrix
expects a check that fires. The alternatives are to widen it (which the
whole entry above argues is how it produced 795 wrong reports), to mark
the row the way the `@ivar` row is now marked, or to say plainly in
`KNOWN_LIMITATIONS` what it will and will not catch.

**Direction:** measure once more with the harness pointed at a workspace
that states types in the shapes the check accepts — a project with a
hand-written `sig/`, not a gem's generated one — before deciding. A check
that fires on the code its users write and not on gems is a different
answer from one that fires nowhere.

## 024.36 Instructing a reviewer narrowed what it could find, and a control run proved it

```yaml
status: fixed
kind: defect
released-in: 0.1.15
```

**Area:** how this project asks for an independent review. The finding is
about the process, not the engine; `CLAUDE.md`'s "How to ask for an
independent review" section is what came out of it.

### What happened

0.1.15 ran eight review rounds. The count of defects fell steadily, and
that decline was read as convergence:

| round | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| code defects | 6 | 3 | 3 | 2 | 1 | 1 | 2 | 0 |

It was not only convergence. Over those eight rounds the instructions
given to the reviewer had been quietly narrowed, every one of the changes
reducing what could be reported:

| | rounds 1–4 | 5 | 6–7 | 8 |
|---|---|---|---|---|
| "re-finding a recorded defect is not a finding" | — | — | 3 entries excluded | **9 entries excluded** |
| "a clean report is a useful result" | — | yes | emphasised | emphasised twice |
| list of already-measured corpora to avoid | — | partial | 14 sets | **16 sets** |
| "concentrate on X" | — | — | — | **yes** |

Each is defensible on its own. Together they mean the same underlying
defect density produces a smaller number every round, and the number was
being used as the stopping signal.

### The control

The last round was run twice on the same tree: once with the narrowed
instructions (round 8), and once with **round one's instructions
verbatim** — no exclusion list, no corpus list, no "concentrate", no
"clean is fine", plus one addition: *report anything you consider a
defect, whether or not it looks already known or deliberate; if a
decision recorded as deliberate is the wrong decision, say so.*

Round 8 found five things, none of which changed what the engine answers.

The neutral run found a **user-visible regression 0.1.15 itself
introduced**: `delegate` and `scope` recorded their generated methods as
taking no parameters, so once this release taught the argument-count
check to count a brace-less trailing hash, every call to a delegated
method was reported — including in ActiveRecord's own
`database_statements.rb`.

The mechanism of the miss is specific and worth naming: round 8 had been
told to avoid the sixteen already-measured corpora, and the Rails gems
were on that list. **The instruction that sounded like efficiency is what
kept anyone from looking where the regression was.** A corpus is only
"already measured" against the revision it was measured at; the release
had moved seven times since.

### What this changes

`CLAUDE.md` now carries the rules this produced. In short: do not tell a
reviewer what not to count, where to concentrate, or that finding nothing
is fine; keep a list of measured corpora as a record of coverage rather
than as an exclusion; and when a review loop's findings are used to decide
that a change set is ready, run one round with neutral instructions before
believing the count.

### What it does not change

The decline was not *only* instruction drift. Rounds 2–5 each found
defects in code the previous round had written, and less new code was
written each round, so some of the fall is real. The point is that the
number could not distinguish the two, and nothing had been done to make
it able to.

## 024.35 A class that includes a module the workspace cannot resolve still reads as closed

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`closed_nominal?`)

`closed_nominal?` asks `chain_reaches_root?` of the *instance* chain --
deliberately, and correctly -- but asks `ancestor_known?` only of the
chain it is about to search. For a class-level call that is the singleton
chain, which `include` never touches. So a class that includes an
`ActiveSupport::Concern` living in a gem the workspace has not read is
judged closed, though its real class-level method set is whatever that
Concern's `class_methods do` block installs.

```ruby
class Configish
  include SomeGem::Model
  validate :ensure_ok      # reported; `include ActiveModel::Model` makes it run
end
```

Reported on 0.1.14 and 0.1.15, silent on 0.1.13 -- 0.1.14 introduced it
by giving the singleton chain a tail that reaches the root, which is what
`chain_reaches_root?` was the only guard against. Four instances in
`solid_queue-1.5.0/lib/solid_queue/configuration.rb` alone.

**Direction:** ask `ancestor_known?` of both chains when the lookup is a
singleton one. The instance chain is where `include` records itself, and
an unknown module there means the class-level set is unbounded too. Worth
measuring in both directions first: it will silence genuine class-level
reports on every class that includes anything unread, which is most of a
Rails app before the Agent is ready.

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

**The owner is wrong too, and this entry said it was not.** An earlier
Direction here read: "the owner is already computed correctly a few
lines below (`constant_full_name(owner_receiver)`); it is only the
`kind`". Round 22 of the 0.2.0 loop disproved it.
`constant_full_name` ends in `qualify`, which nests the name under the
current owner unconditionally — so `def Fetcher.start` written *inside*
`class Fetcher` is recorded on `::Fetcher::Fetcher`, a class that does
not exist. Ruby resolves the constant `Fetcher` there to the class
itself. Anyone following the old Direction would have produced correctly
kinded singleton methods on a namespace nothing resolves to.

**And the consequence is not only `unknown-method`.** The arity check
reads the same declarations, so a call to a `def Const.method` is judged
against whatever *instance* method shares its name. On the 0.2.0
measurement corpus, **9 of the 17 remaining `argument-count` reports**
are this shape: `net/http.rb`'s `def HTTP.get_response` four times, its
vendored copy under `rubygems/vendor/net-http` four times, and
`minitest.rb:472`'s `def Runnable.run_suite`. Neither this entry nor
`KNOWN_LIMITATIONS.md` said so before round 22 measured it.

**Direction:** both the `kind` and the `owner` have to change, and
neither is a one-line edit.

- `kind`: any explicit constant receiver means a singleton method, not
  only `self`. Check what else keys on that predicate first —
  `visit_def_node` also uses it for the declaration's visibility, which
  is `nil` for singleton methods.
- `owner`: the parser cannot know at parse time whether `Foo::Bar`
  exists, so it cannot resolve the constant properly. What it *can* do
  is stop nesting a name that names an enclosing frame: if the written
  name matches the last segment of an enclosing owner, that frame is the
  owner. That covers `def Foo.bar` inside `class Foo`, which is the
  whole measured population.

Still its own task rather than a ride on another release, for the reason
this entry gave before and round 22 agreed with: it changes declaration
kinds, which is what 0.1.14 and 0.1.15 were both spent on, and it wants
a corpus run in both directions.

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

## 024.28 Rename refuses on a macro-declared method rather than editing it

```yaml
status: open
kind: defect
user-visible: yes
```

Refusing is the deliberate behaviour as of 0.1.15; what is open is that
refusing is not the end state.

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

## 024.27 `documentSymbol` lists one outline entry per name a macro declares

```yaml
status: open
kind: defect
user-visible: yes
```

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

## 024.26 A workspace `def Object.foo` is reachable from every class in Ruby and from none here

```yaml
status: open
kind: defect
user-visible: yes
```

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

## 024.25 A Markdown-parsing spec is the wrong shape for "these two documents must agree"

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  A rolled-back internal guard. Nothing about the product changed, so
  there is nothing to tell a user; what is open is a decision about how
  this project keeps its own notes.
```

**Rolled back** rather than fixed. This entry is the deliverable; there
is no code change to point at.

**Area:** was `core/spec/meta/known_limitations_parity_spec.rb` and
`core/spec/meta/readme_parity_spec.rb`, both deleted.

### What was being solved

A review found that `docs/KNOWN_LIMITATIONS.md` did not mention 024.13,
024.19 or 024.20, while `025-0.2.0-review-loop-handover.md` claimed every
open entry was carried there. The prose promise had gone stale, so the
obvious move was `docs/DOCUMENTATION_MAP.md`'s own principle: where a
fact is restated in several places, have a machine compare the copies.

### Why the shape was wrong

The two specs had to *parse Markdown with regexes* to find out what the
documents said — headings, status lines, an opt-out marker, table rows,
footnote definitions. Every review round then found another input shape
the parser mishandled, and each fix was one more special case:

- **Round 2** found eight decisions in the first guard that no example
  pinned, because the fixtures used `**Status:** Open`, which reads as
  open under *both* branches of the case-sensitivity decision. Rewriting
  them onto the resolved side (`Fixed`, `DONE`) fixed that.
- **Round 3** found ten unpinned decisions in the *second* guard, written
  in round 2 — including `count("|") == 5`, whose mutation makes the row
  selector return zero rows for both files and leaves every matrix
  assertion vacuously green. It also found two soundness holes in the
  first: a heading with no title (`## 024.25`) is not recognised, so an
  entry can be added and silently skipped, and the documented "and why"
  requirement for the opt-out was never enforced at all.

Three documents had meanwhile been edited to *claim* the guard enforced
things it did not. That is worse than no guard: a maintainer reading
`DOCUMENTATION_MAP.md` would believe an unchecked rule was checked.

The pattern is 024.15's, one layer up. There, each round bolted a sort
onto one more *reader* of an unordered collection. Here, each round
bolted a fixture onto one more *input shape* of a parser that cannot
enumerate its own inputs, because Markdown prose has no schema. A guard
whose correctness depends on a regex surviving every future edit to the
document it reads is a guard that needs the next round to repair it.

### The direction that was actually needed, and taken

Two candidates were named. The first was chosen, and this file's format
is the result:

1. **Give the data a schema instead of parsing prose.** ✅ Every entry
   carries a fenced `yaml` block, and `core/spec/meta/deferred_findings_spec.rb`
   reads that rather than hunting for `**Status:**` in running text. The
   parser did not disappear — the grammar did the work: one delimited
   shape instead of however many prose can take. Nine of its decisions
   were pinned by reverse-applying each and re-running against a green
   baseline; two survived the first sweep and gained fixtures. It fails
   on an entry whose heading carries no block, which is precisely the
   failure mode that let the old guard skip entries in silence.
2. **Accept that this pair is checked by a person, and make the person's
   job small.** `DOCUMENTATION_MAP.md` already exists for exactly this,
   and its release checklist is the place to name the pairing. The map's
   own preamble says "a machine check *should* compare the copies" — it
   does not say every pair can be compared by machine, and this pair is
   evidence that some cannot be, cheaply.

The EN/JA README divergence found in round 2 is real and remains
unguarded for the same reason. Prefer 1 if this is taken up; it is the
only one of the two that would also have caught that.

### What was kept

Everything the rounds established about the *product* stayed: 024.21
through 024.24, the corrected measurements, and the user-facing text in
both languages. Those were verified against the source and against corpus
runs, and no round disputed them. Only the enforcement apparatus and the
claims about it were rolled back.

## 024.24 Every `*_path`/`*_url` call is a missing route when no routes are loaded

```yaml
status: fixed
kind: defect
released-in: 0.2.0
user-visible: yes
```

Pre-existing — reproduced identically on `main` (0.1.13).

**Area:** `core/lib/ovallsp/diagnostics/engine.rb`
(`unknown_route_helper_findings`)

The check gates on `context.route_registry` being non-nil, and `Server`
always constructs one (`server.rb:55`, `:90`, `:809`). Without a Runtime
Agent the registry is *empty* rather than absent, and an empty registry
answers "no such route" for every helper name. So any receiverless call
matching `/_(path|url)\z/` is reported.

Measured with `scripts/corpus_diagnostics.rb`: **48 reports across Ruby
3.4.7's stdlib and 12 more in prism 1.9.0**, every one of them a false
positive on code that has nothing to do with Rails — `original_path` and
`dsl_path` are ordinary private methods in bundler.

Who sees it: a user who opens a Rails app and declines Workspace Trust
(`vscode/package.json` declares `untrustedWorkspaces: "limited"` and
`extension.ts:209` starts the Core with `workspaceTrusted: false` rather
than refusing), and anyone with a non-Rails project containing a method
whose name ends that way.

Two documents assert the opposite today and have been corrected:
README's legend said `—` means "absent by design, not broken", and
`EXTENSION_CAPABILITIES.md` said an untrusted workspace "degrades to its
static-only answer by design".

**Fixed in 0.2.0**, as the direction recorded here said: `RouteRegistry`
answers `#loaded?`, meaning a snapshot has been applied, and the check
returns nothing until one has. `@generation` already counted
applications rather than routes, so a Rails application whose `routes.rb`
declares nothing still loads and the check is still on there — which is
the distinction the old gate could not make.

What made it worth doing now rather than deferring again: 0.2.0 publishes
diagnostics for files nobody opened, so the same false report went from
the open buffer to every file in the project. A reviewer reproduced that
against a two-file plain-Ruby workspace with trust declined.

Three examples: a loaded table that lacks the name still reports, a table
that loaded empty still reports, and a registry no snapshot ever reached
says nothing.

## 024.23 The singleton chain did not model `Class`/`Module`

```yaml
status: fixed
kind: defect
released-in: 0.1.14
```

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

## 024.22 The unassigned-`@ivar` check is silent in an application `rails new` produces

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/server.rb` (`MODELLED_CLASS_BODY_CALLS`,
`class_body_is_accounted_for?`)

The check requires every class body in the controller chain to call
nothing beyond `private`/`protected`/`public`/`before_action`/
`skip_before_action`. Railties 7.2, 8.0 and 8.1 all generate an
`ApplicationController` whose body calls `allow_browser versions:
:modern`. That is unmodelled, the rule applies to the whole chain, and so
the check is silenced for **every view in a default Rails application**.

The G16 capability row passes because
`core/spec/fixtures/rails_real/app/controllers/application_controller.rb`
is a hand-written empty class — a shape `rails new` does not produce. The
row is honest about what it exercises; what it exercises is not what a
user has.

`KNOWN_LIMITATIONS.md` stated the rule abstractly ("`ApplicationController`'s
own body decides this for every view beneath it") without saying that the
default application trips it. That has been corrected.

**Direction:** not another name in the list — `allow_browser` today,
something else next Railties. Two shapes are defensible: treat a
class-body call that assigns no ivar and is not a callback as irrelevant
rather than disqualifying (which needs 024.R7's gem index to know what a
macro installs), or narrow the disqualification to the chain's *workspace*
classes and treat gem superclasses as opaque-but-harmless. Until then the
E2E fixture should carry the generated `ApplicationController`, so the
row measures the real shape and fails honestly.

## 024.21 A qualified constant is coloured half one way, half the other

```yaml
status: open
kind: defect
user-visible: yes
```

Pre-existing for `Foo::Bar` reads; 0.2.0 is where semantic tokens became a user-visible capability (T1).

**Area:** `core/lib/ovallsp/semantic_tokens.rb` (`Collector`)

`Collector` overrides `visit_constant_read_node` but not
`visit_constant_path_node`, so in `Ovallsp::Server` only `Ovallsp`
receives a token and `Server` receives none. A semantic token overrides
the editor's grammar colour, so the two halves of every namespaced
constant render differently — the first half semantic, the second half
whatever TextMate says.

The same module is also `namespace` where it is declared and `class`
where it is read, which is a second inconsistency in the same feature.

**Direction:** visit the path node and emit a token per segment. The
kinds want deciding together with the declaration case rather than
patched one at a time.

## 024.20 `contains?` treats an exclusive end offset as inclusive

```yaml
status: open
kind: defect
user-visible: yes
```

**The half that reached users is fixed in 0.2.1**, and it was the
largest single source of wrong diagnostics this engine produced. The
receiver position a candidate records is the receiver's *exclusive* end
now, which works with the inclusive `contains?` rather than against it:
no inner element's range reaches that offset and the receiver's does, so
the walk answers with the receiver.

Measured over Ruby 3.4.7's standard library, five Rails 8.1.3 gems and
minitest, both revisions over one corpus, diffed by position:
**`unknown-method` 3,747 -> 2,095 — 1,656 removed, 4 introduced.** (Re-measured at 0.2.1's last commit, both sides printing their own tree and version first, with `unresolved-constant` identical at 9,550 on both as the control. The first reading of this — 3,362 -> 1,810, 1,556 removed — was taken four commits earlier and against minitest 5.26.0 rather than 6.0.6.)
`[w].each` reported that a workspace class has no `each`;
`listeners[:on_x]&.each` that a Symbol has none, 604 times in prism's
`dispatcher.rb` alone.

The 4 introduced are all `OpenSSL::Cipher.new(x).key_len` and its
neighbours, and they are 024.13's family rather than this one: the
receiver now resolves *correctly* to `OpenSSL::Cipher`, which the
standard library reopens in Ruby while implementing it in C, so it looks
closed and its C methods look missing. Verified against the interpreter
-- `key_len`, `iv_len` and `digest_length` all exist. Over the real
Rails application at `ovaldev` the change introduces nothing: the two
revisions are byte-identical there, because an ordinary project does not
reopen `OpenSSL::Cipher`.

`contains?` itself is still inclusive, and the entry stays open for it.
What is fixed is one caller that had been compensating for it wrongly.

`docs/design/tasks/026-0.2.1-review-loop.md` carries what round 23 found
and has not fixed, including several entries that overlap this one.

Two things about how this survived twenty-two rounds are worth keeping:

- **The document's own user-facing half described a different
  consequence.** `KNOWN_LIMITATIONS` cited 024.20 only in the paragraph
  about blocks having no type. Nothing told a reader that the engine's
  largest false-positive family was this, so no round went looking.
- **Every round measured the total and not the shape.** 3,362 is a
  number that moves for many reasons; "1,545 of them have a receiver
  ending in `]` or `)`" is one grep, and it names the cause.

`contains?` itself is still inclusive, and that is what keeps this entry
open: it blocks a correct answer 0.2.0 had to settle for approximating.

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`contains?`,
`locate_in_block`), `core/lib/ovallsp/parser_service.rb` (the receiver
position a candidate records)

Prism's `end_offset` is one past a node's last character. `contains?`
compares `offset <= end_offset`, so an offset that sits *just past* a
node is answered as being inside it. The consequence is not academic: a
method-call candidate records its receiver's position as one character
inside the receiver, which for a receiver ending in `)` is the `)` -- and
the receiver's own last argument ends exactly there. `wrap(Widget.new).go`
therefore resolves the receiver to `Widget`, and `unknown-method` reports
a call that runs.

Measured: making `contains?` exclusive fixes it and **fails 39 examples**,
because every caller that hands it an LSP range end -- whose end is
likewise exclusive -- depends on the current rule. The fix is the rule
plus every call site, which is a change of its own size.

What 0.2.0 did instead: `locate_in_block` answers `Types::UNKNOWN` for a
position inside a block whose receiver is not a generic. Descending into
the body is the right answer and was tried -- it produced **230
`unknown-method` reports the shipped line never made**, across Ruby
3.4.7's own stdlib, because descending is exactly what stops masking the
mis-resolution above (`s[:dependencies].map { }` reported as "Symbol has
no method named `map`"). Returning the *enclosing call's* type, which is
what the code did before, is equally wrong in the other direction and is
what made `argument-type` report a string literal inside
`opts.on("-x") do` as an `OptionParser`. Unknown is the only one of the
three that no check acts on.

**Direction:** make `contains?` exclusive, then fix each caller that
passes a range end to pass the last character instead. `mismatched_arguments`'s
`infer_at(document, range[:end])` is the clearest of them -- its own
comment already explains that it wants the argument's last character and
relies on the inclusive rule to get it. With that done, `locate_in_block`
can descend and hover becomes right inside every block.

## 024.19 The argument-type check judges against a class the receiver is not

```yaml
status: open
kind: defect
user-visible: yes
```

Reported by an independent review that drove the engine over 25 installed gems; not reproduced from a fixture here, which is why it is recorded rather than fixed.

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`sole_declared_overload`)

A receiver whose constant path the workspace does not declare reaches
`WorkspaceIndex`'s documented simple-name fallback -- "名前ヒューリスティック",
the one that answers with whatever class shares the last segment. The
unknown-method check has `closed_nominal?` to stop exactly there; the
argument-type check has no equivalent, so it can resolve
`::Vendor::Gadgets::Widget` to an unrelated `Widget` and type-check
against that class's signature.

There is no second report to notice it by, and an earlier version of this
entry had that backwards. `unresolved_constant_findings` skips a
candidate the index resolves (`engine.rb:579`) — and the resolution that
makes the argument check misfire is the same one — so precisely when the
fallback fires, the full constant is *not* reported unresolvable. Only
its unresolvable prefixes are. Verified against a two-file corpus:
`::Vendor::Gadgets::Widget.make(1)` with a workspace `class Widget`
reports `::Vendor::Gadgets` and `::Vendor`, never
`::Vendor::Gadgets::Widget`.

Reported instance: `prism-1.9.0/lib/prism/translation/parser.rb:320`,
`::Parser::Source::Comment.new(build_range(...))` reported as "`new`
expects Location here, but Parser::Source::Range is given" -- where
`Location` is Prism's own type, not the `Parser` gem's.

**Direction:** the check needs the receiver it was written against, not
the one the index guessed. Either gate on the same closedness the
unknown-method check uses, or require the resolved name to end with the
constant path as written. A fixture has to make the simple-name fallback
fire, which the current spec's RBS shape does not.

## 024.18 The unassigned-`@ivar` check cannot enumerate what it needs to

```yaml
status: open
kind: defect
user-visible: yes
```

and **blocked on 024.R7** for the part that needs it. Three of the five shapes are closed in 0.2.0 by staying silent rather than guessing: a class-body call this analysis does not model (which covers every gem macro), a view that renders anything, and everything rounds 3 and 4 fixed. What is left is *precision* -- turning those two silences back into answers -- and one shape that is still wrong rather than silent, and one that is wrong only at depth two or more:

- a view rendered by *another* controller's action (`render "users/show"`
  from elsewhere) sees only its own controller's ivars;
- `UsersController < BaseController < ApplicationController` with the top
  of the chain not yet read. The depth-1 guard covers
  `UsersController < ApplicationController`; applying the same rule to
  every class read is the correct depth but cannot be told from the
  ordinary case, because the last class a workspace declares inherits
  from a gem that no document will ever exist for. Separating "a
  workspace class not read yet" from "a base class in a gem" is exactly
  what R7's attribution provides.

Recorded under the rule in `CLAUDE.md` about a fix aimed at a symptom: three consecutive review rounds each found a *new*
shape where this check warns on code that renders, and each round's fix
addressed the shape rather than the class.

**Area:** `core/lib/ovallsp/server.rb` (`assigned_ivars_for` and its
guards), `core/lib/ovallsp/diagnostics/engine.rb`
(`unassigned_ivar_findings`)

The check reports an `@ivar` a view reads that the controller never
assigns. To be safe it needs a *complete* enumeration of the assignments
a view can receive, and it guards the cases where it knows it cannot get
one: `instance_variable_set`, a mixed-in module, an unmodelled callback
form, an unread superclass, a shape the walk does not fold.

The shapes found round after round, each a warning on a working page:

| round | shape | fix that round applied |
|---|---|---|
| 3 | `@user \|\|= ...`, an assignment in a block, a `case`, a `rescue`, a multiple assignment | count assignments syntactically instead of by type inference |
| 4 | a superclass the index had not read yet | insist the immediate superclass was read |
| 5 | a gem's class-level macro (`load_and_authorize_resource`, `expose`, Devise, ActiveAdmin) | — |
| 5 | an ivar assigned in a partial the view renders | — |
| 5 | a view rendered by a *different* controller's action | — |

The list does not converge, and the reason is structural: **Ruby has
unboundedly many ways to assign an instance variable that this analysis
cannot see**, and a gem's class-level macro is the ordinary case, not the
exotic one. The same repository already draws this line correctly
elsewhere -- README says the unknown-method check stays silent on classes
inheriting from a gem, "so most controllers and jobs", because reporting
there means guessing. This check reports there.

**Direction: ask the Runtime Agent, rather than adding a sixth static
guard.** This is the answer to the question the static approach cannot
reach, and it closes a whole class rather than a shape.

The Agent has the real application loaded. It cannot say *what* a gem's
macro assigns -- that would mean executing the action -- but it can
report a controller's actual `_process_action_callbacks` chain, which is
exactly where `load_and_authorize_resource`, `expose`, Devise and
ActiveAdmin install themselves. Comparing that chain against the methods
the workspace defines answers the question this check actually needs:

> is every source that contributes to this action one this analysis has
> read?

A callback the workspace cannot account for means stay silent. That
subsumes the gem-macro shape, the concern shape, and every framework
callback at once -- and it is the same shape of question the ancestry
registry already asks the Agent, so the transport, the deferral and the
"answer arrives later" handling all exist.

Two of the five known shapes are *not* covered by it and stay static
work: an ivar assigned in a partial the view renders (collect ivar writes
from the partials a template renders, which is a parse away), and a view
rendered by another controller's action (`render "users/show"` from
`AdminController`; the index already knows every literal render target,
so this is a reverse lookup rather than new information).

Until that exists the check does not meet its own stated bar -- "a wrong
report is worse than a missed one" -- on gem-backed controllers, which is
most of them. Whether 0.2.0 ships it meanwhile is a decision about the
release, not a defect to patch in the current change set.

## 024.14 Workspace-wide diagnostics do not fire against the real Rails fixture

```yaml
status: fixed
kind: defect
released-in: 0.2.1
user-visible: yes
```

**It does not reproduce, and did not need fixing.** A reviewer ran the
procedure this entry describes and got the diagnostic; so did I, on a
real Rails 8.1.3 application: a never-opened file is answered **1.35 s
from process start**, with 42 URIs published. `EXTENSION_CAPABILITIES`'s
**G17** row and its example exist now, and the example fails when the
workspace pass is removed.

What the original measurement most likely hit is a path, not a defect.
`Dir.tmpdir` is `/var/folders/…` on macOS and the server publishes
`/private/var/folders/…`; a test that builds the expected uri from the
un-resolved path waits forever for a notification that has already
arrived under another name. The G17 example calls `File.realpath` and
gives the property its own Core, because the file has to be on disk
*before* the server starts -- which the shared client, started in
`before(:all)`, cannot be given. A first draft of the example wrote the
file afterwards and failed, which is a different property.

Five documents carried consequences of the non-reproducing claim and are
corrected: the missing capability row, README's ⚠️ and its `[^ws]`
footnote, `KNOWN_LIMITATIONS` in both languages, and both changelogs.

**The lesson is not "close entries faster".** It is that an entry
recording a *measurement* should record how the measurement was taken
precisely enough to re-run, and this one did not -- so for two releases
nobody could tell the defect from the harness.

**Area:** `core/lib/ovallsp/workspace_diagnostics.rb`, `core/lib/ovallsp/server.rb`

0.2.0's workspace pass is covered by Server-level specs (a mistake in an
unopened file is reported, cleared, re-reported on a disk change, and
refreshed when the answers change workspace-wide) and by unit specs for
the pass itself. It has **no E2E row**, because the example written for
one did not pass: a probe file carrying `UnopenedProbe.new
.definitely_not_here`, present in `spec/fixtures/rails_real` before Core
starts and never opened, produced no diagnostic within 45 seconds.

**A diagnosed cause, not yet fixed.** `republish_open_diagnostics` ends
with `start_workspace_diagnostics`, which calls `begin_pass` --
invalidating whatever pass is running -- and `WorkspaceDiagnostics#run`
restarts from `uris.first` with no resume point. That method is called
from six sites, two of which are *loops*: the ancestry drain (which
drains until the queue is empty) and the model-refresh batch (once per
batch). On a real Rails
app each iteration therefore aborts an O(workspace) pass and starts a new
one from zero, and each new one takes the same global index mutex. That
is a credible mechanism for the 45-second silence above, and it is not
among the three causes guessed at below.

The direction is to coalesce rather than restart: a request arriving
while a pass runs should set "run once more when this one finishes"
instead of spawning a pass of its own. Deliberately *not* done in this
release. It is a concurrency change, the harm is reasoned rather than
measured, and the deterministic test it needs -- one that makes the
overlap real rather than racing it -- is the part that is not cheap. A
half-tested concurrency change made late in a review loop is how a change
set drifts. Its own task, with the 45-second reproduction as the
acceptance test.

What *was* fixed here: `workspace_findings_for` recorded deferred
ancestry questions and never asked them. The buffer path drains in an
`ensure`; this one now does too, so a receiver deferred in an unopened
file is answered rather than waiting for someone to open a buffer.

A second gap in the same pass was found when 0.1.11-0.1.13 were merged
in and the whole branch was reviewed: `workspace_findings_for` built its
semantic context without `assigned_ivars:`, and
`Engine#unassigned_ivar_findings` returns [] without it -- so the
unassigned-`@ivar` check (G16) never ran for any view nobody had open,
which is most of them. The pass does visit `.erb`;
`WorkspaceDiagnostics#language_id_for` exists for that. Fixed on the
merge branch, with a spec that fails without it. It is listed here rather
than as its own entry because it is the same capability's E2E story.

The capability row was withdrawn rather than marked PASS on the strength
of the in-process specs — the document's own rule is that a capability
with no E2E row is not a capability, and marking it anyway is exactly the
failure that rule exists to prevent.

Three causes were guessed at before the one above was found, and they
are kept because none is ruled out and any could compound it: the pass
runs before the Runtime Agent is ready and the later refresh does not
reach it; the receiver is not `closed_nominal?` in a real Rails app the
way it is in the fixture-free specs; the pass never starts at all in that
configuration.

**Direction:** fix the restart-without-resume above, then reproduce
against `spec/fixtures/rails_real` directly to see whether anything is
left, and restore the row with an E2E example behind it.

## 024.R1 Rails-specific behaviour has no explicit boundary (roadmap, 1.0.0)

```yaml
status: open
kind: roadmap
```

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

## 024.R2 Argument *type* checking (done, 0.2.0)

```yaml
status: done
kind: roadmap
released-in: 0.2.0
```

as the narrow version this entry described: the expected type comes from an RBS/RBI declaration, the signature must have exactly one overload and no `*rest`, and both the declared and the inferred type must be concrete classes with no ancestor relation between them. Everything else stays silent.

Two false positives were found while building it, both by mutating the
new code rather than by reading it:

- `Signatures::Environment#ancestors` resolves a *qualified* name, so
  asking with a bare one reported every stdlib subclass as incompatible
  with its parent — an `Integer` passed where `Numeric` is declared.
- RBS's `int`/`string`/`boolish` are aliases meaning "anything that
  converts", not classes, so an object of an unrelated class satisfies
  one. They are excluded by the same rule that tells them apart from Ruby
  constants: capitalisation.

A third, pre-existing, was found on the same lookup: `HierarchyIndex`
reports a class's own entry already qualified, so `rbs_resolves?` asked
for `::::Widget` and found nothing — meaning anything a project declared
in its own `sig/` without also writing it in Ruby was reported as an
unknown method. Both call sites now share one helper.
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

```yaml
status: open
kind: roadmap
```

roadmap. Its three 0.2.0 rows are done; the table below carries a **shipped in** column so the entry can be read as a record rather than only as a plan. Two of the three shipped outright; whole-project diagnostics shipped without a capability row, because the E2E example written for it did not pass (024.14) -- README marks that row ⚠️ and both changelogs say so.

Pylance is the closest well-known reference point for "what a language
server is expected to do" in a dynamically typed language with optional
type declarations, so it is a useful yardstick — not a target to copy.
Rows Pylance has that make no sense here (Jupyter support, IntelliCode's
ranked completions, Python-specific stub packaging) are deliberately
absent rather than listed and dismissed.

Capabilities were read from the `initialize` response and the code, not
assumed. As of 0.2.0: `hoverProvider`, `documentSymbolProvider`,
`definitionProvider`, `referencesProvider`, `renameProvider`,
`workspaceSymbolProvider`, `completionProvider`, `signatureHelpProvider`
and `semanticTokensProvider`. Everything below without a "shipped in" is
still absent.

| Pylance capability | OvalLSP before it | Planned for | Shipped in | Notes |
|---|---|---|---|---|
| Diagnostics across the whole project | Open files only | **0.2.0** | 0.2.0, no capability row (024.14) | The first thing a user noticed as missing. `publishDiagnostics` fires from `reindex`, which only runs for open buffers, so a mistake in a file you are not looking at is invisible. Needs a workspace-wide pass plus a budget, or LSP pull diagnostics. |
| Docstrings in hover and completion | Type, origin and definition location only | **0.2.0** | 0.2.0 | Ruby has RDoc/YARD comments directly above a `def`. Nothing reads them. Hover shows what a thing *is* but never what it is *for*, which is most of hover's value. |
| Semantic highlighting (semantic tokens) | None | **0.2.0** | 0.2.0 | Unusually valuable in Ruby, where `foo` alone is ambiguous between a local variable and a method call on self — the engine already knows which, and the editor currently does not. Covers ERB templates' Ruby regions too, which the shared extraction path now makes free. Distinct from shipping a TextMate grammar, which is a non-goal: VS Code already associates `.erb`, and another grammar would only collide. |
| Inlay hints (inferred types, parameter names) | None | **0.3.0** | — | The type engine's answers are only visible on hover today. Inlay hints put them where the code is, which is the difference between a feature people use and one they remember exists. |
| Code actions / quick fixes | None | **0.3.0** | — | Each existing diagnostic implies one: define the missing method, correct the route helper name, fix the argument count. A diagnostic that only complains is half a feature. |
| Go to type definition | Go to definition only | **0.3.0** | — | Cheap given `explainType` already resolves the type: jump from an expression to the class it evaluates to, rather than to the method being called. |
| Document highlight (occurrences in file) | None | **0.3.0** | — | Small and self-contained: the reference index already answers this workspace-wide, so scoping it to one file is nearly free. |
| Call hierarchy | Find references only | **0.3.0** | — | An incremental step on the same index. Callers/callees of a method, navigable, rather than a flat list. |
| Auto-import / add `require` | None | **0.4.0** | — | Much weaker payoff than in Python: Rails autoloads, and plain Ruby projects mostly `require` at the entry point. Worth revisiting only after the plain-Ruby story (024.R1) exists. |
| Type checking strictness levels | One fixed set of checks | **0.4.0** (as per-check severity) | — | Pylance's basic/strict switch matters because its checks are numerous and opinionated. With the checks this engine has, a per-check severity setting would cover the same need more simply. |
| Signature help with active parameter tracking | Signature label only | **0.4.0** | — | Already useful; highlighting which argument the cursor is in is a refinement, not a gap. |
| Generating type stubs from source | RBS/RBI are read, never written | not planned | — | Interesting for library authors, irrelevant to the Rails application developer this Preview targets. |

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

```yaml
status: open
kind: roadmap
```

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

```yaml
status: done
kind: roadmap
released-in: 0.1.7
```

Measured against the same real application that reported it: 2 diagnostics before, 0 after.

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

## 024.R6 Reading an instance variable that is never assigned (done, 0.2.0)

```yaml
status: done
kind: roadmap
released-in: 0.2.0
```

scoped to views, which is where the symptom the entry describes actually appears. A view is handed exactly what its controller action and callback chain assign, and that set was already computed for type propagation; everything else receives its ivars from wherever it likes, so nothing is reported there.

The safety of the check is one distinction: the set is `nil` when nobody
worked out a context and *empty* when an action genuinely assigns
nothing. Collapsing the two would report every `@ivar` in any file no
context could be established for. `nil` is therefore also the answer for
a view outside the naming convention, a view no action renders, a
controller chain containing `instance_variable_set`, and a document whose
Ruby does not parse — each pinned by asserting nothing was logged, since
the rescue above them produces the same silence for the wrong reason.
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

```yaml
status: open
kind: roadmap
```

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

**It is also what 024.18 waits for.** The unassigned-`@ivar` check
currently stays silent whenever a controller's class body calls anything
it does not model, because a gem's macro
(`load_and_authorize_resource`, `expose`, Devise, ActiveAdmin) installs a
callback that assigns at runtime and nothing can tell that call apart
from a harmless one. With this index, such a call is attributable: "a
method CanCanCan defines, whose body this analysis has not read" is a
sound reason to stay silent, and a class-body call that resolves to a
*workspace* method that *was* read is a sound reason to report. That
narrows the guard rather than replacing it -- every answer the check
gives today it still gives, and it starts covering controllers it
currently declines. Doing it before this index exists would mean
guessing, which is the thing this check refuses to do. **This is a
required part of R7, not an optional extension of it: 024.18 is not
closed until it lands.**

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

## 024.R8 Completion does nothing until you type a dot (done, 0.2.0)

```yaml
status: done
kind: roadmap
released-in: 0.2.0
```

The entry's own reading was right: the work was mostly ranking and bounding, not calling the existing pieces. The order it proposed is the order that shipped (locals, methods on self, workspace constants, Kernel), with two decisions it left open settled as it suggested — a hard cap with `isIncomplete`, and a one-character prefix that returns only the two sources near the cursor.

Two things the entry did not anticipate. The ranking has to be rendered
into `sortText`: an editor re-sorts a completion list itself, so array
order alone pins nothing, and a spec checking array positions passes with
`sortText` deleted. And `WorkspaceIndex#search` matches by substring
because `workspace/symbol` wants that, while a completion prefix means the
start of the name. Filtering `search`'s answer down was the first attempt
and it was wrong: `search` truncates, so on a workspace with more than
`limit` substring matches every prefix match can already be gone -- 250
classes merely containing `art` made typing `art` return nothing at all.
The index gained `#prefix_search`, which applies both the prefix and the
offerable kinds *before* the truncation.
**Area:** `core/lib/ovallsp/server.rb` (`completion_result`),
`core/lib/ovallsp/semantic/query_service.rb`,
`core/lib/ovallsp/semantic/prefix_completion.rb`,
`core/lib/ovallsp/workspace_index.rb` (`#prefix_search`)

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

```yaml
status: fixed
kind: defect
released-in: 0.1.13
```

`ci.yml`'s skip guard now checks both `spec/integration/real_rails_spec.rb` and `spec/e2e/capabilities_spec.rb`, by table rather than by a second copy of the check.

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

```yaml
status: fixed
kind: defect
released-in: 0.1.13
```

for the two decisions a user notices -- `documentSelectorFor` and `statusPresentation` moved into `vscode/src/clientPresentation.ts`, which imports no `vscode`, with fifteen unit tests -- thirteen behavioural, plus two that assert `extension.ts` actually calls them (024.10's first attempt exported the strings but left the choice between them at the call site, so the tests described code the extension did not reach). `resolveStatus` was added in a second pass: the extraction had left the "no client" / "the client did not answer" decision at the call site, where a mutation reporting a failure as "no client" passed all 167 tests.

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

```yaml
status: fixed
kind: defect
released-in: 0.1.13
```

by option 1 below, in the half of it that carries the cost. Option 1 called for both collections to be maintained sorted at write time; `@by_symbol`'s entry lists are, and `@by_simple_name` is still an unordered Set sorted per read -- but by one centralised reader rather than by each of eleven, which is the property the option was chosen for. Sorting a Set on insert would have cost every `replace_file` a sort of every bucket its declarations touch, against a read path that filters first and so sorts a handful of elements.

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

```yaml
status: open
kind: defect
user-visible: yes
```

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

## 024.41 Typing a `.` reports a method on the *next* line

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`analyze`'s parse
gate), `core/lib/ovallsp/server.rb` (`did_change`, which publishes with
no debounce)

Half of this is fixed and half is not, and the half that is not is the
commonest editing action there is: `.` is the completion trigger.

```ruby
a = Article.new
a.
b = "str"
```

→ ``Article has no method named `b=` ``. Also reported for a next line
of `value`, `if true` and `return 1`; not for `puts 1` or
`other_thing(1)`.

The `end` half -- `a.` at the end of a method, where recovery invents
`a.end` -- was fixed in 0.2.1 by gating semantic checks on a clean parse.
This shape defeats that gate because **there is no syntax error at all**:
`a.\nb = "str"` is valid Ruby that means `a.b = "str"`, and it is
reported correctly. Nothing in the text says the user is mid-edit.

**Direction:** not another check. The engine cannot tell this apart from
the same code written deliberately, so the answer is to stop publishing
*while the user is still typing* -- a debounce on `didChange`, and
ideally the edit position, which the notification already carries and the
Server discards. Recorded rather than patched, because a heuristic that
suppresses "a call whose message is on a different line from its
receiver" would also suppress the leading-dot chain style, which is
ordinary Ruby.

Round 23 found it, round 24 found it again and widened it, and it existed
only in `026-0.2.1-review-loop.md` until now -- which is why it is an
entry: a finding parked in a round's handover is invisible to
`deferred_findings_spec.rb`, and `DOCUMENTATION_MAP`'s "A known
limitation" row was therefore unenforced for it.

## 024.42 An RBS signature label says `Unknown` where RBS says `self`, and leaks method type variables

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/signatures/type_converter.rb` (`convert`),
`core/lib/ovallsp/semantic/query_service.rb` (`rbs_signature`)

Signature help shows `push(...) -> Unknown` for `Array#push`, which RBS
declares as `-> self`, and `map() -> Array[U]`, where `U` is the method's
own type variable and means nothing to a reader.

`TypeConverter` maps `self`, `void`, `untyped`, `top` and `bottom` all to
`Types::UNKNOWN`, which is right for the *type model* — nothing
downstream can act on any of them — but a signature *label* is prose for
a human, and "Unknown" is a worse answer than the word RBS actually
wrote. The label is built from the converted type, so it inherits a
decision made for a different purpose.

It became visible in 0.2.1 rather than new: populating `parameters` for
RBS signatures made these labels the thing `activeParameter` points into,
so people read them.

**Direction:** keep the raw declared return alongside the converted one
on `Signatures::Overload`, and render the label from the raw. Not the
converter — every other reader of it is right to get Unknown. Deferred
rather than done because it touches the shape a signature is stored in,
and 0.2.1 was days from release; the two label defects that needed no
model change (a dropped block, duplicate overloads) are fixed.

## 024.43 Signature help answers nothing for a receiverless stdlib call

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/server.rb` (`method_signature_help`),
`core/lib/ovallsp/semantic/query_service.rb` (`signature_owners`)

`puts(` answers `{signatures: []}` while bare-prefix completion offers
`puts` from its own Kernel source. The receiverless path resolves the
enclosing `self` and asks its ancestor chain; `lookup_owners` walks what
the workspace declares, and Kernel is not in it — so every Kernel method
called the way Ruby actually calls them has no signature help.

Round 22 found S1's receiverless half, round 23 fixed it, and this is
S2's: the same row shape, one release later, for the stdlib source
instead of the workspace one.

**Direction:** the receiverless chain should end in `Kernel` the way
`PrefixCompletion#kernel_methods` already does — one source of "what a
receiverless call can reach", read by both, rather than each deciding.

## 024.44 A partial's local is not resolved, and C11's stated basis names it

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/server.rb` (`ivars_for_view`,
`analyzable_document`), `core/lib/ovallsp/local_inferencer.rb`

In a scaffolded application, `app/views/articles/_article.html.erb` uses
`article` — a local the *`render` call site* supplies. Hovering it
answers `""` and `article.` completes to nothing, while the same file's
`@article` (were there one) resolves through the controller action.

C11 reads PASS, and its example writes `<% post = Post.new %>` into the
template first — a local the template assigns itself, which is a
different thing. The example's own comment gives the row's justification
as "a local in a template is what a partial receives", which is exactly
the case it does not cover. The row now says so; this entry is what it
points at.

**Direction:** the type comes from the `render` call site
(`render @article`, `render partial: "article", locals: {article: a}`),
so it needs the same propagation `ivars_for_view` already does for
instance variables, keyed by partial name instead of by action. Deferred
rather than done: it is a new inference path, not a correction, and 0.2.1
is a patch.

## 024.45 Re-analysis after a keystroke is seconds on a large file, against a stated 300 ms

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/server.rb` (`#reindex`, `#publish_diagnostics`,
called synchronously from `#handle_did_change`),
`core/lib/ovallsp/workspace_index.rb`, `core/lib/ovallsp/diagnostics/engine.rb`

Measured as the difference between a run with five `didChange`
notifications and one with none, so the one-off RBS load cancels:

| file | lines | per-edit re-analysis |
|---|---|---|
| `uri/generic.rb` | 1,592 | 4.31 s |
| `net/http.rb` | 2,574 | 2.06 s |
| `rubygems/specification.rb` | 2,666 | 5.25 s |

Super-linear: a synthetic file at 506 lines costs 0.10 s and at 16,006
lines 23.7 s. `ParserService#summarize` is about 19 ms of it; the rest is
reference resolution and the diagnostics engine.

`docs/design/docs/01-product-requirements.md` states `p95 <= 300ms` for
single-file re-analysis, so this is seven to seventeen times over on
files an ordinary Rails application contains. The Core answers one
request at a time, so hover, completion and signature help queue behind
every keystroke.

**Not a 0.2.1 regression** -- `main` measures 4.86 s on
`specification.rb` against 0.2.1's 5.17 s. It is recorded now because
nothing recorded it: `KNOWN_LIMITATIONS` had no mention of latency or
file size in either language, so the product shipped a numeric
requirement it misses by an order of magnitude with no limitation row.

**Direction:** the requirement is about *re-analysis*, and the Server
does it on the dispatch thread inside `didChange`. The two halves are
debouncing (which `024.41` also wants, for a different reason) and
incremental re-analysis of the edited region rather than the file. Both
are their own task; neither belongs in a patch.

## 024.46 Typing `self` cost 55 false diagnostics and was rolled back

```yaml
status: fixed
kind: defect
released-in: 0.2.1
user-visible: yes
```

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`#eval_type`)

0.2.1's round-30 countermeasure spec surfaced that `self.target(1)`
resolved to nothing -- `LocalInferencer` had no `SelfNode` case while
`MethodAnalyzer` did -- so one was added: `self` is the enclosing class,
which the descent already tracks.

Round 31 measured it. Over Ruby 3.4.7's standard library, three runs one
at a time with `unresolved-constant` identical at 7,561 as the control:

| side | `unknown-method` | `argument-type` |
|---|---|---|
| before | 1,034 | 0 |
| with the `SelfNode` case | **1,086** | **3** |
| with that one line reverted | 1,034 | 0 -- byte-identical to before |

**55 new false reports, none removed.** Three families:

- `self.class.foo` -- `self` becomes a Nominal, `.class` resolves through
  RBS to `Class`, and every call on it is reported unknown.
  `unless self.class.correct?(v)` is everyday Ruby.
- `def Const.method` and `class << self` bodies type `self` as an
  *instance* rather than the class object, because `#locate_def` only
  pushes `ClassOf` when the receiver is literally `self`.
  `Class.new(self)` inside `def HTTP.Proxy` was reported as a wrong
  argument type.
- `self.foo` where `foo` is C-defined or declared by a singleton
  `attr_accessor`.

Reverted. Answering nothing for `self.foo` is the trade this project
takes; answering wrongly on `self.class` is not.

**What this cost, and the rule it belongs to.** The case was added
*during a review round*, to satisfy a spec written as a countermeasure
for something else. The loop widened the change set instead of closing
it, which is what `CLAUDE.md`'s same-place rule exists to catch -- and
what caught it here was a measurement, not a reviewer's reading. Giving
`self` a type is a real improvement and belongs in a release that can
measure it properly, with `ClassOf` handled for singleton bodies and
`.class` resolving to the class object rather than to `Class`.

## 024.47 A namespaced class named after a core class loses its diagnostics, and the readers disagree about a shadowed literal

```yaml
status: open
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/index/type_name_resolution.rb`
(`#substitution?`), applied by
`Diagnostics::Engine#shadowed_declared_type?` inside
`#receiver_type_for`

The substitution test recognises a *bare* name that signatures declare
being answered by a workspace class in a different namespace. It cannot
tell a name the user *wrote* -- a bare name is exactly how Ruby refers
to a class from inside its own namespace -- from a name inference
produced, so wherever the rule is applied, it is applied to both
populations at once. 0.2.1 tried both placements, and each was wrong for
one population:

- **Applied at resolution** (`HierarchyIndex#canonical_name`, built
  mid-loop): the literal case was right and every written bare name
  broke -- hover, definition and completion all stopped answering for
  `Range.new` inside `module Billing`. Rolled back before 0.2.1
  shipped.
- **Applied at the diagnostics engine** (what 0.2.1 shipped, and what
  ships today): hover, definition, completion and signature help all
  answer for the written name, and the engine declines to report about
  *any* receiver the test matches. Measured on this tree (0.2.3's
  scope-confirmation pass, controls included): `r.tagg` -- a genuine
  typo -- on a `Billing::Range` receiver is never reported, while the
  identical typo on a `Pricing::Tariff` receiver is. The check is
  silently off for exactly the classes this entry is about.

```ruby
module Billing
  class Range
    def tag(name) = name
  end
  class Invoice
    def run
      r = Range.new
      r.tag("x")     # 0.2.0: hover, definition and completion answer
      r.tagg("x")    # 0.2.1-0.2.3: they still answer -- and this typo
    end              # is never reported (a Tariff's identical typo is)
  end
end
```

(This entry's first version annotated the example "0.2.1: all three
answer nothing". That described the mid-loop resolution-side
arrangement, which was rolled back before 0.2.1 shipped, and the
`KNOWN_LIMITATIONS` paragraph written from it told users a limitation
the shipped build does not have -- while saying nothing about the
diagnostics silence it does have. Both corrected in 0.2.3; believe the
measurement above, not this file's history.)

The literal side, meanwhile, still disagrees with itself while such a
class is indexed: `"hello".` completes to the workspace class's members
and none of String's (0.2.0's behaviour, kept deliberately), hover and
signature help on `"hello".upcase` answer from RBS, and diagnostics
decline. Three readers, three sources.

Applies to `Data`, `Set`, `Method`, `File`, `Time`, `Struct`,
`Comparable`, `IO` and `Random` -- any core name a namespaced class
shares. `Billing::Logger` survives only because `logger`'s RBS is not
loaded by default.

**What the 0.2.1 revert left behind, cleaned up in 0.2.3.** `CLAUDE.md`'s
revert rule ("grep the tree for the thing being reverted before
committing the revert") points here for the full inventory of what
reverting the resolution-side placement stranded:

- an unreferenced method: `Index::TypeNameResolution.canonical`, whose
  only caller was the reverted `canonical_name` (removed);
- an inert constructor parameter: `signatures:`/`@signatures` on
  `Semantic::HierarchyIndex`, assigned and never read (removed, with its
  three construction sites);
- stale comments describing the reverted arrangement as current, in
  `index/type_name_resolution.rb` (header), `semantic/hierarchy_index.rb`
  (`initialize`), `server.rb` (the `@signatures` ordering note),
  `diagnostics/engine.rb` ("resolution itself now refuses"),
  `scripts/corpus_diagnostics.rb` (naming a shadow rule in
  `canonical_name` that is not there), and `CLAUDE.md`'s countermeasure
  exemplar list (holding up the rolled-back placement as the right
  shape) -- four rewritten against the shipped arrangement, and the
  two whose subjects were themselves the dead code above
  (`hierarchy_index.rb`'s `initialize` note, `server.rb`'s ordering
  note) deleted with them;
- a published changelog bullet claiming the reverted completion fix as
  shipped, contradicting its sibling bullet under the same 0.2.1
  heading in both languages (deleted; 0.2.3's entry carries the
  notice);
- the `KNOWN_LIMITATIONS` sections in both languages described above
  (rewritten from measurement);
- a dead e2e client helper (`lsp_client.rb#document_highlights`) from
  the same rollback commit's capability removal (removed);
- a contract line nothing could observe: `substitution?`'s refusal of a
  qualified name was exercised only through the reverted resolution-side
  caller -- its one surviving caller blanks qualified receivers a line
  earlier (`WorkspaceIndex#guessed_type_name?`), and a full-suite sweep
  ran green with the line deleted. Pinned in 0.2.3 by a direct unit spec
  (`spec/ovallsp/index/type_name_resolution_spec.rb`, watched failing
  against the deleted line) rather than removed: the module states the
  bare-name precondition as its own contract, and a refusal that holds
  only because the sole caller pre-filters is 0.2.2's
  emergent-containment lesson over again.

**Direction, re-costed in 0.2.3.** The two shapes stand, and the second
was evaluated concretely against this tree before being declined for a
patch release:

1. Carry the written/inferred distinction into the type -- an inferred
   Nominal is not the same thing as a written constant reference. Still
   the shape that addresses the cause.
2. Stop choosing: let the ancestor chain hold both the workspace class
   and the RBS type, so member lookup finds whichever declares it. A
   simulation (0.2.3's review record, `028-0.2.3-review-loop.md`) showed
   the real bill, and the entry's earlier costing -- "one spurious
   completion candidate on a literal" -- understated every line of it:
   `"hello".upcase(:ascii)`, legal Ruby, becomes an `argument-count`
   false positive whenever the shadow class declares its own `upcase()`
   (`sole_source_declaration` keeps each source's answer singular while
   the receiver's identity is not, and `sole_declared_overload` has the
   symmetric RBS-side family); a written `Billing::Range` gains the
   whole core `Range` API as spurious completion candidates; one hover
   popup mixes an RBS label with a workspace `Defined:`; and making
   literal receivers closed re-opens 024.13's family -- `"".squish`
   under ActiveSupport-style direct additions -- for any workspace
   containing a shadow class. A corpus diff cannot arbitrate any of
   this: the gems that reopen core classes do it at the *top level*,
   where `substitution?` never fires, so the measurement is blind
   exactly where collisions live. Fixtures watched failing, not corpus
   deltas, are the gate if this shape is ever built.

Per the roll-back rule's own step 3 -- the problem goes to its own
release or its own task -- the fix is re-scoped out of 0.2.3, which
carries the documentation and this record instead. 027 deferred "the
hover/completion countermeasure" here; this entry is where that item
landed, and why it is not a code change in a patch.

**Not caught for seven rounds** because `scripts/corpus_diagnostics.rb`
built a `HierarchyIndex` without the `signatures:` the then-current
shadow rule read, so the rule was inert in every corpus measurement the
release quoted (024.48).

## 024.48 The measurement tool ran an engine the server never runs

```yaml
status: fixed
kind: defect
released-in: 0.2.1
user-visible: no
user-visible-note: >
  A tooling defect. Its consequence reached users only through the
  regressions it failed to catch, which have their own entries
  (024.46, 024.47).
```

**Area:** `scripts/corpus_diagnostics.rb`

(The constructions below are the mid-0.2.1-loop arrangement this entry
was written against. The resolution-side shadow rule they describe was
rolled back before 0.2.1 shipped, and 0.2.3 removed the then-inert
`signatures:` parameter from `HierarchyIndex` everywhere -- so on
today's tree the "defective" construction and the correct one read the
same, the rule lives in the diagnostics engine, and the script matches
the server again by *not* passing what no longer exists. 024.47 records
that rollback; the lesson here is unchanged.)

It built `HierarchyIndex.new(workspace_index:)` while `Server#initialize`
built `HierarchyIndex.new(workspace_index:, signatures:)`. The shadow
rule of the day lived in `#canonical_name` and read `@signatures`, so it
did nothing in any corpus run -- and every figure this release quoted
came from those runs. A measurement of a configuration no user gets is
not a smaller measurement; it is a measurement of something else.

Fixed by building it the way the server did. The lesson is the one
`CLAUDE.md` already carries, one level up: *confirm each side ran the
code you think it ran* has to include "and in the configuration a user
would run it in".

## 024.49 A release record kept asserting durations it could not witness ending

```yaml
status: fixed
kind: defect
released-in: 0.2.3
user-visible: no
user-visible-note: >
  Release-record prose (028's guard narrative and the workflow/spec
  comments that copied it); nothing an editor user sees. Entered
  because the same place failed three consecutive review rounds, which
  is the roll-back rule's threshold, and the rule says the entry is
  the deliverable.
```

**Area:** `docs/design/tasks/028-0.2.3-review-loop.md` ("A guard that
could not see its input"), and the ci.yml/pages.yml/guard-spec comments
that carried copies of it

Three consecutive rounds of 0.2.3's review loop found the same
narrative wrong, each time about its relationship to time:

1. **Round 1**: "the check now runs on every push" — false of the
   trigger (`push: branches: [main]` plus pull requests). Hand-fixed,
   in four places at once.
2. **Round 2**: "the check was red on `main` for five days" — a
   duration attached to the wrong fact. The redness began with 0.2.2's
   push (2026-08-16); five days is the publish-before-push gap
   (Marketplace 2026-08-11, repository 2026-08-16), which no in-repo
   check can see. The round's countermeasure — deduplicate the dated
   narrative into 028 and leave only ageless mechanism sentences in
   shipped files — was real and held. But its own restatement
   introduced "lasted under 21 hours".
3. **Round 3**: "lasted under 21 hours" asserts a *completed* duration
   for a condition that had not ended — `main` stays red until the
   release lands on it, and a fixed record cannot date that. (It was
   also arithmetically stale by commit time: the fix existed on the
   branch twenty hours in, but a fix on an unmerged branch bounds
   nothing about `main`.)

**Root cause:** the narrative kept asserting facts whose truth depends
on time and on systems outside the tree — trigger shorthand, deploy
state, the Marketplace, wall clocks. Such claims can silently stop
being true after the commit that states them. Each round fixed the
number; none changed the claim's *shape*, so the next round inherited
a fresh instance of the same class.

**Direction actually needed, applied in 0.2.3:** a fixed record states
witnessed, timestamped events — never durations or completions of
conditions it cannot watch end. An interval may be stated only when
both endpoints are witnessed (publish 2026-08-11 → push 2026-08-16).
Dated narrative does not go into shipped files at all; mechanisms,
which do not age, do — with a pointer to the record that holds the
dates.
