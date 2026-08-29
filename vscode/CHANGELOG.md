# Changelog

[日本語版](CHANGELOG.ja.md)

All notable changes to the OvalLSP VS Code extension are documented here.
Each release leads with what changed; the reasoning, the measurements and
the disproved approaches are kept below it under **Details**.

## 0.2.16 — the backlog, driven

Every open finding this release named was reproduced against the tree
rather than read: 111 of them, each with a control in its own fixture.
94 reproduced exactly as recorded, 13 differently, and 4 were reported
already fixed — two of which an independent check overturned. What
follows is what the driving found and fixed.

- **`self.` completes.** Typing `self.` offered nothing at all, while the
  same position with an explicit receiver completed normally. It now
  takes its type from the class the cursor is in, including inside
  `class << self`. The undefined-method check deliberately still says
  nothing about `self` — measured, letting it assert there added nine
  false reports to ActiveSupport's own source and removed none.
- **A receiverless `format(` or `puts(` gets signature help.** It
  answered for an explicit receiver and not for a bare call. 3,046
  answers gained across a 7,900-probe comparison, none lost.
- **Hover answers in a view.** With the caret on a model method inside
  `<%= @user.full_name %>`, hover was empty while completion offered the
  method and go to definition opened it. All nine position handlers read
  the same document now, so they cannot disagree about one position
  again.
- **Find References stops answering from a comment.** The caret anywhere
  inside a method's body — including inside a comment, on a bare number,
  or on `end` — listed that method's call sites, as though it were on the
  name. Rename, asked at the same positions, had always declined
  correctly.
- **Each name a macro declares gets its own place in the outline.**
  `attr_accessor :alpha, :beta` produced rows that all pointed at the
  whole macro call, and picking the second one answered about the first.
- **`trap`, `set_trace_func` and `iterator?` stop being reported
  missing.** Three names the interpreter gives every object that the
  bundled signatures do not declare.
- **"Go to Symbol in Workspace" no longer blocks indexing while it
  answers.** A two-character query went from 10.4ms to 4.0ms on a
  15,000-symbol workspace, and the request stopped holding the lock
  indexing needs for the length of a full scan.

### Details

**What the driving pass was for.** Two of the 111 entries were reported
fixed by a triage agent and by the independent agent checking it, and
both were wrong in the same way: they drove a spelling the entry did not
name. `024.19`'s rooted and namespaced spellings really are fixed; its
title and its published limitation are about the *bare* one, which
resolves a constant Ruby raises `NameError` for and then judges an
argument against it. A verifier handed the same fixture to try is not an
independent measurement.

**Two entries stated their own defect backwards, and both were this
project's own writing.** `024.242`'s title said a class held in a local
loses an overload; the narrow answer is the correct one and it was the
*constant* spelling asserting a return the signature does not allow — a
reader repairing it from the title would have widened the wrong side.
`024.240`'s recorded cause named two handlers where only one was at
fault. Closing an entry freezes its cause into the record, so both are
corrected rather than left standing beside fixes that contradict them.

**Three fixes were built, measured, and not shipped.** A fix for the
reopened-core-class reports removes eleven false ones over a gem corpus
and silences four real typo reports; a shared type-identity path for the
argument check silences a true mismatch as soon as one unrelated class
shares a last segment; and an optimisation of the scope walk answers with
no locals at all when the walk hits its step budget. Each is recorded
with its measurement and its reproduction.

**A check now re-runs the evidence.** This project requires a claim about
Ruby's semantics to be taken from Ruby and pasted in. Those 89 pasted
sessions were inert text — a mis-transcribed one reads exactly like a
correct one. They are re-run on every suite run now. Not one was false,
so this closes no defect; it stops one arriving, and it makes the pasted
session the cheap way to state a behavioural claim, because prose stating
the same thing is checked by nobody. Two review rounds in this release
each found a false claim about a macro written as prose.

**Nothing user-facing was published that the product contradicts.** Three
limitations shipped in both languages saying the opposite of what the
server answers — that completion is silent inside a module body, that the
symbol picker switches to an index after two characters, that the client
sends an empty query when it opens. Each was driven and rewritten, and
the one about the client now goes through the document that requires a
source for a claim about the editor.

## 0.2.15 — answers the engine already had

Every fix here is a case where the engine knew the answer and something
between it and the reply threw it away. No capability is added.

- **`String.new(`, `File.read(`, `Integer.sqrt(` answer again** — in
  signature help, hover *and* go to definition, all three of which were
  silent for every class method the standard library declares. A class
  receiver reached the lookup as an internal wrapper type, so RBS was
  asked about a class that does not exist. 14 stdlib calls measured, 0
  before and answering after, with six controls unchanged.
- **A signature is spelled the way you wrote it.**
  `def simple(a, b = 2, *rest, key:, opt: 1, **others, &blk)` presented
  as `simple(a, b, rest, key, opt, others, blk)`, telling you `key` was
  the fourth positional argument when it is a required keyword. Hover
  showed the same string and is fixed by the same change.
- **One unresolvable `include` in your own `sig/` no longer turns that
  whole class into false reports.** The RBS ancestry build failed, was
  swallowed, and came back indistinguishable from "this type has nothing"
  — so methods your signature file declares were reported missing.
  Measured on the `rbs` gem's own 89 hand-written signatures: 20 false
  reports, now none.
- **An argument written as a paren-less call is judged as itself.**
  `w.label(w.make 1)` was judged by the trailing `1`, which both reported
  a String argument as an Integer *and* hid the real mismatch in
  `w.resize(w.make 1)`.
- **Picking a class in the outline selects its name**, not its whole
  body.
- **Completion says which methods only one branch of a union has.**
  On `x = cond ? "s" : 1`, the ones both branches have now sort first.
- **A `private` written inside an ordinary loop reaches the methods
  below it**, as Ruby does — and so do `protected`, `public` and
  `module_function`.

### Details

Seventeen register entries close here. The account is in
`docs/design/tasks/047-0.2.15-scope.md`, including a triage of the
thirty-four entries that had queued up behind this release: five of its
seven batches were refuted by an independent pass, one proposed closure
turned out to be a live defect, and nothing was closed on contested
evidence.

## 0.2.14 — the record, and the checks that keep it true

**Nothing in this release changes what the extension answers.** Every
line it touches in the engine is a comment, and the VS Code extension is
untouched. It is here because the project's own record had drifted from
the product, and because several of the checks meant to notice that
could not fail.

- **A limitation this product does not have was published to users, in
  both languages.** A finding was split into nine entries and seven of
  them were verified; two were not, and one of those described a defect
  the engine had not had for several releases. It is withdrawn, and the
  paragraph is gone.
- **Three checks could not fail in the case they existed for.** The one
  that asked "did the suite actually run" counted examples, and a fully
  skipped file still reports examples. The one that hunts a text pattern
  had matched its own prose and exempted its own file. The one that
  scans the tree read only committed files, while the commit gate runs
  before the commit.
- **A scripted edit doubled a register entry and every check stayed
  green.** Duplicate headings now fail.
- **`PUBLISHING.md` documented the publish command that shipped a
  corrupt VSIX** as v0.1.2, and kept it for twenty-five releases.
- **A corpus run did not record what it had run**, so two measurements
  taken against different trees could look comparable. It now prints its
  own working directory, revision and corpus digest before it starts.
- Smaller: a script that crashed under a locale-less shell on the very
  input it exists to report; a leak check that counted every descriptor
  in the process and flaked under load; a review harness that reported
  "nothing found" when its own post-processing had crashed; and the
  example count in three documents, which had been three hand edits per
  commit and is now derived.

### Details

The full account is in `docs/design/tasks/046-0.2.14-making-the-record-true.md`,
including the audit that started it, the hypothesis that turned out half
wrong, and three review rounds whose findings are recorded rather than
resolved — this project ships with open findings written down rather
than letting a release recede.

## 0.2.13 — what a class's own body says, and failures that stop being silent

- **A class that runs a macro this extension cannot read no longer
  reports the macro itself.** It already declined to report anything the
  macro might define; reporting the call that opened that door was the
  same fact answered two ways. Measured over 1,659 files of 16 installed
  gems, `unknown-method` false reports fell from 506 to 389 — 119 gone,
  none added, and the one real latent `NoMethodError` in that corpus is
  still reported.
- **`attr_accessor` written inside a `def` inside `class << self`** is
  read the way Ruby reads it — an instance accessor — instead of a class
  one, so calling it from an instance method stops being reported. Real
  code has the shape: ActiveRecord's `has_and_belongs_to_many` builder,
  `csv/parser.rb`, `cgi/core.rb`, Devise.
- **`def Foo.bar` is a class method.** It was recorded as an instance
  one, so both answers were inverted: the call Ruby runs was reported and
  the call Ruby raises on was accepted.
