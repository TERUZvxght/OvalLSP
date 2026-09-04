# 060 — The rules after the gates

**Branch:** `docs/060-rules-after-the-gates`, merging into `main` by pull
request.

## Why

059 turned the procedures with a fixed order into commands that refuse.
A rule a command refuses is kept without anyone holding it in mind, and
the card's job is the rules that *have* to be held in mind — so the
maintainer asked (2026-09-04) for the rulebook to be re-tidied against
what the gates now keep. This is that pass, in two halves: which lines of
`AGENTS.md` changed enforcement class, and which documents still told a
person to do by hand what a command now does.

## The card

| Line | Before | After | Kept by |
|---|---|---|---|
| The legend | *check* = `preflight` or CI fails | *check* = a command, `preflight` or CI refuses. A refusal at the moment of doing is the third kind of check 059 added, and the legend did not name it | — |
| Documents: the trigger table | "walk it"; *check*, in part | preflight enforces the rows whose trigger is a file; the rest are walked; *check* for file rows | `scripts/check_doc_triggers.rb` |
| Documents: a new issue | intake → an entry "in the legend's shape; the index is generated"; *check*, in part | `issues.rb promote` writes the entry and `close` retires it, each refusing a decision left unmade; *check*. The shape and the index are the command's, not the writer's | `scripts/issues.rb` |
| Documents: a round's findings | "into the task file as the round produces them" | into the table `review_round.rb start` opened. The place exists before the first finding does | `scripts/review_round.rb` |
| Review loop: closing | a method the previous round did not use; *judgement*, with the four methods listed | the repeated method and the tree that moved under a round are refused; who reviews and what counts stay judgement. The method list lives in `docs/REVIEW_LOOP.md` and in the command's own refusal | `scripts/review_round.rb` |
| Releases | a patch ships without asking "if `docs/PUBLISHING.md`'s privacy checks passed"; *judgement* | `bump` decides what a patch is (no capability row moved since the last tag) and `gate` runs the privacy checks; *check* up to the asking, which is the one part no program can do | `scripts/release.rb` |
| Session start | five lines | four: "list the directory" folded into "never trust a number written elsewhere", which is the rule it was an instance of | — |

The budget held: 120 lines before, 120 after. The lines that became
*check* got shorter, which is the point — a check explains itself when it
fires, so the card need only say that it exists.

## The documents

- `docs/DEVELOPMENT.md`, "Commits, and the public repository": told a
  person to run `gitleaks` before a push. The pre-push hook runs it over
  the outgoing range and `gate` over the whole history; the command stays
  for a scan by hand, labelled as that.
- `docs/PUBLISHING.md`, the standing permission for a patch: each of its
  conditions now names what runs it — `bump` refuses a patch that moved a
  capability row, `gate` runs gitleaks over the history and the hook over
  the outgoing range, and `gate`'s preflight and the hook between them run
  the home-path scan in both modes. The conditions themselves did not
  change. The versioning section says `bump` moves both version files
  together with the lock files and the badge; the artifact steps name
  `record` and say which checklist rows `gate` runs and which stay by
  hand.
- `docs/RELEASE_CHECKLIST.md`: two sentences that 058 wrote — the four
  steps are done by hand, and the whole-history scan is run locally —
  stood one paragraph above the sentence 059 wrote saying `gate` does
  both. The contradiction is gone; the paragraph now says what became a
  command and what did not. The targeting section says what the tools do
  with the list (`open` prints it, `gate` refuses while an entry is open)
  and what they do not: re-run the reproduction.
- `docs/DOCUMENTATION_MAP.md`: the intro says which rows preflight
  enforces, and the version-number row says `bump` moves the six files
  together.

## What stayed judgement, and why

Reading the record at the start of a session; test first; the simplest
construction; one measurement at a time; re-running a reproduction before
promoting a finding; who reviews and what counts as a finding; the bound
of three rounds; the same place twice; asking before a minor or major.
None of these is a fact a program can read off the tree, and a check that
guessed at one would carry the false-positive rate `024.150` measured
before that check was switched off. They keep their lines.

## 残課題

未処理の指摘はこの文書ではなく `024` に書く。
