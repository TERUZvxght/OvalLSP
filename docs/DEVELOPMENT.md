# Development

How this repository is set up, tested, committed and branched.
`AGENTS.md`'s "Branches, commits, releases" lines point here, and so does
the setup half of its "Writing code"; this is the how-to behind them.

## Layout

- `core/` — the Ruby Core Language Server (`ovallsp`), LSP 3.17 over
  stdio.
- `vscode/` — the VS Code extension, a thin client that launches
  `core/bin/ovallsp --stdio` per workspace folder.
- `docs/` — the documents `AGENTS.md` lists, the support matrix and the
  release records; `docs/design/` holds the design documents, the ADRs
  and the per-release task records.
- `site/` — the public site, hand-written HTML, generated from nothing.

## Setup

Ruby 3.4.x and Node.js 20, which is what CI installs;
`vscode/package.json`'s `engines.vscode` is the VS Code API version
targeted.

    cd core && bundle install
    cd ../vscode && npm install

Two Core suites drive a real Rails application and need `rails ~> 8.1`
and `sqlite3` resolvable as **local** gems. The fixture is bundled with
`--local`, so a network that could fetch them is not enough:

    gem install rails -v "~> 8.1" && gem install sqlite3

Without them, `spec/e2e/capabilities_spec.rb` and
`spec/integration/real_rails_spec.rb` skip in full and `rspec` still exits
0; so does `spec/meta/client_behaviour_spec.rb` without
`vscode/node_modules`. A skipped example is still an example, so a count
cannot see this, which is why `preflight` and CI read each example's
status instead (`scripts/check_suites_ran.rb`). A pending example whose
message does not say `NOT YET` is this.

## Running tests

    cd core && bundle exec rspec
    cd vscode && npm run test:unit
    cd vscode && npm run test:integration            # a real Extension Development Host, monorepo Core
    cd vscode && npm run test:integration:packaged   # the same, against a copy-core layout

## Before committing

    ruby scripts/preflight.rb

Everything that has to be true before a commit, in one command. `--list`
names the checks, and this document deliberately does not: every prose
enumeration of the gate went stale by the release that added a check to
it (`024.195`). `--install` makes it a pre-commit hook;
`PREFLIGHT_SKIP=1 git commit …` skips it for one commit. After its verdict
it prints one non-gating `ci:` line, because a green preflight says
nothing about `vscode/` or about CI (`024.284`).

Two sweeps are run by hand rather than by preflight, because both write
into the tree and restore it:

- `ruby scripts/hunk_sweep.rb [base]` reverse-applies each hunk of the
  change set on its own and runs the suite; a hunk that leaves the suite
  green is unpinned behaviour.
- `ruby scripts/check_pinned_mutations.rb` applies every mutation named in
  `core/spec/meta/pinned_mutations.yml` and requires the named example to
  fail. CI runs this one on every push.

Never run either while anything else is mutating the same tree. The hunk
sweep refuses a dirty tree and a concurrent sweep; the mutation applier
restores each file but cannot see another writer, so that one is on you.

## Before pushing

    ruby scripts/preflight.rb --install-prepush

Two things must be true of a push and of nothing else, so neither is in
preflight: the outgoing range carries no secret, and no commit or tag
message carries a real home path. The tree scan preflight runs cannot see
a message, and `gitleaks` over the history is not a price to pay on every
commit — so they are a pre-push hook. It refuses the push on either, and
refuses when `gitleaks` is not installed rather than passing, because a
scan that did not run reports what a clean one reports.
`PREPUSH_SKIP=1 git push …` skips it for one push; say what you checked
instead.

## What else has to change when a file does

    ruby scripts/check_doc_triggers.rb

[`docs/DOCUMENTATION_MAP.md`](DOCUMENTATION_MAP.md)'s trigger table says
what must change alongside what. The rows whose left column is a set of
files are data in [`docs/doc_triggers.yml`](doc_triggers.yml), and this
fails from preflight when one of them changed on your branch and none of
its companions did. It asks for one companion, not all of them, and it
covers only the pairs nothing already checks — that file says per rule
what it adds.