- **`private`, `module_function` and `attr_accessor` written in an
  ordinary loop** — `%w[a b].each { … }` — reach the class around them,
  as Ruby makes them.
  *Correction, 0.2.15: only `attr_accessor` did. The two visibility
  halves of this bullet were not true of 0.2.13 or of any release before
  0.2.15, which is where they were actually fixed. `attr_accessor`
  records a declaration while the shared context is installed; `private`
  produces state, and the block frame discarded it on the way out. This
  note is left rather than the bullet edited, so the correction is
  visible to anyone who read the original.*
- **`K.instance_eval { attr_accessor :x }` and `K.class_eval { … }` get
  the same answer**, which is what Ruby gives them, and neither is
  attributed to the class the call is *written* in.
- **A `Struct.new`/`Class.new` block's methods stop appearing on the
  class around it.** They belong to the class being built.
- **`define_method(:name)` puts the name in hover, go to definition and
  completion**, instead of only silencing reports about it.

### Details

**What the release was for.** Every fix above is one shape of a single
question: *when this engine cannot enumerate something, does it say so,
or does it answer as though nothing went wrong?*

The second half is the part with no user-visible bullet. Every `rescue`
in the Core Server was enumerated — 158 of them — and each now records
what it does with the failure: it surfaces, or it carries an argument for
why no caller can turn the value into a claim about your code. **Three of
them failed that test and were changed**: a parse failure was making
`defined?(@x)` report, another was quietly removing one file's instance
variables from the set the check compares against, and a third was saying
"RBS does not know this name" about a question it had not been able to
ask.

A check keeps the list complete, and this project's own working
agreement now says that catching a failure and carrying on is not the
default.

## 0.2.12 — the apparatus, and what it found

Nothing in this release changes what OvalLSP answers about your code. It
changes what this project can find out about itself, and the four things
that turned up while building it are the reason the release exists.

- **A private alias was being offered by completion.** `alias_method
  :aka, :build` followed by `private :aka` put `aka` in the list, and
  picking it raises. Two earlier releases had fixed the halves of this
  separately — one put aliases into completion, one filtered private and
  protected — and neither made them meet, because an alias has no
  declaration of its own and the visibility rule reads declarations.
- **A class method your workspace adds to `Object` is reachable again.**
  `class Object; def self.foo; end` is inherited by every class in Ruby
  and was inherited by none here. This is the one shape the changelog has
  described as *worse* than 0.1.14 since 0.1.15.
- **A module included by a bare name keeps its methods.** If your class
  writes `include Helpers` and any other namespace in the workspace also
  has a `Helpers`, that module's methods used to disappear from
  completion, hover and go to definition. Ruby is not ambiguous here —
  it looks the name up where you wrote it — and neither is this now.
- **Diagnostics keep updating if your editor reopens a file without
  closing it**, and a corrected answer is no longer overwritten by a
  slower one computed from less.

### Details

**What the release was actually for.** Three review rounds in a row, over
three releases, found an example that could not fail under the change it
was written to guard against — a test that passes whatever the code does.
Reading cannot find those, and this project had been finding them one
reviewer at a time.

A spec can now name the mutation it claims to catch, and a CI job applies
each one and requires the failure. It is not a substitute for judgement;
it makes a *stated* claim unable to be false.

On its first working run it found a clause that was documented as a
deliberate trade-off and was dead code. Then, asked about an older
release's decisions, it found a fix that had been designed, described in
the register as shipped, and never actually written — the private-alias
bug above. Then it found a claim about which test pinned which decision
pointing at the wrong test.

None of those is visible by reading. They were all passing.

## 0.2.11 — what the engine may assert

Five fixes, all of one kind: this extension was answering from evidence
that did not establish the answer.

- **A concern's class methods reach the class that includes it.**
  `Article.cm_public` from a `class_methods do` block, and from the older
  `def self.included(base); base.extend(ClassMethods); end` spelling —
  both were reported as missing methods, and both work.
- **`module_function :name` works when the method is in another file.**
  `module Reopened; def r_a; end; end` in one file and
  `module Reopened; module_function :r_a; end` in another: `Reopened.r_a`
  now has a hover, a definition to jump to, and a place in completion.
  It had none of the three.
- **A bare class name is resolved through what your class inherits.**
  `Config` inside `class Runner < Zbase`, where `Zbase::Config` exists,
  means that one — as Ruby does — instead of a top-level `Config`.
- **A class that answers through `def self.method_missing`, or whose
  class methods are made by `define_singleton_method`, is no longer
  reported for the calls it really does answer.**
- **A file reopened without being closed keeps getting diagnostics.**

### Details

**What this release does not change**, measured: over four Rails gems,
`unknown-method` findings are 84 before and 84 after, with
`unresolved-constant` identical at 1,099 as a control. Nothing added,
nothing removed. The fixes above are for shapes those gems do not
contain, and each was checked against the Ruby interpreter one at a time.

**One change was tried and taken back out.** A macro this extension
cannot read — `attr_atomic :thing` from a gem's DSL — is still reported
as a missing method, which is wrong. Silencing it also silenced every
`Foo.bar` check in the whole workspace whenever any file reopened
`Module`, `Object` or `Kernel`, and hid a real latent error in Rails
itself. `docs/KNOWN_LIMITATIONS.md` describes what is left, along with
everything else open.

## 0.2.10 — an answer knows what it was computed from

- **Typing on a large file stops queueing your questions behind stale
  work.** Every keystroke used to start a full re-analysis and publish
  its result, so a hover asked while you were typing waited behind all of
  them. Measured on a 3,900-line file: a hover asked during a burst of
  edits took **1.43 seconds; it now takes 0.04.** A burst of edits faster
  than one analysis produces one answer — about where the buffer landed
  — instead of one per keystroke, and the client is no longer throttled
  by the server while it types.
- **A class of yours named like another class of yours resolves the way
  Ruby resolves it.** `Config` written inside `module App` means
  `App::Config` if `App` declares one, exactly as the interpreter does —
  so `App::Config`'s own methods are no longer reported as missing while
  the call that really raises goes unmentioned. The Rails shape of this
  is a `Billing::Comment` beside an ActiveRecord `Comment`.
- **`class_methods do` in an ActiveSupport::Concern attaches to the
  class.** It was attributed to instances: completion offered those
  methods after `Article.new.`, and the undefined-method check accepted a
  call that raises while reporting `Article.cm_public`, which works. All
  four of those answers are now what Ruby does.
- **`module_function` and `extend self` produce their methods.** Both
  idioms produced nothing at all — `MF.` completed 190 items with no
  `mf_a` among them — while `def self.x` in the same module worked. The
  bare form, the by-name form and the `module_function def` form Rails
  itself writes are all recorded now.
- **A Ruby that cannot run the Core no longer half-starts it.** Four
  documents said this extension stops before answering anything on an
  incompatible interpreter, and it did not: it warned and served answers
  anyway. It now checks, before starting, whether your Ruby can load
  either this build's bundled `prism`/`rbs` or its own — and if neither,
  the Core Server does not start and says so. If it merely could not
  determine your Ruby's version, that is no longer fatal on its own.

### Details

**Underneath**: a published diagnostic now carries the buffer it was
computed from rather than a version integer. A version is chosen by your
editor and is only meaningful inside one buffer — across a close and
reopen it may start again anywhere — so comparing two of them across
buffers was comparing numbers on different scales. And analysis follows
the state a buffer settles into rather than every event on the way to it:
not a debounce, with no interval to tune, but a question about whether
anything else is waiting to be read.

**What the review found, because it is worth knowing what a release
costs.** Three rounds, and the third — which ran the product against real
Ruby rather than reading the change — found 41 false reports on shipped
Rails source that the two reading rounds had both missed. One was a fix
from the round before it. Nothing in that list reached this release; the
work it required is why `module_function` ships and a typo in
`PlainMod.nope` still is not reported. That last one is in
`docs/KNOWN_LIMITATIONS.md`, along with everything else left open.

## 0.2.9 — one question, asked once, answered honestly

- **Completion no longer offers a name that would raise if you picked
  it.** A private method on `obj.` and a protected one on
  `other_object.` are both uncallable from where you are typing, and
  both were being offered. So was a private *alias* — `alias_method
  :aka, :build` followed by `private :aka` — which slipped through
  because an alias has no declaration of its own for the visibility rule
  to read.
- **The undefined-method check stopped reporting methods that exist.**
  `to_s`, `send`, `frozen?` and anything a module such as `Comparable`
  brings in were reported as unknown on some receivers: the check asked
  whether an ancestor was *declared* anywhere, never whether it *has* the
  method. Measured over 213 files of installed gems, `unknown-method`
  false positives fell from 54 to 6.
