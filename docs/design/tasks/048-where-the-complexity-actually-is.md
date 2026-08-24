# 048 — where the complexity actually is

Asked: re-examine every element in the order *what we want to do → the
minimum logic that does it → is the implementation more complex than
that*, write the excess down in one place, and make a release of fixing
it.

This is that document. **The answer is not the one the question
expects**, and the number that says so is worth stating before anything
else.

## The result

Ten subsystems were audited, each by an agent given section 0, told what
shapes count as excess, and required to state a falsifier for every
proposed reduction. They returned **101 pieces of excess**: 2 large, 8
medium, 32 small, 59 trivial.

The ten large-and-medium ones — the only ones that could change a
release's shape — were then each handed to a second agent told to
measure the reduction rather than read it.

| of the 8 medium | |
|---|---|
| safe to apply as proposed | **0** |
| measured **unsafe** | 4 |
| unproven | 2 |
| measured safe but *recommended against* | 2 |

**Not one of the eight survives contact with measurement as written.**
Four would make the product worse. The two that are mechanically safe
are the two the verifier said to leave alone.

That is the finding of this audit: **the complexity in this codebase is
overwhelmingly earned.** 11,659 of its 24,172 lines are comments, and
the audit's own failure rate is what those comments are for — each one
records a defect a specific line prevents, and an agent reading the code
without them proposes removing the line.

## What "unsafe" meant, concretely

Not "risky". Measured:

- **Making `#contains?` exclusive** (the audit's headline type-inference
  reduction): breaks 114 examples, and over 1,070 Rails files **adds 100
  diagnostics and removes 23** with the control unchanged — new
  `argument-type` false positives on `Time.utc(...)`. It also flips
  `#receiver_type_before_dot` from *the receiver before the dot* to *the
  enclosing call's own type*, replacing a correct answer with a wrong
  one in hover, completion and go to definition. Adding the three
  compensations restores parity — and then the change is **+3 net
  lines**. As a complexity reduction it is negative.
- **Narrowing `MethodSummary`**: hover, completion, go to definition and
  signature help stop answering for **84.8% of the calls that path types**
  on a 1,246-file Rails corpus, to fix a path that occurs for 0.32% of
  method symbols — and the thing it "fixes" is an over-wide union that
  *contains* the truth rather than a false assertion.
- **Folding the three agent-refresh claims into one**: the slot the
  audit called duplication is a bound on thread growth. Measured, the
  fold gives **9 live threads where there are 2** for eight spaced
  saves. The two mechanisms bow out in opposite directions —
  newest-wins versus first-waiter-wins — and folding them keeps the
  name-safety and loses the bound, which is the only thing the slot was
  for.
- **Deleting the `unresolved-constant` check**: it is this project's
  **corpus-comparison control**. `CLAUDE.md` instructs putting a control
  in every measurement diff and cites this category; seven recorded A/B
  runs used it. Measured, deleting it takes this repo's own `core/lib`
  from 941 findings to 0 — no control and no signal — and on a six-gem
  corpus leaves only `unknown-method`, which is the category most
  diagnostic changes are trying to move.

## The two that are mechanically safe, and why they are still "no"

- **`Erb.template_uri?` / `analysis_document` duplication.** Identical
  spec results, identical engine answers, identical extracted-source
  hashes. But the two sites carry *two independently earned comments* —
  one recording the 0.2.1 fix that applied the rule where documents are
  fetched rather than at ten handlers, the other recording that summary
  coordinates are the extracted regions. Merging is line-neutral and
  orphans one of them. The duplication is in the code; the knowledge is
  not duplicated.
- **The plugin runtime path.** No caller exists, measured 2503 → 2499
  examples with the same pre-existing failures. What it holds up is not
  behaviour but **the truth of eight published claims**: `site/security.html`
  in both languages tells the public "Runtime plugins — the highest-privilege
  kind — never load at all in an untrusted workspace", `SECURITY_CHECKLIST.md`
  cites the trust gate as a mitigation, both Marketplace READMEs advertise
  the Plugin API, and `loader_spec:543` is the only test of that gate
  anywhere. Deleting the code makes all of it false at once. That is a
  product decision, not a refactor.

## The two structural findings that do hold

Both were verified by hand rather than by an agent.

**1. The plugin subsystem is unreachable in the shipped product — 1,028 lines.**
The only entry is `Server#load_static_plugins`, which requires
`initializationOptions[:pluginManifests]`. The shipped extension sends
`workspaceTrusted` and `ovallspClient` and nothing else
(`vscode/src/extension.ts:233-239`); `pluginManifests` appears nowhere
in `vscode/src`. So the early return at `server.rb:1215` always fires.
`README.md:246` nevertheless lists "Plugin API (static/runtime),
process-isolated plugin execution" under `## Status` as implemented, and
`docs/EXTENSION_CAPABILITIES.md` has **no plugin row at all**.

