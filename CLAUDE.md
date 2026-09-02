# CLAUDE.md

Project-specific instructions for working on OvalLSP (Ruby Semantic LSP: Core Server + VS Code extension + Rails Runtime Agent).

## What these rules are for

Every rule below is subordinate to two things, and exists to serve them:

1. **General safety obligations** — personal data, the extension's own
   data, the safety of the user's machine. Independent of the product
   vision; what shipping a product at all makes you responsible for.
   Done whether or not anything here or in section 0 mentions it.
2. **[`docs/design/docs/01-product-requirements.md`](docs/design/docs/01-product-requirements.md)
   section 0** — why this product exists, what "finished" means, and the
   principle that a wrong answer is worse than no answer *but letting
   1.0.0 recede forever in pursuit of accuracy is worse than either*.

**Section 0 is the trusted root; this file is not.** Most of these rules
were written after a real incident, which makes them hard to question and
is exactly why they need a root to be checked against. **Not all of them
were**: some are inferences drawn from measurement, or from another
rule, and those are the ones most worth re-checking — an inference
carries the authority of an incident without having paid for it. Where a
rule below does not name what it cost, that is the first thing to ask
about it. If following a
rule here starts working against section 0 — most often by making the
release recede — **the rule is what changes**. Section 0.6 says how to
check one, and how to write one without manufacturing a false rule from
a true instruction. An audit on 2026-08-18 found four passages in this
repository stating the project's own inferences in the maintainer's
voice; that is the failure this paragraph exists to prevent.

## Review cadence (mandatory)