- **Signature help stopped offering a choice that does not exist.** A
  method that overrides another showed both signatures — Ruby calls
  exactly one of them. 0.2.8 fixed the case where the override reused its
  parent's parameter names; this fixes the ordinary case, where it
  renames them.
- **A class receiver still answers.** `Widget.build(` was briefly
  answered by nothing while the above was being fixed; there is now an
  example holding it.

### Details

**What changed underneath, and why the list above is short.** Asking
"does this receiver have this member" returned a list, and an empty list
meant two different things: the member is not there, or the receiver
could not be enumerated at all. Every feature reconstructed the
difference for itself, and each learned about a new way of not knowing
only after it had reported something false — six times in `0.2.6` alone,
one per review round.

The answer is now a value with three states, and `unknown` is produced by
whatever failed to enumerate rather than inferred by whoever received it.
A caller cannot get from `unknown` to "not there" without saying so. The
practical consequence is that the next way of not knowing makes every
feature silent by construction instead of by each one being taught, which
is the only version of this that stops costing a false report per
discovery.

**What is still open.** Three examples added by this release may not
distinguish the behaviour they pin — the fixture passes under either
candidate answer. One of the four reported was found and fixed (it is the
signature-help item above); the other three were lost before the list was
written down, and re-deriving them is `024.109`, deliberately left for
0.2.10 rather than done inside the review loop that found them.

## 0.2.8 — the parser's bookkeeping, and a file's identity

- **A workspace opened through a symlink no longer shows every file
  twice.** This extension analysed your files under the *resolved* path
  while the editor talked to it about the path you opened, so the
  Problems panel listed the same file twice and the second copy could
  never be cleared — not by fixing the errors, not by saving, not by
  closing the tab. It now uses the folder the editor named. Symlinked
  checkouts are ordinary: `/tmp` on macOS, git worktrees, a `~/src` that
  points at a volume.
- **Go to definition returns a path your editor will use**, so following
  it no longer opens a second tab of the file you are already in.
- **Underneath: the parser stopped deciding a declaration's owner from
  six separate pieces of bookkeeping.** Five recorded defects and every
  one of the "this macro was attributed to the wrong side" fixes of the
  last four releases came from twelve places each consulting whichever
  subset its author remembered. There is one value now, and it answers
  the question rather than exposing the state.

### Details

No capability row moves, and the parser change is measured rather than
argued: its whole output was compared before and after across **3,606
installed gem files and 976 standard-library files** — every declaration,
every alias, every ancestor, every reference — and the reference records
came out byte-identical across 634,508 of them.

`docs/KNOWN_LIMITATIONS.md` gained six sections. All six are defects that
were already there and are now written down, found by a reviewer driving
the product: a class of yours named like another class of yours can be
answered with the wrong one; `class_methods do` in a concern is
attributed to instances; `private` inside `class << self` does nothing;
`module_function` and `extend self` produce no completions; an alias is
missing from completion though every other feature knows it; protected
methods are offered where they cannot be called.

Five of those six are one thing seen from six angles — the same question
asked through four different code paths, and an enumeration that cannot
say when it was incomplete. That is what the next release is for.

## 0.2.7 — a document cannot be read half-written, and a publish cannot arrive out of order

- **Closing a file no longer leaves its errors behind.** A re-analysis
  pass running in the background decided which files to visit before it
  started, so one already in flight republished a file you had just
  closed — and nothing republishes a file nobody has open, so those
  errors stayed in the Problems panel for the rest of the session. This
  was in every version this extension has shipped.
- **And a slower analysis cannot put its older answers back.** Every
  publish now goes through one place that remembers what it last said
  about a file, refuses anything older, and lets closing a file win.
  Reopening a file starts over cleanly: an answer computed for the
  buffer you closed can no longer be mistaken for one about the buffer
  you just opened.
- **A file's text, version and line positions always belong together.**
  They were written one at a time while background work read them, so a
  position could be worked out from new text against old line offsets.
  Measured on the previous version: under a concurrent edit, 1,977,450
  of 1,977,451 attempts returned a position belonging to neither. That
  is the arithmetic under hover, completion and go to definition.
- **A file deep enough to exhaust Ruby's stack, and a malformed message,
  no longer end the session** — carried over and hardened.

### Details

No capability row moves. This release is about answers arriving in the
right order and about a document never being readable half-written.

`docs/KNOWN_LIMITATIONS.md` gained six sections rather than losing them,
and one of the ones it kept was corrected: closing a saved file *does*
still bring diagnostics back, recomputed from disk, which is how this
extension has reported on unopened files since 0.2.0. What was fixed is
the stale copy from the buffer you closed. Saying only the first half was
an over-claim, and a review round caught it.

Four independent review rounds ran against this release — reading the
change set, driving the product, attacking its guarantees, and
re-deriving its own claims. The first attempt at the publish rule
introduced a defect **worse than the one it fixes**: close a tab while
work is in flight, reopen it, and the panel would freeze on the pre-close
errors for hundreds of edits. Two rounds found it independently. It is
recorded in full, because a release that only lists what it fixed is not
telling you how it got there.

## 0.2.6 — The undefined-method check, made honest

- **False "has no method" reports on real code: 54 → 6.** Measured over
  the same 213 files of installed gem source each time, one run per
  revision. A class whose body runs a macro this extension cannot read —
  `attr_atomic`, `safe_initialization!`, `singleton_class.send
  :alias_method` — now has a method set it admits it does not know, and
  says nothing rather than guessing. So does a class that `include`s or
  `extend`s something it cannot identify, including a module named only
  at runtime: `include Singleton` no longer reports `.instance`, and
  `include Sidekiq::Worker` no longer reports `sidekiq_options`.
- **`alias_method :create, :new` written above `def new` is read the way
  Ruby reads it.** An alias binds to what the target means at that
  moment, not to a definition five lines below. ActiveSupport's own
  `TimeZone` got two false "takes 1 argument, but 3 given" reports from
  this, and the same construct elsewhere got "has no method named
  `create`" — two checks, two different wrong answers about one alias.
- **A call that does not exist through a relation is now reported.**
  `Order.recent.first.no_such_method` was reported by nothing while
  `Order.find(id).no_such_method` was reported normally.
- **`Model.first` answers.** It inferred nothing while
  `Model.scope.first` answered, so the commoner idiom was the one that
  did not work. `last`, `take` and their `!` forms answer too. Given a
  count — `Model.first(3)` — they return an Array and this extension says
  nothing rather than the wrong thing.
- **A name written with its namespace is not answered by a class in
  another one.** `File.stat(path).` offered a workspace `Stat`'s members;
  it offers the real 167 now. `::JSON` means the top-level `JSON`.
- **A plugin's result crosses the process boundary as data, not as
  objects.** The parent used to rebuild whatever classes the stream
  named, before validating any of it — undoing the isolation the fork
  exists for. It now rebuilds typed values from fields it has checked,
  and nothing in a payload can name a class. No plugin needs a change.
- **One unreadable file no longer ends the session.** A file deep enough
  to exhaust the interpreter stack took the whole process with it, and so
  did any malformed message frame.

### Details

Every figure above is a measurement over the same corpus, taken one run
at a time. What remains is seven reports over those 213 files, and the
count is not the interesting part: what a report costs is decided by
whether the path is one people walk. Seven of the nine before this
release's last two fixes were in JRuby-only files that MRI never loads.

`docs/KNOWN_LIMITATIONS.md` gained ten sections in this release rather
than losing them. Three independent review rounds — reading the change
set, driving the product, and attacking its guarantees — measured a great
deal that was already wrong and is still wrong: a constant hovers as its
own name, `self.` completes to nothing, an instance variable set in a
`before_action` has a type in the view and none in the controller, and a
relation stops being a relation after `.where().where()`. None of it is
new, and it is written down now because a limitation nobody has stated is
worse than one everybody can read.

The largest single source of wrong reports that this release does *not*
fix: a project that reopens a core class. The Runtime Agent answers it by
reporting what your classes really respond to, and it cannot run in a
workspace you have not trusted. Trusting the folder is what makes those
go away.

## 0.2.5 — The foundations, and the answers that rested on them

- **A model's `scope` answers for the model it belongs to.** `scope :recent`
  on `Billing::Order` produced a relation named after the last part of that
  path, so wherever another namespace held an `Order`, completion after
  `Shipping::Order.recent.first.` listed the *other* model's methods and
  go-to-definition found nothing. Measured before fixing: 13.6% of class
  basenames in the gem corpus are shared by more than one namespace.