Two readings, and the audit cannot choose between them: 1,028 unreachable
lines, or a feature waiting for a client. What is not in doubt is that
the documents disagree with each other about which it is.

**2. `server.rb:1956-2355` is analysis logic in the dispatch layer.**
17 methods, ~400 lines, ~10% of that file. Measured: it touches the LSP
protocol **zero** times — the single `respond` match is the string
`respond_to do |format|` inside a comment — and its dependencies are all
analysis collaborators (`@local_inferencer` 9, `@document_store` 5,
`@workspace_index` 4, `@hierarchy_index` 3). Three call sites. This is
register entry `024.63`, confirmed.

## What survives, carved out by the verification

The verifiers did not say "do nothing". They said the proposals as
written are wrong, and each carved out a part that measurement supports:

| | measured |
|---|---|
| Runtime Agent `"metadata"` branch + `#metadata_section` + the `\|\| ["metadata"]` default | genuinely dead and unpinned; deleting produced **0 failures** |
| `#discover_models` as a second copy of `#models_result`'s `descendants.reject(&:abstract_class?)` | a real one-rule-two-places case — a better argument than "unreachable" |
| `MethodSummary` move (a) | nothing breaks; two suites identical, byte-identical corpus output |
| agent-refresh phase 1 — routes and all_models only, which *do* share the rule | behaviour-preserving, measured green |

These are small. They are also the only things in the audit that a
measurement supports doing.

## What was done, and the one that was not

Three of the four carve-outs are in. Each was re-verified by hand before
being applied, not taken from the agent's word.

**`agent/snapshot`'s `"metadata"` section, and its `|| ["metadata"]`
default.** Every caller of `AgentProcessManager#fetch_snapshot` passes
`["routes"]` (`rails_bootstrap.rb:118`, `server.rb:3426`) and no spec
asked for the section. It also restated three of `#hello_result`'s four
fields, so a Core that wanted it had a cheaper way to ask.
`05-protocol.md` updated in the same change.

**`#discover_models` and `#models_result` now share one enumeration.**
They had the same four decisions written out twice — is ActiveRecord
loaded, eager-load first, drop `abstract_class?`, drop anything without
a usable `name` — differing only in the payload. `#concrete_models`
yields the class; the payloads stay different, because they genuinely
are: discovery is deliberately lightweight and `agent/models` is not.

**`MethodSummary#parameter_types` and `#effects` are gone**, with
`#parameter_types_for`. Both were written on every summary — `{}` and
`[]` at one site, a built Hash at the other — and read by nothing. The
doc comment defended them as reserved "so a later task doesn't need to
change this shape", which is the reasoning `AGENTS.md` forbids outright:
*never implement functionality speculatively or in advance; apply YAGNI
rigorously*. A `Data.define` shape can be extended the day something
needs it. Both design documents updated.

### The fourth was declined

Folding `#refresh_routes` and `#refresh_all_models` onto one superseding
claim is behaviour-preserving and measured green. It was still not done,
and the reason is the arithmetic rather than the risk: it buys **6 to 15
lines out of 4,025** in the most concurrency-sensitive method group in
the server, and it forces `core/spec/meta/rescue_verdicts.yml` to
collapse **two separately argued `surfaces` verdicts into one shared
verdict**.

That trade is the wrong way round for this codebase. The whole finding
of this audit is that the reasoning attached to code is worth more than
the lines, and a reduction whose cost is paid in recorded reasoning is
not a reduction. Recorded here rather than left as an omission, so the
next person does not re-derive it as an opportunity.

## The 91 not verified

32 small and 59 trivial findings are recorded in the raw audit output and
have **not** been through a verification pass. Given that 8 of 8 material
findings failed verification, the honest prior is that a similar
proportion of these are earned correctness too. They are not a backlog;
they are a list of things that would each need measuring before they
became one.

## What this means for 0.2.16

A release of simplifications is not supported by the measurement. What
the audit found instead is:

- two **product decisions** — the plugin subsystem, and whether view
  inference moves out of the dispatch layer;
- four small carve-outs worth doing;
- and a codebase whose complexity is, where it was measured, the record
  of defects already paid for.

The counting rule is worth keeping for whoever revisits this: an audit
that reports 101 findings and survives verification on 0 of its 8 biggest
is not measuring the code. It is measuring how much of the code's reason
lives in comments an auditor did not read.
