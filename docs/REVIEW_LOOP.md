# Review loop

How a change set is reviewed until it ships. `AGENTS.md`'s "Review loop"
lines point here.

## Cadence

**A round closes when a reviewer that has not seen this change set, using
a method the previous round did not use, reports nothing.** Method is one
of:

- `diff` — read the change set;
- `drive` — run the product and compare answers;
- `attack` — take one guarantee and try to break it;
- `reproduce` — re-derive the round's own claims.

Each round records which it used, in the release's task document. A
closing round whose method repeats the previous round's closes nothing.

**Two of those are mechanical, and are a command:**

    ruby scripts/review_round.rb start <method>
    ruby scripts/review_round.rb status
    ruby scripts/review_round.rb close

`start` refuses a method the list above does not name, refuses the method
the previous round used — read from the task document, where it was
written and nothing read it — refuses a tree that is not clean, and
refuses while a round is already open. It then records the index the
round reads, and writes the round's heading and an empty findings table
into the highest-numbered task document on the branch. `close` refuses
when the index moved under the round, because a round that read two
trees can conclude about neither.

What it cannot see is an edit nobody staged — the round's own heading is
one — so a clean `close` says nothing was *committed* under the round,
not that nobody typed. The rules are the two paragraphs around it; the
command is only the part of them a person had been holding in their
head.

**After three rounds that find defects, ship with the open findings
recorded** — each in `docs/ISSUES.md`'s intake, in the register once it
has been driven, and a `KNOWN_LIMITATIONS` paragraph for any a user can
meet. Section 0.4: letting 1.0.0 recede in pursuit of
accuracy is worse than the defects being pursued, and an unbounded loop
has no other outcome. The bound of three is this project's operational
choice, not a maintainer ruling. Departing from it is written down where
the release is recorded.

**During a loop, fix; do not add.** A capability a reviewer asks for is a
finding to record. A round reviews a fixed thing, and every addition
between rounds resets it.

*Why this and not "repeat until clean":* `028` declares merge round 8
clean, and the next entry is an external reviewer finding two defects.
Around sixty rounds are recorded across 0.2.x.

## The same place twice: mechanise, then roll back

A finding about the previous round's changes is the loop working. What
matters is the **same place** found in two consecutive rounds, so track,
per round, which code each finding is about.

- **The first time**, put in a mechanical countermeasure — something that
  makes the class of defect fail a check rather than wait for a reviewer:
  two scanners that had to agree about one text, replaced by one both
  read; a table two readers diverged on, replaced by one both read; a
  guard given the input it could not see. A regression test for the one
  instance is *not* a countermeasure.
- **The second time**, the countermeasure was aimed at the symptom too.
  Stop the loop, roll back the whole thread of changes those rounds
  produced, write the root cause and the direction actually needed as a
  register entry, and re-scope the problem to its own release or task.
  The entry is the deliverable.

`024.15`: four rounds each bolted a sort onto one more reader of a
collection whose storage had no order — zero net progress, and a release
larger than the three before it combined. Two corollaries: do not tell a
reviewer to assume the previous round broke something, because that
manufactures the self-referential findings this rule detects; and
centralising a rule into a constructor is not free (`024.47`).

## Asking for an independent review

A review is worth what the reviewer is allowed to find. Do not narrow
what counts:

- not *"re-finding a recorded defect is not a finding"* — the exclusion
  list grows while the count is read as convergence;
- not *"concentrate on X"* — X is where the last round looked, not where
  the next defect is;
- not *"a clean report is the expected outcome"* — say what a defect is,
  never what the answer should look like.

Tell a reviewer what has been measured and at which revision; that is
coverage, never an exclusion. A corpus is measured against a revision,
not for ever.

Before believing a falling count, run one round neutral: the same tree,
round-one instructions, plus *report anything you consider a defect,
whether or not it looks already known or deliberate; if a decision
recorded as deliberate is the wrong decision, say so.* A falling count
cannot distinguish "fewer defects remain" from "fewer can be reported";
read it against user impact instead. `024.36` is the control run that
established this.

## What a round leaves behind

- **Findings go into the task document as the round produces them** — a
  table of number, what it was, disposition — not after the fixes land.
  `review_round.rb start` writes that table's header, empty, so the place
  to put them exists before the first one arrives. Findings that lived
  only in a message were lost before they were written down (`024.109`).
- **Anything the release does not fix** goes to `docs/ISSUES.md`'s
  intake, then to the register, by that document's rule.
- **Promoting a finding** — splitting an entry, giving it a target,
  marking it user-visible, writing its `KNOWN_LIMITATIONS` paragraph —
  restates it in the present tense with more authority. Run its
  reproduction against the tree you are promoting it into (`024.130`,
  `024.131`).