- **A nested core type keeps its namespace, so your class cannot take its
  place.** `File.stat(path)` answered as `Stat`, and a workspace class of
  that name captured it — offering its methods and denying the real ones.
  240 of the 334 types in the loaded RBS environment are nested, and 27 of
  their basenames are names ordinary code uses: `Error`, `Node`,
  `Generator`, `Buffer`, `Location`. One visible consequence: an aliased
  core class now shows its real path, so `Mutex.new` says `Thread::Mutex`.
- **Workspace Trust gates everything that executes, not just the Agent.**
  Trust was read once, at start-up, and not kept — so restarting the Agent,
  running observed tests with a caller-supplied command, and loading a
  plugin never asked. The shipped extension sends none of those from an
  untrusted window, but the LSP is a protocol any client can speak.
- **The cache is owner-only.** It holds method bodies from your own source,
  as `PRIVACY.md` says, and was created with the default mode — readable by
  every other account on a shared machine. Caches made by earlier versions
  are tightened too, including other projects': the sweep that already
  visits every project on launch does it, so you do not have to open each
  one to make it private.

### Details

The trust gate is one predicate that fails closed before `initialize` has
been handled at all, so a new entry point cannot be added without meeting
it. Six existing tests encoded the ungated contract; one of them asserted
that an untrusted restart should be acknowledged, which was the hole
itself.

`Marshal.load` on plugin output remains, and is recorded as `024.73`
rather than patched: the parent deserialises bytes the plugin produced,
which instantiates classes before any validation runs. The obvious fix —
JSON — does not fit, because declarations legitimately carry real type
objects and `Marshal` was chosen for that. The direction is to send plain
data and rebuild the objects in the parent from validated fields, which is
a protocol change. Loading a plugin is gated on trust meanwhile.

Two release-side gaps closed. The packaged artifact that actually ships
had never been inspected for build-machine paths — CI greps an
ubuntu-built VSIX, which is a different build entirely — and `release.sh`
does that now, refusing to publish on a hit. It also refuses to publish
when the Marketplace token file is readable beyond its owner, which it had
documented without checking since the token flow was written.

Nothing in this release adds a capability.

## 0.2.4 — An untrusted workspace could choose what the extension runs

**Security fix. Update if you ever open a repository you have not
trusted.**

- **Settings that name a binary or a command are now ignored from
  workspace scope until you trust the folder.** Opening a repository in
  Restricted Mode used to run a program of that repository's choosing,
  about two seconds after the window opened and before Workspace Trust
  was consulted at all. `ovallsp.rubyExecutablePath`,
  `ovallsp.ruby.command`, `ovallsp.server.path` and
  `ovallsp.observation.testCommand` are now declared restricted
  configuration, which is what makes VS Code withhold a workspace's value
  for them. User and machine settings are unaffected, and static analysis
  still works untrusted exactly as before.
- **`release.sh` refuses to publish when `.vsce-pat.local` is readable
  beyond its owner.** The file holds a Marketplace token and the script
  had documented `chmod 600` without ever checking it.

Nothing else an editor does changes, and no capability moves — the
manifest already promised this and the release makes it true.

## 0.2.3 — What the record says is what ships

Nothing an editor does changes in this release. It exists because three
published documents said things the shipped build does not do, and
because 0.2.1's rollback left debris behind it in the tree. Every
correction below was written from a measurement of the current build,
not from what an earlier document remembered.

- Fixed: the known-limitations entry for **a namespaced class named
  after a core class** (`Billing::Range`) claimed hover, go to
  definition and completion stopped answering in 0.2.1. They answer —
  the arrangement that broke them was rolled back before 0.2.1 ever
  shipped. What the shipped build actually does, and the entry now
  says: **mistakes on such a receiver are silently never reported**,
  and a literal of the same name completes to that class's members
  while hover answers from the core class — `(1..5).` offers
  `Billing::Range`'s methods (024.47).
- Fixed: 0.2.1's own notes carried **two bullets contradicting each
  other** about completion on a shadowed literal, under one heading, in
  both languages. The one claiming the completion half was fixed
  described a change that was reverted before release; it is removed,
  and the surviving bullet — completion behaves as 0.2.0's did — is the
  true one.
- Fixed: the site's front-page badge advertised **0.2.1** against a
  published 0.2.2. The check that compares the badge against the build
  ran only when a site file changed, so a version bump alone could
  never fire it; the badge is current again, and the check now runs on
  every pull request and every push to `main`.
- Fixed: an example in the Core test suite handed the cache a
  fabricated absolute path and assumed creating it would fail. **Run as
  root, it created directories at the filesystem root** and failed
  against correct code. The unusable directory is now constructed
  inside the example's own temporary directory, and is unusable for
  every uid.
- Fixed: this README and the site promised behaviour the build does
  not have — a refusal to run on a Ruby the bundled payload was not
  built for, and a hard stop on an Extension/Core version mismatch.
  What actually happens: the extension probes whether that Ruby can
  load `prism`/`rbs` itself and uses them when it can, and a version
  mismatch is reported and the session keeps running. The documents
  now say so; the README-promise defect is recorded as fixed (024.50),
  and the mismatch follow-through and a publish-after-close race are
  pinned as limitation entries (024.55, 024.56).
- Added, from the parallel 0.2.3 preparation (see Details): the guards
  it built that this tree verifies — the documented-example-count
  check **actually runs now** (its glob made it skip on every CI run
  to date), no two spec files may share a top-level constant, a
  publish-invariant property over the notifications a client really
  sends, hover/completion agreement on a template's `@ivar`, a
  fail-on-zero informational Ruby 4.0 CI job, and a roadmap⇔site
  parity check with the site's roadmap page brought current.

### Details

0.2.2 deferred three things to this release: the 0.2.1 documentation
cleanup, the register entries, and the hover/completion countermeasure.
The first two are this release. The third — making completion, hover
and diagnostics answer a shadowed name from one decision — was
evaluated concretely against this tree and declined for a patch: the
candidate design's recorded cost ("one spurious completion candidate on
a literal") turned out to understate an `argument-count` false-positive
family (`"hello".upcase(:ascii)` reported against a shadow class's own
`upcase()`), a hover popup mixing two classes' identities, the entire
core API arriving as completion noise on the written-name side, and a
corpus measurement that is structurally blind to all of it. The
evaluation and the re-scoping are recorded in 024.47 and
`docs/design/tasks/028-0.2.3-review-loop.md`; the register entry stays
open and the limitation stays documented, in both languages.

The rest of the cleanup: an unreferenced method and an inert
constructor parameter left by the rollback are gone, six comments
described the rolled-back arrangement as current — four are rewritten
against the shipped one and two went with the dead code they described
— and a deferral comment that named the wrong release (0.3.0 for
`activeParameter`; the roadmap says 0.4.0) is corrected.

**Two preparations, one release.** This 0.2.3 was prepared twice, in
parallel and unknowingly: once on the branch that shipped it, and once
on `fix/0.2.3` — the original, paused mid-loop by the incident 0.2.2
records and resumed after it. The two converged independently on
several of the same corrections, which is worth something as evidence;
where they overlapped, the version verified on this tree was kept, and
what the original's own record does not yet call demonstrated — its
engine work: a background cache sweep, `VendorBootstrap`, a handshake
rework — continues on that branch as **0.2.4**, with its register
entries. `docs/design/tasks/028-0.2.3-review-loop.md` carries the full
merge record, and the rule that prevents the double preparation (the
record on `main` names the branch the work lives on) is codified in
the working agreements.

## 0.2.2 — A test that deleted things, and the containment it needed

Nothing you can notice changes. This release exists because a defect in
this repository's own test suite destroyed files on the machine running
it, and the fix needs a version number to point at.

- **The published extension was never affected, and could not have
  been.** The defect lived in a test file, which the VSIX does not
  contain, and the single code path that tidies the cache derives every
  path it touches from the same cache root, so it cannot reach outside
  it.
- Changed: every deletion the cache performs now goes through one
  function that refuses a path outside the cache root. Until now each
  call site computed its own target, and staying inside the cache was a
  property of all of them being right at once rather than a property of
  deleting.
- Removed: an unused `clear` method that erased a directory handed to it
  by its caller, with every error suppressed. Nothing in the product
  called it.

### Details

**If you cloned this repository between 2026-08-05 and 2026-08-11 and
ran the Core test suite, it deleted directories outside the repository.**
`CONTRIBUTING.md` carries the disclosure, the affected commit range and
what to do about it. In short: an example passed a fabricated absolute
path to code that removes directories, the sweep resolved to the
filesystem root, and it removed all but the most recently modified
top-level entry. On macOS that meant `/Applications`, until a
SIP-protected path raised and stopped it.

The method under test swallows every error by design — a cache that
cannot be tidied is still a correct cache — so the example's
"does not raise" assertion was satisfied on every run while this
happened. An assertion that cannot fail is not a test, and that is the
first of the three rules this incident wrote into `CLAUDE.md`.

