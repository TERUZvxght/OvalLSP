# 050 — where 0.2.16 stands, and what is staged but not applied

Written to stop, not to finish. Rate limits made continuing the wrong
call, so this records the state precisely enough that the next session
does not re-derive it.

## What shipped into the branch

Seventeen commits on `feat/0.2.14`, which carries the 0.2.16 work.

**The backlog was driven rather than read.** All 111 open entries
targeting 0.2.16 were reproduced against the tree, each with a control in
the same fixture: 94 reproduce exactly as written, 13 differently, 4 were
reported already fixed — and two of those four were overturned by an
adversarial verifier, which is why the pass had one. Zero controls failed
to hold. Unlike `024.91`, whose four shapes turned out to be two, this
backlog was live.

**Five user-visible defects fixed**, each through two review rounds:

| entry | what changed |
|---|---|
| `024.239` | `trap`, `set_trace_func`, `iterator?` stopped being reported missing. Corpus 18 → 16 |
| `024.27` / `024.28` | every macro-declared name gets its own token; Find References had been answering about the *first* name in `attr_accessor :a, :b` from the second |
| `024.85` | `self.` completes. Measured to move no diagnostic at all |
| `024.137` | `#search` stopped holding the index lock for a full scan; a two-character query 10.4ms → 4.0ms |
| `024.43` | a receiverless stdlib call answers signature help: 3,046 answers gained, 0 lost |

**Two countermeasures**, both triggered by the same-place rule rather
than scheduled. `024.220` re-runs every interpreter session in tracked
content (89 of them, 65 with a recorded answer) as preflight's ninth
check. `024.195` removed every prose statement of what preflight runs,
because adding a ninth check made four of them disagree.

**Thirty-nine internal entries** across six clusters — the doc-link
checker, the home-path scanner, the measured-claim scanner, the register
grammar, the release gates, and the pinned-mutation and SBOM records.

**`049`**, the DTSTTCPW audit, with the three live defects it turned up.

## What is staged and not applied

Two patches exist, were verified by a second agent, and were told
**do not apply**. Both defects are real and reproduced.

### `core-internals` — patch at `scratchpad/w2/core-internals.patch`

Closes 024.38, 024.74, 024.102, 024.135, 024.138.

- **[blocking] 024.38** — The `locate_in_statements` change is not answer-preserving: when the walk aborts (step budget exhausted, or any `StandardError` inside `eval_type`), `scope_at` now answers with **zero locals** where it previously answered with everything accumulated so far. The register section published with this change claims the opposite — "only the last pre-cursor statement's snapshot is ever read", "every earlier one is overwritten before anything can look at it", and "byte-identical" — and the first two are false because `scope_at`'s own `rescue BudgetExceeded, StandardError` is a reader of an earlier ca

- **[worth-fixing] 024.135** — `core/lib/ovallsp/observation/wire.rb` is a wholly new file whose validation decisions are largely unpinned, against a report that states "Every behavioural line is pinned and every pin was watched red before it went green. Nothing here is asserted from reading." This is the blind spot CLAUDE.md's test-first section names explicitly — reverse-applying a hunk that adds a whole file only tests that the file exists — and the file in question is the security boundary the entry is about.

### `misc-scripts` — patch at `scratchpad/w2/misc-scripts.patch`

Closes 024.156, 024.157, 024.168, 024.176, 024.191, 024.192, 024.193, 024.198, 024.204, 024.208, 024.209, 024.215, 024.217, 024.220, 024.225.

- **[blocking] 024.220** — 024.220 is already fixed and released at the stated base 8d39437, by a different, more capable implementation. This change set adds a second one, and resolving the merge toward it replaces a bounded checker with an unbounded one.

- **[worth-fixing] 024.215** — The prose claim "the original wording is not recoverable from any commit" is false, and the reconstruction written in its place discards a specific recoverable fact for a generic sentence. The claim appears twice - at the site and in the register entry that is now marked fixed.

- **[worth-fixing] 024.220** — The new checker runs pasted programs with no timeout, so a non-terminating session wedges the suite and the `preflight --install` pre-commit hook indefinitely with no output.

- **[worth-fixing] 024.157 / 024.204** — The new "spawns no git subprocess that has not had its repository scrubbed" guard misses the two most ordinary Ruby spawn shapes, so the containment it advertises can be reintroduced by ordinary-looking code.

- **[worth-fixing] 024.156** — The CI-job citation is recognised by its surrounding prose form, so rewording one row silently removes the citation and that gate becomes unchecked again - the per-kind floor cannot see it because the other rows still supply a ci_job citation.

### `024.178`'s fifth place

`doc-link-checker` is merged, but its verifier found a fifth tracked
place still asserting the false quantifier — in `046`, the document the
entry's own Area names. `046:205-207` says the A0 census was "every one
in a source comment"; re-run, the nineteenth is a Markdown file. That is
`046`'s own narrative rather than a historical round note, so it is a
correction rather than a rewrite.

## Wave 3, designed and deliberately not run

`049` found three live user-visible defects while building
simplifications, none of them reported by any review round, each
invisible because a duplicate path looked like the working one. They are
filed, published in both languages, and **not fixed**:

- `024.240` — in a view, hover answers `null` where completion offers the
  method and go to definition opens it, at the identical position.
- `024.241` — Find References answers a method's call sites from a word
  inside a comment, from a bare `42`, and from `end`, while rename at the
  same positions correctly declines.
- `024.242` — `Zoo.pick(1)` and `k = Zoo; k.pick(1)` are the same call
  and the second loses a declared overload.

`049` also holds eleven measured substitutions that are **not** for this
release: every one is a retrospective simplification of working code, and
`CLAUDE.md`'s DTSTTCPW rule gives those an ordinary change's obligations.
Eleven in one release is the blast radius 0.2.1 lost a release to.

## Two things about the method, for whoever runs the next batch

**The agent worktrees were not branched from the commit the brief named.**
They came from `bdd0ebe` while the brief said `8d39437`. One agent
noticed and diffed against its real base; the rest did not, and one
consequence is in the list above — `misc-scripts` re-implemented
`024.220`, which had landed at `8d39437` but not at `bdd0ebe`, and its
version has no timeout. Check the base before trusting a patch.

**Do not hand a patch back as text.** Two patches in the first batch were
corrupted in transit and one would not apply even at its own base commit.
The second batch wrote patches to files and returned paths; none was
corrupted.

## Before this release can be cut

`ruby scripts/deferred_findings.rb --targeting 0.2.16` reports 75 open
entries still naming this version, and `deferred_findings_spec`'s
shipped-target guard fails the moment a released version has an open
entry pointing at it. Those 75 need retargeting or closing, and that is a
deliberate pass rather than a sweep: `024.19` and `024.35` are in there
because a triage pass called them fixed and a verifier agreed, and both
were wrong.