## Cutting a release

    ruby scripts/release.rb status

One command per step — `open`, `bump`, `gate`, `publish`, `record` —
each refusing when the one before it left no evidence, and every refusal
naming what clears it. It implements no check: each step runs the script
or spec that already owns the question.
[`docs/PUBLISHING.md`](PUBLISHING.md) has the sequence and the
permission it operates under.

## Branches and pull requests

One `release/<version>` branch per version, every commit for that release
on it, merged into `main` by pull request. `main` is what has shipped, and
GitHub protects it: a pull request is required; ten status checks are
required — every CI job except the informational Ruby 4.0 one and the
darwin-arm64 packaged job 0.3.2 added, which the list does not yet
include; the branch must be up to date; the rules apply to
administrators; force pushes and deletions are refused; and no approving
review is required, because GitHub does not let a solo maintainer approve
their own pull request. Verified by trying it: a direct push to `main`
comes back `GH006: Protected branch update failed`. Set by the maintainer
on 2026-09-01; `028` records what building a release without a branch
cost.

Work that is not a release — a correction to the record, a fix to a check
— takes a short-lived branch of its own and the same pull request. The
release's task document on `main` names its branch, and
`scripts/check_release_pointers.rb` fails on a release branch that no
document names.

**A merged branch is kept.** `main` squash-merges, so a release's
individual commits, and the reason for each, exist only on its branch.
Deleting one is a decision to write down, not tidying; local branches and
worktrees are ordinary clutter.

Before opening a pull request: preflight is green, `npm run package`
succeeds if packaging changed, and the description says what changed, why,
and which tests ran.

## Commits, and the public repository

This repository is public. Never commit or push secrets, credentials,
private URLs, personal information or a real home path — in source,
fixtures, generated files, logs, copied command output or commit messages.
Use a public noreply address for commit metadata. Before a push, inspect
the complete outgoing diff and commit range, and run the secret scan:

    gitleaks detect --config .gitleaks.toml

`scripts/check_home_paths.rb` is the one detector for home paths, read by
`home_path_guard_spec` for tracked content and by CI's secret-scan job for
commit messages. Adding a name to its `SYNTHETIC` list is a deliberate
edit with a reason.

## The register

`scripts/issues.rb` is the way in and the way out. It reads and retargets
entries, and it opens and closes them:

    ruby scripts/issues.rb intake                     # the untriaged list, numbered
    ruby scripts/issues.rb promote <n> --kind K --target V \
        --area A --direction D --user-visible yes|no [--note "…"]
    ruby scripts/issues.rb close 024.N --released-in V [--drop-paragraphs]

`promote` takes the n-th intake item, allocates a number never used
before, writes the entry in the legend's shape, drops the bullet,
restates the list's own count, and re-runs the register's three guards.
`close` sets the status, moves the entry to the archive and re-indexes —
and refuses while either language still publishes a paragraph for the
finding, printing both locations. `--drop-paragraphs` removes the whole
`##` section rather than the marker inside it, because a marker removed
on its own leaves the limitation published and silences the guard that
would have reported it. `docs/ISSUES.md` has the four decisions each
option stands for, and why the command refuses rather than defaulting
any of them.

Every write goes through one primitive that is told what the edit should
cost and refuses one that costs anything else. Editing the register by
hand is still possible and is a worse idea than it looks: it is 25,000
lines across two files, four enforced fields per entry, a number that may
never be reused, and a generated index. A scripted edit of it uses the
block form below.

## Edits that lose work

- `git checkout <file>` discards uncommitted work, silently. Use
  `git stash` or copy the file aside — and after `git stash pop`, commit
  before running anything whose effect is "make this match something
  else".
- Prefer a form of work that can be replayed — a patch file, a script —
  over one that exists only in the tree.
- A scripted edit uses `String#sub`'s block form: the replacement string
  expands backreferences, and a backtick in it pastes the whole preceding
  file in at the anchor (`024.225`).