The fix is deliberately not a guard at the entry point. That would have
stopped this one caller and left the next one free to compute a target
some other way. Containment belongs to the deletion, so that is where it
now lives, and a check in `spec/meta/` pins that the cache continues to
delete in exactly one place — the containment cannot be pinned by an
ordinary example, because the surviving call sites cannot produce a path
outside the root for it to refuse.

## 0.2.1 — Fewer wrong reports, and the promises already published

Nothing new to learn here. This release is about the engine saying fewer
things that are not true, and about the places where the site, the README
and the capability tables promised something the build did not do.

- Fixed: a call whose receiver ends in `]` or `)` — `[widget].each`,
  `handlers[:on_save]&.call` — was reported as an unknown method. The
  receiver was looked up one character inside itself, so the lookup
  answered with the receiver's own last element. Over Ruby 3.4.7's
  standard library, five Rails 8.1.3 gems and minitest 6.0.6, **1,656 of
  3,747 unknown-method reports are gone**; four are new, and all four
  belong to a separately recorded case (024.13). On a real Rails
  application the two builds report identically. (This bullet said "1,556
  of 3,362" until the release's last day: that was measured four commits
  earlier and against a different minitest, and the figures moved when it
  was re-run. The removed set and the four introduced did not.)
- Fixed: `delegate`, `class_attribute`, `mattr_accessor`,
  `thread_mattr_accessor`, `concerning` and `deprecate` were reported as
  unknown methods in a model or controller body. The Runtime Agent read a
  class's own methods as `base.methods - Object.methods`, and `Object` is
  itself a class object — so everything `Module` defines was subtracted
  away. Five wrong reports on a scaffolded application; none now.
- Fixed: `"hello".upcase` is no longer reported as unknown when your
  workspace happens to contain a class whose last name segment is
  `String`. The engine stops asserting about a receiver it substituted;
  completion still offers that class's members, as it did in 0.2.0, and
  making all three readers agree is a design question rather than a patch
  (024.47).
- Fixed: a file that does not parse gets its syntax errors and nothing
  else. Typing `.` at the end of a method made `a.end` a call, and the
  engine reported that your class has no method named `end` — on the
  commonest editing action there is. The other half of this is not fixed:
  `a.` followed by a line like `b = "str"` parses cleanly as `a.b =` and
  is reported as such.
- Fixed: `Range` and `Regexp` literals have a type. `(1..10).` completed
  to nothing and hovering `/abc/` answered an empty popup, against a
  capability row promising a literal's type.
- Changed: typing `A` offers candidates. 0.2.0 needed two characters
  before workspace classes joined the list — which is exactly the example
  the site used. Measured before removing the floor: it bought 0.4 ms per
  keystroke. On a real application `A` goes from 2 candidates to 14, with
  the local still ahead of every class.
- Added: hover answers a call written with no receiver. `article_params`
  in your own controller showed an empty popup; go to definition and
  signature help were given that reading in 0.2.0 and hover was not.
- Fixed: **upgrading now actually delivers the fixes above.** The parse
  cache was keyed on your workspace, Ruby, Prism, `Gemfile.lock` and RBS
  — but not on OvalLSP's own version, and a cached entry is the output of
  a particular build's parser. Every file whose bytes had not changed
  kept answering with the previous release's results, including one
  wrong diagnostic that survived restarts and `Re-index Workspace` alike.
  Cache directories for keys no longer in use are also swept now, eight
  kept; nothing had ever removed one.
- Fixed: hover, go to definition and signature help no longer answer
  about a method for something that is not a call. Resting on a word
  inside a comment or a string, on a parameter name in a `def`, or on a
  local variable that shares a name with a method opened a popup with
  that method's signature, origin, a "Defined:" link and its doc comment.
  A local variable in scope is what Ruby resolves there, and that is what
  you now get.
- Fixed: signature help no longer disappears when an earlier argument
  contains an unpaired parenthesis inside a string or a comment —
  `raise ArgumentError, "bad )"` — and no longer answers with an inner
  call because of one.
- Fixed: `->() {}`, `!x`, `a && b` and `a || b` have a type. A default
  written `name || "anonymous"` is a String rather than nothing.
- Fixed: **a method whose name ends in `!` or `?` gets answers.** Hover,
  go to definition and signature help all stopped reading the name at the
  `!`, so `@article.destroy!` opened an empty popup, F12 said "No
  definition found", and typing `(` after it showed no parameters — on
  `save!`, `valid?`, `update!`, the names a Rails controller is mostly
  made of. Completion offered them the whole time.
- Fixed: signature help on a large file. Answering "there is no
  signature here" walked the file one character at a time, which on a few
  hundred KB with any non-ASCII character in it took seconds — and the
  Core answers one request at a time, so hover, completion and
  diagnostics waited behind it.
- Fixed: the signature popup no longer vanishes when the cursor is
  inside an argument that is still being written — `create(tags: [1, |2],`
  — and no longer answers with a call from an earlier line when there is
  no enclosing call at all.
- Fixed: no signature popup inside the parameter list of a `def` whose
  name ends in `!` or `?`, or a `def self.` — it was answering with the
  method being declared.
- Fixed: hover and go to definition work with the caret at the *end* of a
  `save!` or `valid?`, which is where it lands after you type the name.
- Fixed: a comment whose last word is `def` no longer silences signature
  help and completion on the identifier below it.
- Fixed: `1 || "b"` is an `Integer`. An instance is always truthy, so
  `||` never reaches its right-hand side.
- Fixed: clicking the first character of a negated name (`!ready`) no
  longer says "No definition found".
- Fixed: `items || []` is an `Array[Integer]`, not a union of that array
  with another array.

### Details

Six capability rows read PASS while their examples verified something
narrower than the row promised, and one row (`C7`) asked for a prefix
that could not match what it promised. All seven now say and test the
same thing.

`024.14` — recorded as "project-wide diagnostics produce nothing end to
end" — does not reproduce: on a real Rails application a file nobody
opened is answered 1.35 s from process start, 42 URIs published. The
capability row and example 0.2.0 shipped without now exist.

Three corpus measurements during this release produced confident false
results — a diff of a file still being written, a diff between runs over
different corpora, and a `cd` that persisted so both sides ran the same
build. Each is recorded, and the check that caught the last one was a
test, not a second reading of the numbers.

## 0.2.0 — Completion from the first keystroke, and diagnostics beyond the open file

**If you are on 0.1.13, this brings 0.1.14 and 0.1.15 with it.** Both were
tagged and never published, so their entries below describe changes that
reach you here for the first time. 0.1.14 removed about twelve thousand
wrong reports and introduced a handful of its own; 0.1.15 is those
corrections. Arriving together, the intermediate state never existed for
anyone.

- Added: typing `Ar` offers candidates. Completion needed a `.` first, so
  workspace classes, the locals in scope and the methods callable right
  there offered nothing until the whole name was written. Two characters,
  not one, in this release — 0.2.1 removed that floor.
- Added: mistakes in files you have not opened are reported. (0.2.0
  shipped this without a capability row, on a measurement that said an
  end-to-end example produced nothing; 0.2.1 found it working, added the
  row and the example, and marked the README row ✅.)
- Added: passing an argument of the wrong type is reported. Only the
  *number* of arguments was checked before.
- Added: reading an `@ivar` that is never assigned is reported. In an
  application `rails new` produces this stays silent, because the
  generated `ApplicationController` calls `allow_browser` and any
  class-body call the analysis does not model silences the check for
  every view beneath it (024.22).
- Added: hover and completion show the RDoc/YARD documentation, where a
  receiver was written — `widget.charge` and the list a `.` produces.
  Hovering the `def` itself, a receiverless call, or anything in an ERB
  template shows the type without the comment, and the bare-prefix
  completion added above carries no documentation.
- Changed: hovering inside a block whose receiver is not a container
  (`Array`, an Active Record `Relation`, a `CollectionProxy`) now answers
  nothing, where it used to answer with the enclosing call's type. That
  answer was frequently wrong — a string literal inside `opts.on("-x") do`
  read as an `OptionParser` — and 0.2.0's new checks would have published
  it as a diagnostic. Reading the block's body is the right answer and is
  blocked on an offset rule fixed separately (024.20).
- Added: semantic highlighting, in `.rb` and in an ERB template's Ruby
  regions.
- Fixed: `Widget.new` is offered. Completion asked RBS about the
  receiver's own name and nothing else, so a member declared by an
  ancestor was never in the list — and `new` is `Class`'s. A workspace
  class instance now also offers what every Ruby object has (`tap`,
  `frozen?`, `then`), after its own methods rather than before them.