**A round closes when a reviewer that has not seen this change set,
using a method the previous round did not use, reports nothing.** Method
is one of `diff` (read the change set), `drive` (run the product and
compare answers), `attack` (take one guarantee and try to break it),
`reproduce` (re-derive the round's own claims). Each round records which
it used; a closing round whose method repeats the previous round's closes
nothing.

**After three rounds that find defects, ship with the open findings
recorded** — register entry plus a user-facing paragraph in
`KNOWN_LIMITATIONS`. Section 0.4: letting 1.0.0 recede in pursuit of
accuracy is worse than the defects being pursued, and an unbounded loop
has no other outcome. The bound of three is this project's operational
choice, not a maintainer ruling.

**During a review loop, fix; do not add.** A capability a reviewer asks
for is a finding to record. A round reviews a fixed thing, and every
addition between rounds resets it.

**Departing from this rule is written down**, where the release is
recorded. Shipping under the bound above is the rule, not a departure.

*Why it is this and not "repeat until a round is clean": that form
measured reviewer exhaustion. 028 declares merge round 8 clean and the
next entry is an external reviewer finding two defects; eight rounds
followed, one a rollback. Around sixty rounds are recorded across 0.2.x.
Rewritten in 0.2.5 under section 0.6. The per-five-implementation-tasks
trigger is also gone: the last implementation task was 023.8, so it has
not been able to fire in over two hundred commits.*

## Test-first discipline (mandatory)

Write the test before the implementation, in this order:

1. Write a test that expresses the required behaviour and **watch it fail against the current code**. A test that has never been observed failing has not been shown to test anything.
2. Implement the change.
3. Confirm the test now passes, and that the rest of the suite still does.

Writing the fix first and then reverting it to check the new test still counts as verifying that one test — but it cannot reveal the more common problem below, so it is not a substitute for step 1.

### Establish where the expected value comes from, before writing it down

Step 1 says to watch the test fail. It does not say the test is right, and
**a wrong expectation written first is implemented faithfully.**

0.2.8 replaced the parser's six bookkeeping stacks with one value, and the
spec was written first, as required:

```ruby
it "stops answering singleton inside a method written there"
```

That is not what Ruby does. The default definee does not change when a
method body opens:

```ruby
class S; class << self; def build; def helper; :h; end; end; end; end
S.build; S.respond_to?(:helper)      # => true
S.new.respond_to?(:helper)           # => false
```

The code was then written to match the spec, a nested `def` in
`class << self` was recorded as an instance method, and a working call was
reported as an unknown method. Test-first did not prevent it; it *pinned
it into place*, and a review round found it by asking the interpreter.

So, before writing an expected value:

- **A claim about Ruby's semantics is taken from Ruby.** Run it. Paste the
  session into the example, so the next reader can see what the
  expectation rests on rather than trusting that somebody checked.
  **Paste it as a session, not as prose about what Ruby does**, because
  `scripts/check_interpreter_sessions.rb` re-runs every session in the
  tree and re-runs no prose. Two review rounds in 0.2.16 each found a
  false claim about a macro's behaviour in the same rewritten bullet
  list — that `enum` stores the token, that `delegate` under `prefix:`
  does not keep it as a substring — and both were prose. That is the
  same place twice, and the checker is the countermeasure it called for:
  it cannot read the prose, so the rule is to stop writing it. A pasted
  session is now the cheap form, because it is the one something else
  checks. `024.220`.
- **A claim about something outside this tree** — the client, the editor,
  the LSP specification — goes through `docs/CLIENT_BEHAVIOUR.md`, which
  exists because the same failure happened with a claim about
  `vscode-languageclient` that had been quoted forward for two releases
  and was false.
- **A claim about this tree's own numbers** is derived, not typed. See the
  measured-claim markers `core/spec/meta/measured_claims_spec.rb` checks.

The general form: *test-first* is worth what the expectation is worth. Where
the expectation is a belief about behaviour nobody has run, writing it
first converts a belief into an implementation.

### Unpinned behaviour is a defect in its own right

A behavioural line that no test fails on when it is reverted is a defect, and must be reported and fixed like any other — regardless of whether the behaviour itself is correct. Correct code with no test is one refactor away from being incorrect code with no test.

Verify this mechanically rather than by inspection: take the diff hunk by hunk, reverse-apply each behavioural hunk on its own, and run the full suite. Every hunk that leaves the suite green is unpinned. Do this before declaring a change set ready, and record the result.

Established after rounds 9–12 of independent review on the v0.1.5 change set: of the last six findings, four were not wrong behaviour but behaviour that could be reverted with the entire suite still green — including a one-line qualified-name guard whose removal would have made a view show a different controller's inferred types. Each was found only because a reviewer thought to mutate that specific line by hand.

The sweep has a blind spot worth knowing before trusting its number: reverse-applying a hunk that *adds a whole method* only tests that the method exists at all. It says nothing about the individual decisions inside it, because reverting the hunk removes the call site too. A `reset_budget: false` argument living inside such a hunk survived the sweep untested and was caught only by a later reviewer. Treat "N of M hunks pinned" as a floor, and for any hunk that introduces new code wholesale, pin its internal decisions separately.

Two further rules follow from that experience:

- Never run this hunk-by-hunk sweep while another agent is mutating the same working tree. Concurrent mutation invalidates both results. Sequence them.
- A spec whose fixture cannot distinguish the two candidate behaviours is unpinned even though it passes. Prefer fixtures where each branch of the decision yields a *different* observable answer (e.g. a block whose return type differs from the seed type, or two same-named classes in different namespaces), and assert the distinguishing value.

## A test that deletes things, and an assertion that could not fail (mandatory)

For six days, `bundle exec rspec` deleted the maintainer's installed
applications. `store_spec.rb` called

```ruby
described_class.prune_generations(cache_root: "/nonexistent-cache-root", current: "/x", keep: 2)
```

to check that an unreadable cache root does not raise. The unreadable
root was handled exactly as intended — and then the *second* half of the
same method aimed itself at `File.dirname("/x")`, enumerated `/`, found
more entries than it was told to keep, and removed all but the newest:
`/Applications` first. It stopped only because a protected path made
`remove_entry` raise. Identified by an Endpoint Security trace naming
`rspec` as the process unlinking `/Applications/*.app`; reinstalling
macOS had not helped, because re-cloning restores the cause.

Three rules, each of which alone would have prevented it:

- **An assertion that cannot fail is not a test.** `prune_generations`
  swallows every error by design, so `.not_to raise_error` against it was
  true before the method was written and would be true if it deleted the
  disk. Before writing an example, ask what would have to happen for it
  to fail; if the answer is "nothing", it is asserting nothing. This is
  the same defect as an unpinned behavioural line, arriving from the
  other direction — see "Test-first discipline" above.
- **Contain a destructive operation where the deletion happens, not at
  each caller.** Every call site here computed its own target and was
  individually plausible; containment was an emergent property of all of
  them being right at once, which is not a property. One function now
  performs every removal in that class and refuses a path outside the
  cache root, so no present or future caller can aim it elsewhere. An
  entry-point guard is the symptom's fix; this is the class's.
- **Never pass a fabricated absolute path to code that deletes.** The
  spec's `"/nonexistent-cache-root"` and `"/x"` were chosen to be
  obviously fake, which is what made them dangerous: `/x` does not exist,
  but `File.dirname("/x")` does, and it is the machine. Destructive code
  gets `Dir.mktmpdir`, always, including in the examples that assert it
  does nothing.

The wider lesson is about what "this test is safe" rests on. Nothing in
the example named a directory anyone cared about; the path from it to
`/Applications` ran through a `dirname` in another method. Reading the
test could not reveal that, and reading the method it called could not
either — only the two together.

## Catching a failure and continuing is not the default (mandatory)

A swallowed failure does not produce a wrong answer somebody eventually
notices. It produces **the answer that would be right if nothing had gone
wrong**, and this project has been bitten by that at every layer:

- `Cache::Store#load` rescued a "struct size differs" into a silent
  whole-cache miss, so a schema bump that was never made looked exactly
  like a cache that was working.
- `LocalInferencer#assigned_ivar_names` answered `[]` when its parse
  raised, and the check that reads it builds a *union* — so one
  unreadable ancestor file silently removed its ivars and every read of
  one became a false report. The layer above already knew to decline; the
  failure was being caught one layer below the layer that knows what to
  do with it, which is the commonest form of this and the hardest to see.
- `scripts/check_pinned_mutations.rb` reported all four mutations
  uncaught on its first run, because it could not load the code it was
  mutating. **A checker that cannot see the thing it checks reports
  exactly what a working checker reports when nothing is pinned.**
- `prune_generations` swallowing every error by design is what made
  `.not_to raise_error` an assertion that could not fail, in the spec
  that deleted the maintainer's installed applications.

**Every `rescue` in `core/lib` carries a verdict** in
`core/spec/meta/rescue_verdicts.yml`, and
`scripts/check_swallowed_failures.rb` fails on one that does not — in the
suite and as a CI job. Two verdicts are allowed:

- **`surfaces`** — it raises, or reports through a channel a person sees:
  a published diagnostic, an error notification, the Output channel.
- **`contained: <why>`** — the argument, written at the site as well as
  in the file. And the argument that counts is not "this failure is
  unimportant". It is that **no caller can turn the value into an
  assertion about the user's code**: `Types::UNKNOWN`, a `nil` every
  reader already treats as "cannot say", a cache miss that recomputes, a
  prune that leaves the file.

The test to run a site against is not *is this failure important* but
**does the fallback let a caller assert something**. Enumerating is what
decides whether to assert, so a failure to enumerate has to decline —
which is section 0 applied to this class. `Engine#rbs_known_constant?`
answering `false` on failure said "RBS does not know this name", an
assertion made from a question that could not be asked; it answers `true`
now.

*The 158 sites were enumerated and argued in 0.2.13 (`024.122`). The
column that would hold an unargued one is empty and the check keeps it
that way. Many of those arguments are one author's, reviewed by nobody
else yet — a `contained` that turns out to be wrong is an ordinary
finding, and the file is where to record that it was.*

## The simplest thing that could possibly work (mandatory)

**Source, per section 0.6:** the maintainer asked on 2026-08-25 that
DTSTTCPW be set as a working principle so that excess complexity stops
being produced. That is (b) — a dated instruction. Everything below the
next paragraph is (c): this project's generalisation of it, written out
separately so a later session can check the generalisation rather than
inherit it.

**The instruction generalised:** *when you write something, write the
simplest construction that satisfies the requirement in front of you,
and let the next requirement change the shape.* It serves the capability
axis by keeping the number of places that must agree small, and it
serves 0.4 by not spending a release on a mechanism nothing has asked
for yet.

### It is a rule about writing, not a licence to rewrite

This is the whole of what makes it safe here, and the evidence is this
repository's own.

`048` audited ten subsystems for excess and produced eight proposals
large enough to change a release. **Every one of them failed
measurement.** Four would have made the product worse. The headline
reduction — making `#contains?` exclusive — broke 114 examples, added
100 diagnostics over 1,070 Rails files, and once the three compensations
it needed were added came out at **+3 net lines**. `024.47` records a
rule moved to where the value is produced and rolled back. `024.224`
records two attempts at one comparison, both measured unsound.

So: applied to code being written, DTSTTCPW prevents complexity.
Applied to code that works, it is an ordinary change and carries an
ordinary change's obligations — a test watched failing, a corpus driven,
a control in the diff. A simplification is not exempt from the rules
because its intent is subtraction.

### The measure is places that must agree, not lines

The `#contains?` result is the reason this sentence exists. Before
calling something simpler, count:

- how many places must agree about one fact, and whether anything checks
  that they still do;
- how many invariants are held by convention rather than by a type;
- how many readers must remember a rule to read a value correctly.

If those numbers do not go down, it is not a simplification whatever the
diffstat says.

### Where to apply it, concretely

The moment is when you catch yourself **adding the N-th place that must
agree** — not later, during an audit. Four shapes to stop at, each of
which this repository has produced:

- **Information destroyed upstream and reconstructed downstream.**
  `024.224`: `Signatures::TypeConverter` knows an absolute `RBS::TypeName`
  at the moment it builds a `Types::Nominal`, flattens it to a String, and
  three downstream readers then normalise spellings to get the identity
  back. Every recovery rule strong enough to reunite two spellings of one
  class also unites two different classes. Nothing there is unused, so
  YAGNI cannot see it. The simplest thing that could work is to not throw
  the identity away.
- **N bookkeeping structures where one value would do.** 0.2.8 replaced
  the parser's six stacks with one immutable `Index::Cref`. This is the
  successful instance, and it is what the shape looks like when it works.
- **A sentinel every reader must remember to check.**
  `Signatures::Environment::UNAVAILABLE` is a frozen `[]` told apart by
  `.equal?`. It exists for a real defect (`024.223`) and a reviewer found
  a *new* consumer getting it wrong during 0.2.16 — so the "readers must
  remember" cost is being paid repeatedly rather than once.
- **A guard at each caller instead of at the thing guarded.** The
  `/Applications` incident: every call site computed its own target and
  was individually plausible, and containment was an emergent property of
  all of them being right at once, which is not a property.

### And the counter-rule, which is equally load-bearing

**Centralising is not free, and "one place that knows the rule" has a
cheap form and an expensive one.** 0.1.12 moved three naming rules and an
invariant into `Index::SymbolId`'s constructor and one of that release's
regressions existed *only* because logic had moved into `initialize`.
0.2.1 moved the type-name shadowing rule into resolution so its readers
could not diverge, and broke every bare name written from inside its own
namespace (`024.47`, rolled back). A module function that callers invoke
is usually the cheaper form.

The test to apply: **do all the readers really want the same answer?**
If they do, one implementation. If they want the same answer *most of
the time*, they do not want the same answer, and unifying them is how
0.2.1 lost a release.

### How this sits with the YAGNI rule already written down

`AGENTS.md` already says never to implement speculatively. That rule
answers *should this exist*; this one answers *given it must exist, is
this its simplest form*. They fail differently and they are caught
differently — a deletion finds the first and only a substitution finds
the second — which is why both are written, and why `048`'s conclusion
that "the complexity here is earned" is correct **within the question it
asked** and says nothing about this one.

## General implementation discipline (reaffirmed by Task 008.6)

- Fix the underlying design, not the symptom. A local `if` patch that suppresses a symptom without addressing the structural cause is not an acceptable fix in this codebase.
- When a review finding implies "the architecture allows this class of bug," fix the architecture, not just the reported instance.
- Every fix needs a regression test that fails without the fix — see "Test-first discipline" above for the order to write them in and for why passing that check alone is not enough.
- When you discover a bug, flaky test, or other fixable issue while working on something else in this repo, fix it in place, in the same session, immediately — do not spawn it off as a separate/background/recommended task. Established after a flaky mtime race in `core/spec/ovallsp/cache/store_spec.rb` was found mid-session during Task 022.2's verification loop and initially deferred via a spawned task instead of being fixed directly; the user explicitly redirected that this must not happen going forward. This applies regardless of whether the issue is related to the task currently in progress.

## Two rounds in a row on the same place: mechanise, then roll back (mandatory)

**A finding about the previous round's changes is not a problem.** A
round that repairs what the last one got wrong is the loop working. Keep
going.

What matters is **the same place** twice. Track, per round, *which code*
each finding is about — not merely whether it postdates the last round.
Then:

- **First time a place is found twice in a row:** do not hand-fix it a
  third time. Put in a **mechanical countermeasure** — something that
  makes that class of defect fail a check rather than wait for a
  reviewer. Then continue the loop normally. Examples of the right shape,
  from rounds that needed one:
  - two scanners that had to agree about the same text, replaced by one
    both read (0.2.1's `#structural_tokens`);
  - a literal-type table two inferencers kept diverging on, replaced by
    one table both read, with the spec driven from the table
    (`Types::LiteralTypes`);
  - a guard that could not see a finding parked outside its input, given
    the finding as input (`024.41`'s entry, so `deferred_findings_spec`
    enforces it).
  A countermeasure can also *fail*: 0.2.1 moved the type-name shadowing
  rule into resolution so its readers could not diverge, and that broke
  every bare name written from inside its own namespace — rolled back,
  024.47. Moving a rule to where the value is produced is only the right
  shape when every reader really does want the same answer.
  A regression test for the specific instance is *not* a countermeasure.
  It pins the one case and leaves the next one to a reviewer.

- **If the same place is found again after that**, the countermeasure was
  aimed at the symptom too. Stop the loop and roll back:

  1. **Roll back** the whole thread of changes those rounds produced —
     not the last one, the whole thread back to where it started.
  2. **Write down the root cause and the direction that was actually
     needed**, as an entry in
     `docs/design/tasks/024-deferred-review-findings.md`. Name the
     attempts and say why each was the wrong shape. That entry is the
     deliverable; the code change is not.
  3. **Re-scope**: the problem goes to its own release or its own task,
     and the current change set returns to what it was about.
  4. Only then resume the loop.

A correct fix does not need the next round to repair it; if it does, the
round after that will need repairing too, and the change set drifts while
every individual round looks productive. The counting rule is about
*place* rather than *recency* because a round whose findings are all new
ground is healthy however recently the code was written — 0.2.1's round
24 had four of ten about round 23's changes, and every one was a
different place.

Established after 0.1.12, where the index's ordering instability was
"fixed" in rounds 8, 9, 10 and 11 — each attempt bolting a sort onto one
more *reader* of a collection whose *storage* had no order. Round 8
pinned an accident, round 9 fixed two readers of seven with an unstable
sort, round 10 regressed round 9's fix, round 11 restored it. Four rounds,
zero net progress, and the release grew to 47 files and 2,463 added lines
— larger than 0.1.9, 0.1.10 and 0.1.11 combined. The thread was rolled
back and recorded as 024.15.

Two supporting rules follow from the same episode:

- **Do not tell a reviewer to assume the previous round broke something.**
  Doing that manufactures the self-referential findings this rule exists
  to detect, and hides the signal. Ask for defects; do not name where.
- **Centralising a rule into a type's constructor is not free.** 0.1.12
  moved three naming rules and an invariant into `Index::SymbolId`, and
  one of the rounds' regressions existed *only* because logic had moved
  into `initialize` (reading `kind:`/`name:` there silently made two
  required keywords optional). A module function that callers invoke is
  usually the cheaper form of "one place that knows the rule".

## How to ask for an independent review (mandatory)

The review loop above is only worth what the reviewer is allowed to find.
0.1.15 ran eight rounds whose defect counts fell 6, 3, 3, 2, 1, 1, 2, 0 —
and a control run of the last round, given round one's instructions
instead, found a user-visible regression the narrowed round had missed.
024.36 records the experiment.

**Do not narrow what counts as a finding.** Each of these was added to
0.1.15's prompts for a good local reason, and together they made the
count stop measuring anything:

- *"Re-finding a defect already recorded in `024.*` is not a finding."*
  The exclusion list grew from three entries to nine while the count was
  being read as convergence.
- *"Concentrate on X."* X is where the last round looked, not where the
  next defect is.
- *"A clean report is the expected outcome."* Say what a defect is; do
  not say what the answer should look like.

**Keep the corpus list, and never use it to exclude.** Tell a reviewer
what has been measured and at which revision — that is coverage. Telling
them to *avoid* those corpora is what let `delegate`'s missing parameters
through: the Rails gems were on the already-measured list, and the
release had moved seven commits since they were measured. A corpus is
measured against a revision, not for ever.

**Before believing a falling count, run one round neutral.** Same tree,
round-one instructions, plus: *report anything you consider a defect,
whether or not it looks already known or deliberate; if a decision
recorded as deliberate is the wrong decision, say so.* If the neutral run
finds more than the narrowed one, the decline was the instructions.

**A falling count is not evidence on its own.** It cannot distinguish
"fewer defects remain" from "fewer defects can be reported", and in
0.1.15 both were true at once. What it *can* be read against is user
impact: rounds 1–7 each found something that changed what the engine
answers; round 8 found five things and none of them did. That is the
signal worth acting on, and it is a different question from the count.

## A measurement is a claim, and it needs the same care as a test

Three corpus comparisons during the 0.2.x work produced confident false
results. None was subtle, each would have changed a decision, and the
count of findings each invented is recorded in
`docs/design/tasks/026-0.2.1-review-loop.md`:

- a diff computed from a file **still being written** — 79 invented;
- a diff between two runs over **different corpora**, one of which
  included this repository's own `core/lib` — 10 invented;
- a `cd` in a compound command that **persisted**, so both "before" and
  "after" ran from the same worktree — reported the fix as doing nothing.

Before reading any diff: confirm both sides finished, confirm both sides
were given the identical corpus, and confirm each side ran the code you
think it ran. Print the thing you are asserting rather than assuming it.

**Run one measurement at a time, in the foreground.** 0.2.1's last day
added two more to the list, and both came from backgrounding: a second
run started while the first was still alive, so two processes wrote the
same output files; and a rewritten script left both sides `cd`-ed into
the baseline tree, which is the third entry above happening again. Each
was caught before its numbers were read — the first because the totals
were implausibly low, the second because the two sides came out
*identical*, which contradicts a spec already watched failing. Neither
would have been caught by re-reading the numbers.

The cheap form of all of this: before starting, check no process of the
same kind is running; have each side print its own working directory and
version *before* it runs; and put a control in the diff — a category the
change cannot affect, which must come out equal. 0.2.1's control was
`unresolved-constant`, identical at 9,550 on both sides.

**A tool with the right name is not necessarily the tool under test.**
0.2.3's pre-publish gate reported that the packaged artifact's compiled
extensions embed the build machine's home path. The check was re-run by
hand to confirm, came back clean, and a register entry was filed saying
the gate's warning was blind. Both commands were the same text; the
gate's ran under `#!/usr/bin/env bash` and got `/usr/bin/grep`, while
the hand-run went through a shell where `grep` is a function wrapping
`ugrep`, which does not report matches in binary files without `-a`.
The entry was withdrawn. The general form: when you re-run a check to
confirm it, confirm you invoked the same implementation — `type -a`, or
just call the absolute path the script calls.

**A green suite is not a blast radius.** 0.2.5 changed one line in the
RBS type converter, ran the whole suite, found one failure, and recorded
the blast radius as measured. A corpus run then found a second
consequence immediately: the change made a nested *alias* capitalised,
which switched off a guard that told aliases from classes by their first
letter, and ordinary `"a.b".tr(".", "")` started being reported as an
error. No fixture called a selector-typed method on a known String, so
the suite could not have seen it. When a change alters something every
other component reads — a name, an encoding, a key — the suite measures
the radius it already has fixtures for. Drive a corpus.

**And when a measurement disagrees with a spec you have already watched
fail, the measurement is wrong until proven otherwise.** That is what
caught the third one; nothing about re-reading the numbers would have.

**A green suite is a measurement too, and it can be green because it did
not run.** `spec/e2e/capabilities_spec.rb` and
`spec/integration/real_rails_spec.rb` drive a real Rails application, and
without `rails ~> 8.1` and `sqlite3` installed as **local** gems they
skip in full while `rspec` still exits 0 — so a local run reports success
while the suite that decides whether a capability row is true never
executed. CI catches it ("Fail if the real-Rails or capability suites
were skipped instead of run"), which means it bites locally and nowhere
else. Before believing a green run, print the thing you are asserting:
run those two files and check the example count is non-zero, exactly as
the rule above says to do for a corpus diff. `CONTRIBUTING.md` carries
the install command.

## Promoting a finding is making a claim (mandatory)

Splitting a grab-bag entry, giving one a `target:`, marking one
`user-visible: yes`, or writing its paragraph into `KNOWN_LIMITATIONS`
— each of these **restates the finding in the present tense**, with more
authority than it had, in a tree that has moved since it was written.

**Run the reproduction against the tree you are promoting it into.**

0.2.14 split `024.90`'s nine bullets into nine numbered entries and
verified none of them. Driven afterwards, seven reproduced exactly as
written, and two did not:

- `024.130` did not reproduce at all. The engine had answered correctly
  for several releases, and the split published a limitation the product
  does not have — in both languages.
- `024.131` reproduced, but backwards. It said hover "answers nothing";
  it answers `nil` for a local that is a `String`. That is the
  difference between the product declining and the product asserting
  something false, and **section 0 ranks those in the opposite order to
  the way the entry read** — so the wording argued for the lower triage
  of the two.

The second is the one worth remembering. A stale entry that *understates*
its defect is harder to catch than one that is simply wrong, because
nothing about it looks incorrect.

## Writing a check means writing bait for the other checks (mandatory)

Every check here scans tracked content, and a check is tracked content.
So an example, a fixture path, a register number or a scanner's needle,
**spelled the way a real one is spelled, becomes a finding about the
file that hunts it.**

This happened **twelve times during 0.2.14**, in nine different files,
to an author who had the rule in front of them and had just written the
entry describing it. It is not a lapse of attention; the moment of
writing an illustration is the moment the rule is furthest from mind.

Two forms, and the repair differs:

- **In a spec** — use `core/spec/support/unspellable.rb`.
  `unspellable("docs", "brand_new.md")` and `unspellable_number(999)`
  build the string at runtime and leave no literal in the source. It
  refuses a single argument, because one part is a literal.
- **In a comment** — there is no helper, and there cannot be: a call can
  be assembled, an illustration has to be legible. **Describe the shape
  instead of quoting it**, and say in the comment that you did, so the
  next person does not "fix" it back.

**Never exempt the file.** That is the trap the trap sets: exempting
stops checking a file that carries real citations, and the file whose
author was demonstrably thinking about this defect is the last one to
stop checking. `024.126` has the twelve instances and the sweep across
every scanner.

## Two working-practice traps, each of which cost a session (mandatory)

Neither is repository state, so neither can be checked by the
repository. Both are here because they were paid for.

- **`git checkout <file>` discards uncommitted work, silently and
  unrecoverably.** It is the natural way to undo an experiment and it
  does not distinguish an experiment from an hour of work in the same
  file. Use `git stash` (recoverable), or copy the file aside first. The
  rule generalises: *before running a command whose effect is "make this
  file match something else", know what the file currently holds.*

  **And `git stash` protects the work only until it is popped.**
  `git stash pop` restores everything *unstaged*, whatever it was before,
  so a tree that was carefully staged comes back inside `checkout`'s
  reach — and `git checkout -- .` then takes the lot. That is how 0.2.16
  lost an applied patch plus five review-note repairs, from a session
  that had read this paragraph and used stash exactly as it says. The
  sentence the paragraph was missing: **after a pop, commit before doing
  anything whose effect is "make this match something else."** A
  work-in-progress commit is cheap and is the only form of this that
  survives the next command. `git stash pop --index` keeps the staging
  but not the protection.

  What made it recoverable was not git: the change was a patch file on
  disk and five scripted edits, both replayable. *Prefer a form of work
  that can be replayed* — a patch, a script — over one that exists only
  in the tree.

- **A completion check reads whatever the output file holds now, which
  may be a truncated prefix.** A background run's output file was read,
  its tail looked like a suite still going, and the wait loop ran for ten
  hours against a process that had already exited. Do not poll a file to
  decide whether work finished; the harness reports completion, and that
  report is the answer. If something must be waited on, wait on the
  process, not on the shape of its output.

  **The harness reports what it launched, so do not detach from it.**
  Backgrounding with a trailing `&` inside a harness-run command makes
  the harness time the *wrapper*: 0.2.16 got "completed, exit 0" for a
  `preflight` that was still running, and the output file held two lines
  of a nine-check run — the truncated-prefix trap arriving through the
  door the completion report was supposed to close. Let the harness
  background the command itself. If a process really must be waited on
  from a shell, wait on its pid (`while kill -0 <pid>; do sleep …; done`),
  never on its output.

- **`String#sub` expands backreferences in the *replacement*, and one of
  them is a backtick.** A replacement containing a backslash-backtick
  means "everything before the match", so a scripted edit whose new text
  contains an escaped backtick -- an ordinary way to write a literal one
  inside bold Markdown -- pastes the whole preceding file in at the
  anchor. `024.223`'s entry took the register from 11,555 lines to
  25,878 that way, twice. **Use the block form**, which expands nothing:
  `src.sub(anchor) { replacement }`. Two characters, and every
  backreference stops being special. The symptom was a meta spec
  reporting 108 reused entry numbers; the diff was far too large to
  read, and isolating it meant restoring from `HEAD` and replaying each
  edit with `wc -l` after each. `024.225`, and the same class as
  `024.140`.

**And before committing, run `ruby scripts/preflight.rb`.** What it runs
is not enumerated here — `ruby scripts/preflight.rb --list` prints it,
and every prose enumeration of this gate in the repository had gone
stale by the release that added a check to it, this paragraph included
(`024.195`). One property is worth stating because the list does not show
it: the **three** environment-dependent suites — `real_rails_spec`,
`capabilities_spec` and `client_behaviour_spec` — are run separately,
because each skips in full without its local dependency while `rspec`
still exits 0.

It reads **each example's status**, not the count. A count cannot see
this: a skipped example is still an example, so a fully skipped file
reports every one of its examples as pending, zero failures, and exit 0,
which satisfies any count-based rule. (This paragraph quoted a specific
example count until 0.2.17, and so did both scripts, each attributing it
to a different file and none of them to one that still had that many —
`024.196`.) This paragraph described the count-based version until
round 3 found it — which meant the operating document was instructing a
reader to rely on the exact check `024.148` records as unable to fail in
the case it existed for. Twice in one
session a commit was made on a partial run — the suite had been run for
one directory, it was green, and the full run afterwards was not.
It also prints one non-gating `ci:` line after its verdict, because a green preflight is a statement about the Core and says nothing about `vscode/` or about CI (`024.284`). `--install` puts it in a pre-commit hook.

## Documentation is part of the change (mandatory)

Before finishing any change a user could notice, open
[`docs/DOCUMENTATION_MAP.md`](docs/DOCUMENTATION_MAP.md) and walk its
trigger table. It lists every document that a given kind of change makes
stale — including the public site under `site/`, which is *not* generated
from the Markdown docs and therefore propagates nothing on its own.

Do not rely on remembering the list, and do not rely on a review agent to
find what was missed: that was the previous arrangement and it is why the
map exists. Read the file each time. It is short, and it names which
checks already enforce which pairs, so the parts a machine can catch are
marked as such.

Established after 0.2.0 shipped six capabilities without adding a single
row to `docs/EXTENSION_CAPABILITIES.md` — the document `docs/PUBLISHING.md`
defines a "capability" by — leaving the release's own version number
unjustifiable on the project's own terms until a reviewer caught it.

**A revert is the change most likely to leave documentation behind**, and
it is the one least likely to look like it needs a pass: the prose was
correct when it was written, and nothing about undoing a change announces
that it also undid the reason for a paragraph. 0.2.1 reverted its
resolution-side shadowing rule and left an unreferenced method, an inert
constructor parameter, stale comments in six places describing the
reverted arrangement as current, a published changelog bullet claiming
the reverted change as a fix — so the release shipped two bullets under
one heading contradicting each other about one behaviour — and a
`KNOWN_LIMITATIONS` section in both languages describing the rolled-back
arrangement instead of the shipped one, so users were told a limitation
that did not exist while the one that did went unmentioned. All of it was
found by re-measuring rather than by reading, across two releases; the
first inventory itself undercounted ("three comments") until 0.2.3
re-grepped. The cheap check is to **grep the tree for the thing being
reverted before committing the revert**, not after. 024.47 records the
full list.

## Where a release's work lives (mandatory)

**One branch per version, merged into `main` by pull request.** The
branch is `release/<version>` — `release/0.3.0` — and every commit for
that release goes on it. `main` is what has shipped; it is not where a
release is assembled. Set by the maintainer on 2026-09-01, and **`main`
is branch-protected on GitHub since the same day** — a direct push is
refused, ten status checks are required, and the rules apply to
administrators, so this is not a rule that depends on being read.
`CONTRIBUTING.md` lists what is on.

*This is (b) in section 0.6's terms — a dated instruction — and the
paragraphs below it are (c), this project's own reasons, which predate
it and are what it replaces. 0.2.15 through 0.2.18 were built directly
on `main`, so those four releases had no reviewable unit between "a
commit" and "a tag": the change set a reviewer would read existed only
as a range somebody had to reconstruct. A pull request is that unit,
and it is also the place a review round's findings can be answered
where the next reader will find them.*

`release/<version>`, not `feat/` or `fix/`: the older branches were
`feat/0.2.6`, `feat/0.2.7`, `feat/0.2.8` and `fix/0.2.3`, and the
prefix is a claim about the release's contents made before the work
starts. 0.2.17 was named a fix and shipped a capability; 0.2.18 was
going to be a fix and turned out to be a record release. One name per
version needs no such guess.

**None of those branches is deleted once merged, and that includes the
old ones.** `main` squash-merges, so a release's individual commits are
reachable only from its branch — 21 for `release/0.3.0`, 25 for
`fix/0.2.3` — and with them every commit message saying why a change
was made. `main` can say which release changed something; only the
branch can say which change did, and this project asks that question
often enough to have answered it twice in 0.3.1 alone. Nothing is at
risk in the code: `main` is strictly ahead of all of them. Deleting one
is a decision to record, not tidying up; `CONTRIBUTING.md`'s "A merged
release branch is kept" has the demonstration. Local branches and
worktrees are the ordinary clutter and need no ceremony.

The task file on `main` that names the release also names that branch.
A pointer to a file that exists only on an unnamed branch is a pointer
to nothing for every session that cannot see the branch.

Starting or resuming release work begins with `git fetch --all
--prune`, listing the remote branches, and reading the
highest-numbered `NNN-*.md` on every branch whose name or record
claims the release — not only on `main`. When work moves between
branches, or a branch is renamed or renumbered, the record on `main`
moves in the same change.

Established by 0.2.3, which was prepared twice in parallel: 027 on
`main` said the work "continues in `028-0.2.3-review-loop.md`", that
file existed only on `fix/0.2.3`, nothing on `main` named that branch,
and a session starting from `main` rebuilt the release from the
pointer. The two preparations converged independently on several
identical corrections — worth something as evidence the corrections
were load-bearing, but bought with days of duplicated work. 028's "Two
preparations, one release" section records the merge and the
dispositions.

## Public repository privacy and secret handling

- This repository is public. Never commit or push secrets, credentials, tokens, private keys, private URLs, personal information, or personal email addresses.
- Treat Git author/committer metadata, generated artifacts, logs, fixtures, snapshots, and copied command output as possible disclosure paths, not only source files.
- Use an established public noreply address for commit metadata. Before every push, inspect the complete outgoing diff and commit range and run the repository's secret scan; stop rather than push if any sensitive or personal data may be present.

**One of these is now machine-checked, because the prose alone failed
twice.** 0.2.1's record named a scaffolded application by its absolute
path, and 0.2.3's pre-publish gate quoted the build machine's home
directory into a task document *and* a commit message — the second
channel being one the line above already names, which is the point: a
rule that lists disclosure paths does not make anyone see them. Per the
same-place rule, the third pass is a countermeasure.

`scripts/check_home_paths.rb` is the single detector, read by both places
that must agree about it: `core/spec/meta/home_path_guard_spec.rb` scans
tracked content on every suite run, and ci.yml's secret-scan job runs
`--messages` over commit messages, which no tree scan can see. Adding a
name to its `SYNTHETIC` list is a deliberate edit with a reason; an
unknown name fails. The script refuses a shallow clone rather than
scanning one commit and reporting the history clean.

Note what it does *not* do: it guards content arriving from here on, not
history. The instance already published in `main` stays, because
rewriting that history would orphan the `buildCommit` SHAs baked into the
0.2.1 and 0.2.2 VSIXs the Marketplace still serves — an integrity loss
for no privacy gain, since the name is the published Marketplace
publisher id in `vscode/package.json` regardless. That is a decision, and
`docs/design/tasks/028-0.2.3-review-loop.md` records it.