- Fixed: signature help works on a call written without a receiver, the
  same shape as go to definition below.
- Fixed: go to definition works on a call written without a receiver —
  `article_params` inside the controller that defines it. That is how
  most Ruby calls a method of its own class, and it resolved to nothing:
  without a receiver the request fell through to a name lookup that only
  matches classes, modules and constants. Find references on the same
  pair always worked, which is what made it visible.
- Fixed: `@article.` completes in an ERB template. Hover on the same
  `@article` already answered `Article` — an ivar in a view gets its type
  from the controller action that assigned it, and only hover was passing
  that along, so completion and go-to-definition saw nothing.
- Fixed: a `*_path`/`*_url` call is no longer reported as a missing route
  when no routes have been loaded — an untrusted workspace, or any
  project that is not Rails. An empty route table used to answer "no such
  route" rather than "I do not know": 8 reports across Ruby's own
  standard library, every one of them an ordinary method. Project-wide
  diagnostics would otherwise have published each of them for every file
  rather than only for open ones (024.24).
- Fixed: an argument is no longer judged against a signature the call
  does not reach. `Invariants.initialize(cb, ocb)`, whose singleton
  `initialize` the workspace declares, was checked against RBS's
  `Class#initialize` — the single argument-type report Ruby's whole
  standard library produced, and it was wrong. A parameter written after
  an optional one (`def hold(a, b = 1, c)`) is also placed correctly now;
  it was read as the second argument's rather than the third's.

A minor release under the versioning rule in `docs/PUBLISHING.md`: six
capability rows are added (H7, C12, C13, G15, G16, T1 — documentation is
one feature and two rows, in hover and in completion). Six features ship
too, but not the same six: workspace-wide diagnostics has no row, because
the E2E example written for it did not pass and
`docs/EXTENSION_CAPABILITIES.md`'s own rule is that a capability with no
row is not a capability (024.14). It is in the list above with that
qualification rather than left unmentioned. It closes the last three roadmap entries scheduled
for it (024.R2, 024.R6, 024.R8).

### Details

Completion from a bare prefix is mostly a *ranking and bounding* problem,
which is a different problem from the one the receiver-based path solves.
A receiver narrows the answer to one type's members; a bare prefix matches
far more, and an editor handed a thousand alphabetically-sorted candidates
is worse than one handed none — the right answer is on page four and the
user learns to stop pressing the key. The order is closeness to the
cursor: locals, then methods on self, then workspace constants, then
Kernel, rendered into `sortText` because that is what the editor actually
sorts by. A one-character prefix returns only the first two: the other two
match essentially everything at that length. The list is capped and says
`isIncomplete`, so the editor re-asks as the prefix narrows.

Workspace-wide diagnostics run on a background thread, never for a file
open in a buffer (those belong to the path that knows the buffer's version
and unsaved text), and abandon a superseded pass between files rather than
finishing one already known to be stale. They are re-run whenever the
answers change workspace-wide — most importantly when the Runtime Agent
becomes ready, since the unknown-method check defers rather than guesses
without one, and until now every unopened file kept the pre-Agent answer.

The two new checks are held to the standard the argument-count check was
held to: a wrong report on code that runs is worse than no check at all.
Argument types are only compared where the expected type is *stated* — an
RBS/RBI declaration with exactly one overload and no `*rest` — and only
when both it and the argument's inferred type are concrete classes with no
ancestor relation. RBS's `int`/`string`/`boolish` are excluded: they mean
"anything that converts", not a class. The `@ivar` check is scoped to
views, which are handed exactly what their controller action and callback
chain assign; its whole safety is the distinction between "no context
could be established" and "the action assigns nothing", and the first of
those is silent.

Semantic highlighting reports only what a parser settles and a regex
cannot — a local variable read against a receiverless call, an instance
variable, a parameter, a constant. It does not re-colour keywords, strings
or numbers, which the grammar already gets right and which a second,
disagreeing opinion would only make flicker. A file that does not parse
reports nothing rather than half a file, so highlighting does not fall off
as you type.

Documentation is read from the source, where it already lives; nothing
indexes comments. Completion goes through `completionItem/resolve` rather
than putting documentation on the list, since reading the source for every
candidate is a file read per item for documentation the user sees for one
of them at most.

## 0.1.15 — the class-body fix, corrected

0.1.14 removed about twelve thousand wrong reports and introduced a
handful of its own. This is those, found by two independent reviews of
the released code and fixed with the same measurement discipline.

- Fixed: a method the workspace adds to `Object` or `Module` — a
  `core_ext` file, which is idiomatic in Rails — is no longer reported as
  unknown when called in a class body. 0.1.14 added `Class`/`Module`/
  `Object` to a class's ancestry and then looked them up for *singleton*
  methods; a class object is an **instance** of them, so their instance
  methods are what a class-level call reaches. The same error silenced a
  real one: `def self.x` added to `Class` is not something an ordinary
  class inherits, and Ruby raises `NameError` for it.
- Fixed: the ancestry tail says what the *receiver* is, not what its
  last ancestor happens to be. A class whose ancestors end at a module got
  the module tail, without `Class` — `ActionController::TestRequest`
  really does, because its chain terminates at a module named `Request`.
  Released 0.1.14 did not report `new` on it, because it carried a special
  case skipping every `new`; deleting that special case is what made the
  wrong tail observable, and both are fixed here.
- Fixed: `define_method` inside `class << self` no longer reports its
  body's calls. That block defines a singleton method, so its `self` is
  still the class.
- Fixed: `instance_eval do … end` no longer reports on either side of
  its own rule. `instance_eval` sets `self` to its receiver: written
  without one in a class body, that is the class, and 0.1.14 reported the
  `attr_accessor` such a block contains; written on an object, that is an
  instance, and reading the block as class-level reported the instance
  methods it calls.
- Fixed: `private attr_reader :x` is private. It was recorded public, so
  a private method appeared in completion on an outside receiver.
- Fixed: renaming a method that a macro declared is refused instead of
  producing a `WorkspaceEdit` that rewrites every call site and leaves
  `attr_accessor :name` behind — an edit that does not run. The editor
  shows its own "cannot be renamed" message; the reason goes to the Core
  log, not to a notification. This
  hole pre-existed for `enum`, `scope` and `delegate`; 0.1.14 extended it
  to ordinary Ruby. `prepareRename`'s own comment always said generated
  symbols were refused; now they are.
- Fixed: a method `delegate` or `scope` generated takes what it
  forwards, not nothing. Both recorded no parameters at all, so the
  argument-count check judged every call to them —
  `within_new_transaction(isolation: x)` in ActiveRecord's own
  `database_statements.rb`, and calls to `delegate`d predicates in devise
  and solid_queue. Over ActiveRecord, ActiveSupport, ActionPack,
  ActionView and ActiveModel together this takes `argument-count` from
  **134 to 11** with nothing introduced.
- Fixed: a brace-less trailing hash is counted as the positional
  argument Ruby binds it to, when the method declares no keywords.
  `add_tests "a", "K" => 1` against `def add_tests(name, hash)` was
  reported as passing one argument. The miscount predates 0.1.14; what
  0.1.14 changed is that a receiverless call in a class body resolves, so
  it reached this check for the first time — **526 such reports in
  brakeman and its vendored gems alone**, 528 → 2.
- Fixed: an argument-count report is no longer produced against a method
  found only through the `Class`/`Module`/`Object`/`Kernel` ancestry this
  release models. That ancestry is there so class-level calls *resolve*;
  using it to produce reports is the aggressive direction, and it is where
  a `module_function` or a `define_method` this engine does not model can
  shadow the method it found. Ruby's own `::JSON.load(source, proc, opts)`
  was reported that way.
- Performance: completion is faster than it has ever been, not merely
  recovered. 0.1.14 grew the singleton chain from one entry to six, and
  each entry cost a full scan of the symbol table. On a 21.7k-symbol
  workspace, a constant receiver went **12.97 ms → 0.099 ms**; on a
  22k-symbol one an independent measurement put it at 3.18 ms (0.1.13) →
  21.3 ms (0.1.14) → 0.013 ms here, with instance-receiver completion
  13.1 → 13.9 → 0.103 ms. Absolutes differ with the workspace; the
  direction and the order of magnitude do not.

A patch release under the versioning rule in `docs/PUBLISHING.md`: no
capability is added.

### Details

Two rules were written out at more than one call site and wrong in every
copy. Which declaration kind an ancestor contributes now lives in
`AncestorEntry#declaration_kind`, and the tail is appended once, at the
entry point, from the receiver's own kind — not inside the recursion,
where whatever the walk happened to end at decided it.

0.1.14 introduced six things, not five: the sixth is the arity miscount
above, which no corpus this release measured had exposed until a later
round chose brakeman's vendored gems. The lesson is recorded with the
rest — a corpus nobody has run is worth more than re-running one that has.

Measured with `scripts/corpus_diagnostics.rb`, each revision pointed at
the same corpus. Over Ruby 3.4.7's standard library, `unknown-method`
findings: 0.1.13 **15,982**, 0.1.14 **3,848**, this release **3,847** —
and **not one report is introduced** anywhere in it, against either.
`argument-count` falls 13 → 11 there, and eight surviving reports change
their wording (`but 2 given` → `but 3 given`) because the hash is counted
now; those eight are a different, recorded defect (024.32) and are wrong
for that reason, not this one. Over
ActiveSupport 8.1.3, 0.1.14 **265** → **240**. Over this repository's own
`core/lib`, 0.1.13 **60** → **4**.

Two things were written during this release and then cut from it, because
a release that exists to remove wrong reports should not add scope that
produces them. `module_function` modelling changed nothing measurable —
over the 47 standard-library files that actually use it, this release and
0.1.14 produce byte-identical output — while introducing a report neither
0.1.13 nor 0.1.14 made. Hover and completion polish for writer methods
shipped a regression that broke go-to-definition after any comment ending
in a period. Both are recorded in `024-deferred-review-findings.md` with
that measurement, so whichever release takes them up has to justify them
on a corpus rather than on plausibility.

That last pair corrects the 0.1.14 entry below, which quoted "62 → 4" and
"776 → 265": both "before" figures came from a different tree than the one
that release shipped. The stdlib figures it quoted reproduce exactly.

The capability suite could not have caught the rename regression: nothing
in the real-Rails fixture used `attr_*` at all, so a green run said
nothing about it. The macro-declared shape is now its own row, **W4**,
with its own example — not a second `W2`, because
`capability_coverage_spec` compares ids as set differences and a
duplicate would have made the row and the example cancel out.

`scripts/corpus_diagnostics.rb` is in the tree as of this release. The
0.1.14 entry cites it for numbers a reader could not reproduce, because
it was only added on the unreleased 0.2.0 branch.

## 0.1.14 — `private` is not an unknown method

- Fixed: `private`, `protected`, `public`, `attr_reader`, `attr_writer`,
  `attr_accessor`, `private_constant`, `alias_method`, `module_function`,
  `define_method`, `include` and `extend` are no longer reported as
  unknown methods when written in a class body. They are `Module`'s
  methods, and a class body's implicit receiver is the class.
- Fixed: methods that `attr_reader`, `attr_writer` and `attr_accessor`
  define are no longer reported as unknown. They were never recorded as
  declarations, so on a class whose ancestry is fully known every
  attribute reader read as missing.

A patch release under the versioning rule in `docs/PUBLISHING.md`: no
capability is added. It removes wrong reports from a capability that
already claimed to work.

### Details

Two separate things were missing, and either alone still produced the
report.

`HierarchyIndex#ancestors(singleton: true)` walked the superclass chain
and stopped. It never appended what a class object *is* — a `Class`,
which is a `Module`, which is an `Object` — so `Module#private` was not
in the chain to be found. The instance side has had its
`Object, Kernel, BasicObject` tail all along; the singleton side had
none. A module's tail is the same list without `Class`, which is why
`superclass` answers on a class and not on a module. An unresolvable
parent (`class Widget < Struct.new(:a)`) still gets no tail: claiming
the chain ends in `Class` would say it is fully accounted for when its
middle is not.

The second was in the parser. One flag answered two questions —
"would an unqualified `def` here declare a singleton method", true only
inside `class << self`, and "is `self` here a Class/Module object", which
is also true directly in a class body and inside a `def self.x`. A
receiverless call took the first answer, so `private` in a class body was
resolved against the *instance* chain, where it does not exist. The two
questions are now tracked separately.

`attr_reader :name` declares `name` as surely as `def name` does, and the
index recorded only the call. That was masked while class bodies were
mis-modelled, and reading a `define_method` body correctly surfaced it on
Thor's `attr_accessor :options` — so closing it is part of this release
rather than a note in it: a fix must not hand anyone a report they did
not have before. A dynamic argument (`attr_reader(*names)`) still records
nothing; guessing there would declare a method that may not exist and
silence a real report. Inside `class << self` these declare singleton
methods, and the open visibility section applies to them as it does to a
`def`.

Measured with `scripts/corpus_diagnostics.rb`. Over this repository's own
`core/lib`, `unknown-method` findings drop from **60 to 4**; over
ActiveSupport 8.1.3, from **785 to 265**. (Both "before" figures were
wrong when this entry shipped — they came from a different tree; corrected
in 0.1.15, which re-measured each revision against one fixed corpus.) Over Ruby 3.4.7's whole
standard library, from **15,982 to 3,848** — and **not one report is
introduced anywhere in it**, which is the number that matters, since the
purpose is to stop saying something untrue. Wrong `argument-count`
reports fall 36 → 13 and wrong `unknown-route-helper` reports 48 → 8 as a
consequence: a name that now resolves to a declaration is no longer
guessed at.

What remains of those counts is a different gap, tracked separately: the
argument-type fallback recorded as 024.19, and the route-helper check
answering "no such route" from an empty route table (024.24), which this
release reduces but does not fix.

The engine had one name of this list special-cased already: `new`, whose
comment named Class/Module as the chain nobody modelled. That special
case is now redundant and the names are Ruby's, not a list this project
has to keep.

## 0.1.13 — the index answers the workspace, not your editing history

- Fixed: go-to-definition, find references, rename, signature help and
  `workspace/symbol` no longer change their answer depending on which
  file you edited last. A class declared in more than one file — a
  reopened model, a controller split across concerns, two spellings of
  one namespace — had its declarations reordered every time any of those
  files was re-indexed, and each of those features takes the first one,
  or truncates the list.

A patch release under the versioning rule in `docs/PUBLISHING.md`: no
capability is added.

### Details

`WorkspaceIndex` removes a uri's entries and appends the new ones on
re-index, so a file's declarations moved to the back of every list they
were in. Typing one character in an unrelated file was enough: a bare
`User` resolved to `Admin::User` and then to `Api::User`, taking the
ancestry chain and the unknown-method check with it; the class in the
file you were looking at dropped out of a truncated `workspace/symbol`
result; signature help showed a reopened method's parameters from the
other definition. At least eleven readers, all taking `.first` of a
collection whose storage had no order, or truncating it — "at least" because the list was
miscounted twice and then grew again under review, which is the argument
for fixing the storage rather than the readers.

0.1.12 tried to fix this four times, each round sorting one more reader,
and produced two regressions before the whole thread was rolled back and
recorded as `024.15`. The order lives in the storage now: entry lists are
ordered by uri and then source position when they are written, and the
one place a query reads the simple-name index orders it by qualified
name, kind and owner — one class has as many entries there as there are
ways to spell it, and those share a name.
`workspace/symbol`'s ranking keeps its exact-match-first rule and gains a
tail, because its result is truncated and a tie decided by index order
changes which symbols survive.

Every example that could regress on re-index re-indexes — that is the
state the bug lives in, and the state all four earlier attempts were
pinned without. It is not sufficient on its own: the `workspace/symbol`
tail shipped unpinned behind a re-indexing fixture whose eight files all
declared one class, so the entry list `replace_file` already sorts was
the only thing it exercised. Ties across *distinct* symbols are what that
part is for, and they need their own fixture. Three more fixtures were
found the same way afterwards: one that ordered its files and its line
numbers alike, so either half of the key satisfied it; one that used a
single name in two files, which is a single symbol, so it never walked
the collection it was written for; and one that re-indexed the
first-inserted file, which lands on the right answer by accident.

Two testing gaps found alongside it, neither user-visible:

The capability E2E suite could skip every one of its 41 examples --
covering all 42 rows, one of which is a pair -- and still exit 0.
`docs/EXTENSION_CAPABILITIES.md` says "a capability whose row is skipped
is not shipped"; CI enforced that for the real-Rails integration suite
only, and `capability_coverage_spec.rb` cannot see it because it reads
the spec file's source text rather than its results. Both suites are
checked now.

And `extension.ts` — the extension's largest module — was covered only by
an integration suite that runs in no workflow. Two decisions a user
notices moved out of it into a module that imports no `vscode`: which
files the client attaches to (Ruby by language id, ERB by extension,
because VS Code assigns `.erb` no built-in id), and what the status bar
says — including the difference between "no client here", which hides,
and "the client did not answer", which must not.

## 0.1.12 — The rule that kept being rewritten, and a privacy list that under-described itself

Every fix here repairs something OvalLSP already claimed to do. Most of
them are the same defect wearing different clothes: one rule about class
names, written out by hand wherever it was needed.

**Privacy and the parse cache** — corrections to what the documents said,
not to what the code does:

- **`PRIVACY.md` no longer says the parse cache holds "not your source
  code's contents". It holds parts of it** — each method's body text and
  each parameter's default expression, verbatim, plus each file's
  absolute path. The cache has always stored these; the document was
  wrong about it, in every version through 0.1.11.
- `PRIVACY.md` no longer says nothing is written to disk beyond the parse
  cache. An observation run writes two temporary files, one of which
  receives your own test command's output — routinely SQL, in a Rails app.
- `PRIVACY.md` now lists everything type observation records, and stops
  listing one thing it does not. It recorded more than it said (the
  classes seen at each parameter, the classes returned, a file digest and
  line, a run identifier, a finish time) and claimed to record whether a
  call raised, which nothing does.
- The parse cache lives under `$XDG_CACHE_HOME/ovallsp/`, not always
  `~/.cache/ovallsp/`. The troubleshooting step that says to delete it was
  wrong for anyone with that variable set to a non-empty value.

**False reports removed** — code that runs, reported as broken:

- `send`, `__send__`, `public_send`, `instance_exec`, `Proc#call` and
  `Method#call` are no longer reported as unknown methods. The first four
  and the last two failed for the same reason through two different code
  paths.
- A class written `< ::BasicObject` no longer has its unknown-method
  check silently switched off. As in 0.1.11, a class that was silent may
  now start reporting mistakes it was quietly ignoring.

**Types that were wrong or missing:**

- `::User.find(1)` resolves to `User`, as `User.find(1)` already did. A
  root-scoped model receiver lost its type, and the Active Record method
  check went quiet for it.
- `self` and `Widget.new` now have the same type inside `Widget`. They did
  not, so a variable assigned from both became a union and the
  unknown-method check went quiet for it — as it did for `::Widget.new`.
- A namespaced class no longer borrows a same-named top-level model's
  data. `Admin::User#name`, delegated to `:company`, was answered from the
  top-level `User`'s associations — a confident wrong type, not a missing
  one.
- A plugin registering a class declaration could make an unqualified name
  resolve to the wrong class.
- One `klass::Error.new` no longer costs a whole method its instance
  variable types. A constant path with a non-constant segment is legal
  Ruby and common in factory code; asking Prism for its name raised, and
  the raise was caught far enough away that the method's entire
  inference was discarded — so a view got no types at all.

**Signature help:**

- No longer shows `()` for a method that accepts arguments it does not
  name. `Array#shuffle` read as taking nothing; so did 106 methods that
  accept `*rest` or `**rest`, including `Array#push` and `#concat`.
- No longer tells you to type `x:` for a method declared in a Sorbet
  `.rbi` that takes plain positional arguments.
- A Sorbet `.rbi` declaring `def f(...)`, `def f(**nil)` or a destructured
  `def f(a, (b, c))` keeps its signature. Introduced and fixed inside this
  release; no published version shipped it.

**Go-to-definition:**

- Go-to-definition on an Active Record column or association reaches
  models written `module Admin; class Company`, not only those written
  `class Admin::Company`.

A patch release under the versioning rule in `docs/PUBLISHING.md`: no
capability is added.

### Details

**One rule, written out at every call site that needed it.** 0.1.11 moved
"a class or owner name is qualified" into `SymbolId` and routed its
callers through it. Copies survived, and this release spent eleven rounds
finding them. It also published a count of them five times and was wrong
every time, always low — which is the finding. There is no count here;
`git diff main...HEAD -- core/lib` shows the removed sites, and how many
there are depends on whether you count `entry.name == "BasicObject"` and
`split("::").last` as the same rule, which is exactly the ambiguity that
kept producing a different number. `chain_reaches_root?` asked `entry.name == "BasicObject"`, and a
class written `< ::BasicObject` produces an entry carrying the `::`, so
its chain was judged not to reach the root, the receiver was not
"closed", and the unknown-method check switched off for that class
without saying so. `ModelRegistry` is keyed by Rails' bare `model.name`,
so `::User` matched nothing — normalised now in its four lookup methods
rather than at the twenty-two call sites, across five subsystems, that
use them. `MethodAnalyzer` matched a delegate's owner by *simple* name,
so `Admin::User` borrowed the top-level `User`'s associations.
`LocalInferencer` built `::`-prefixed types in six places. (An earlier
revision of this paragraph said one of them was user-visible, citing a
hover difference on `k = ::Widget`. That was wrong: 0.1.11 already
normalised that site, and the difference existed only under a mutation.
It was untested, not broken.) The seventh site in that file
asked Prism for a constant path's name without the guard its two
neighbours already had, so `klass::Error.new` raised and took the whole
method's instance variables with it; all of them now go through one
helper that answers nil rather than raising.

`Index::SymbolId` now owns all three directions of that one decision —
`qualify_owner`, `bare_name` and `qualify_within` — and every copy
delegates to it, including
`ReceiverResolution.canonical_receiver_name`, whose old body was one of
the two byte-identical to what it now calls. The type also enforces the
invariant it had only documented: a class's own name is qualified, which
until now was true because `ParserService` happened to produce it that
way, and not true of a declaration registered by a plugin.

**RBS and RBI signatures.** RBS writes "takes anything" as `(?)` and
models it as a function object carrying no parameter lists at all. Two
different declarations run into it: `Proc#call` and `Method#call` are
`(?)` themselves, while `send`, `__send__`, `public_send` and
`instance_exec` carry a `(?)` *block* — spelled `?{ (?) -> untyped }` for
the first three, and `{ (?) [self: self] -> U }` for `instance_exec`,
whose block is required and self-bound. Both converters asked such a
function for its positional parameters, the error was swallowed by the
blanket rescue around signature building, and the method came back as "no
signature" — which the unknown-method check reads as "RBS does not
declare this". `__send__` is core idiom in exactly the proxy and delegator
code people write `< BasicObject` for, so the `::BasicObject` fix above
would have turned a false report on precisely the classes it un-silenced.

The label those signatures produce was asserting zero arity for anything
it could not name: 29 methods in the RBS core this loads have keywords and
no *named* positionals (33 counting each overload), and 106 name nothing
at all but accept a rest slot. Both now render. Three of the 29 also take
a `*rest` *positional* — `Dir.[]`, `Kernel#warn`, `Ractor.new` — which is
the whole difference between 29 and the 26 an earlier revision gave; a
fourth, `Exception#detailed_message`, has a `**` rest and so is not among
them. 135 methods in all rendered as `()` while accepting arguments.

The RBI defect is the one this release caused. Sorbet's
`params(x: Integer)` is a name-to-type map; it describes `def f(x)` and
`def f(x:)` identically, and the parser filed every entry as a required
*keyword*, with a comment saying this was only "for arity matching
purposes". Nothing rendered keywords, so nothing showed — until this
release taught the label to render them, and `def combine(x, y)` began
telling the user to type `x:`. The label was not the bug; it made an
existing lie legible. The `def` under the sig is the authority on
parameter shape and the parser always had that node, so shape now comes
from the def and type from `params(...)`. That first attempt then raised
on three legal parameter forms — `def f(...)`, `def f(**nil)`, and a
destructured `def f(a, (b, c))` all put a node in the list answering no
`#name` — and the blanket rescue turned each raise into a dropped
signature. Fixed within the release; no published version shipped it.

**What the privacy documents got wrong.** Three claims, all older than
this release. The parse cache does hold parts of your source code. Two
temporary files are written during an observation run, one of them
receiving your suite's own output. And the list of what observation
records was wrong in both directions at once — short by five fields, and
claiming a field that does not exist. None of this changed what the code
does; the guarantee that no *value* from your program is recorded held
throughout, and still does. What changed is that the document now
describes it accurately, and says plainly that the "never records"
promise is about what OvalLSP extracts and keeps, not about what your own
test suite prints.

**What eleven rounds of review cost this document.** Most of the numbers
these notes published were wrong at least once and had to be re-derived:
two suite counts, a mutation count, and the count of the copies described
above three separate times. There is no total here, because a total would
be one more number nobody could check. Two release titles made
completeness claims that the next round falsified. The strongest correction in the release — the parse cache
holding source — went unmentioned in any bullet through ten rounds, in a
document eleven reviewers had each read. And one thread was rolled back
rather than shipped: four rounds spent on the index returning results in
whichever order files were last edited, each attempt sorting one more
reader of a collection whose storage has no order. Round 10 regressed
round 9's fix in the same method. That defect predates this release and
now has an entry of its own (024.15) naming the fix it actually needs,
which is to order the storage rather than each reader. The notes above
have been re-derived from the code rather than from earlier drafts of
themselves; where a number appears, it was counted.

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
