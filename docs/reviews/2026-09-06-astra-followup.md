# Astra follow-up review — 2026-09-06

The original probes demonstrate several real repairs, but **they do not establish that all sixteen original acceptance conditions were satisfied**. R07 explicitly remains narrower than the requested branch-sensitive fix. The two remaining `old_accepted: true` values for R06 are calls that bypass the new generation argument, not demonstrations that the production disk path still behaves like the old implementation.

This report closes the investigation at the user's request. Prepared additional probes were **not executed** and supply no findings. No additional filesystem-permission or symlink probes were run after that instruction.

## Evidence and scope

- Reviewed revision: `61eb96437b453f94804dbbaa1855e2dbcda16941`. The supplied worktree was detached at this commit, despite being described as checked out on `release/0.4.0`.
- Read `AGENTS.md`, product requirements section 0, measurement/development/review instructions, the original review, all three commit messages, and implementation/test changes. This is not a completed exhaustive audit of every committed evidence artifact.
- Measurements used a private Git copy and a worktree created with `git worktree add` at `/private/tmp/astra-followup/head`. The main checkout was not measured or modified. No fetch was performed under the review-only instruction.
- Runtime reported by the completed probe: Ruby `3.4.10`, OvalLSP `0.3.3`. The release branch's name is not the library version.
- **Before** below means the original review's committed [probes.json](2026-09-05-critical-review/probes.json). **After** means my completed run, `/private/tmp/astra-followup/original-probes.json`. The before side was not rerun in this session. The original review included an uncommitted constant-resolution change at its starting revision; this is not a clean `9c17dc2` versus HEAD corpus experiment.

Completed reproduction command, from `/private/tmp/astra-followup/head/core`:

```sh
/opt/homebrew/bin/ruby /opt/homebrew/lib/ruby/gems/3.4.0/bin/bundle exec \
  /opt/homebrew/bin/ruby -Ilib \
  ../docs/reviews/2026-09-05-critical-review/probes.rb \
  > /private/tmp/astra-followup/original-probes.json \
  2> /private/tmp/astra-followup/original-probes.err
```

Exit status: `0`. Stderr:

```text
review-probes: cwd=/private/tmp/astra-followup/head/core ruby=3.4.10 ovallsp=0.3.3
```

The table refers to that command as **P**. Its JSON keys identify the exact output. It actually executes its synthetic Ruby examples using `Module.new.module_eval`; Ruby results below come from that execution, not from an assumed language rule. Where no interpreter experiment ran, I do not offer one as evidence.

## 1. R01–R16: original acceptance conditions

**Met** would mean the original 「確認する条件」 was demonstrated in full. **Partly met** means a repair is supported by execution or source inspection, but a stated condition remains missing or untested. It is not a full acceptance verdict. **Not met** below can mean acceptance was not demonstrated; that is distinguished from an observed failing reproduction in the evidence column. In particular, missing host or race tests are not invented product defects.

| ID | Verdict | Evidence and the precise missing part |
|---|---|---|
| R01 | **Partly met — source evidence only** | `bb1c450` changes `Cache::Store.inside?` to resolve the root and parent, and skips direct symlinks in `tighten`. Its message explicitly says this is **not** a defence against replacement between check and removal. The original condition expressly requires a controlled replacement test, plus deletion/chmod controls. I did not run `cache-probe.rb` or the prepared boundary probes. Static changes cannot certify these conditions, and I do not claim an external deletion or chmod on HEAD. |
| R02 | **Partly met** | **P**, `override_rename.accepted`: **`true → false`**. The original unsafe parent edit is now refused and supplies no edited source. The original source still evaluates to **`2`** in this run. Missing: child-side and multilevel cases, executing accepted unrelated-name edits, and a real-gem refusal census. The HEAD JSON's `after: "NoMethodError"` is an artifact explained below, not execution of a returned edit. |
| R03 | **Partly met** | **P**, `keyword_completion.insertText`: **`take(${1:required}) → take(required: ${1:required})`**; `insertTextFormat` remains **`2`**. This repairs the demonstrated missing keyword colon. Missing: filling and executing the generated snippet, mixed positional/required/optional keyword binding, complete tab-stop numbering, and a no-argument control. |
| R04 | **Partly met** | **P**, `cold_race.indexed`: **`["::OldVersion"] → ["::NewVersion"]`**, while disk text is **`class NewVersion; end`** on both sides. The controlled old-read-finishes-last reproduction passes on HEAD. Missing: the reverse arrival ordering and an independently executed ordinary cold-index control for the full condition. |
| R05 | **Partly met** | **P**, `dependent_refresh`: publication counts **`1 → 1` before**, **`1 → 2` on HEAD**. `signature_refresh` has the same improvement. Forced analysis still returns **`` `take` takes 2 arguments, but 1 given ``** and **`` `take` expects String here, but Integer is given ``**, respectively. Thus refresh is scheduled in these two cases. The probe does not save the automatic publication's contents separately from the later forced result. Missing: warning appearance/removal contents, restoration, newly resolvable names, and declaration/file deletion. `61eb964` also explicitly leaves inferred-return-body changes outside its comparison. |
| R06 | **Partly met — old probe bypasses the repair** | **P**, `disk_stale_publish.old_accepted`: **`true → true`**; `disk_after_clear.old_accepted`: **`true → true`**. Both direct calls omit `generation:`. The production disk path now supplies it, including for `[]`; no normal production caller publishing an undated disk analysis was found in the traced call sites. These two booleans do **not** establish that R06 is genuinely unfixed. Missing: execution of the dated path and the original deletion/recreation/open-during-analysis ordering conditions. See the detailed call trace below. |
| R07 | **Partly met — an explicit acceptance gap remains** | **P**, `explicit_guard.findings`: **one `unknown-method` → `[]`**; `bare_guard.findings`: **`[] → []`**. `guard_leaks.findings`: **`[]` → one `unknown-method` for `Unrelated#absent` at line 7**. `guard_control` continues to report `absent`. Thus explicit self and the separate-class example are repaired. However, the implementation scopes by enclosing-body line range and `bb1c450` expressly acknowledges that it does not distinguish branches. The original condition requires the true branch alone, plus inside/outside controls. That half is missing, not satisfied by documenting it. Additional branch/same-line/nested-context probes were prepared but not run. |
| R08 | **Partly met** | **P**: `rename_world!` and `rename_world?` go from **`accepted: false`** to **`accepted: true, parses: true`**. Returned source changes both definition and bare reference to the same new name. `world` remains accepted; `world=` and `end` remain refused. Missing: executed rejection controls for whitespace/expression injection and the full separately defined operator/setter scope. |
| R09 | **Partly met** | **P**: `inherited_constant.findings` changes from **`cannot resolve constant Child::LIMIT`** to **`[]`**; Ruby returns **`3`**. `unrelated_constant.findings` changes from **`[]`** to **`cannot resolve constant LIMIT`**; Ruby raises **`NameError`**. `Parent::LIMIT` remains clean, and the genuinely missing bare `LIMIT` remains reported. These are the two important directions of the original defect. Missing: nested/reopened namespace cases and separate `safe`-mode execution; P explicitly passes `:standard` for these fixtures. No fresh constant corpus comparison was completed. |
| R10 | **Partly met** | **P**: `LocationRbs.decoded_exists` and `LocationRbi.decoded_exists` each change **`false → true`**; both URI suffixes now contain **`project%23one/sig/…`**. `posix_uri.roundtrips`: **`false → true`**, with `one\two.rb` preserved. Missing: the complete Unicode/Windows/escaping matrix, a Server definition response's range, and actual VS Code navigation. These location checks call the signature environment, not the editor. |
| R11 | **Partly met** | **P**, `watcher_escape`: cold names stay **`[]`**; watcher names change **`["::OutsideSentinel", "secret"] → []`**. The original static external-link discrepancy is repaired. Missing: internal-file/internal-link controls, intermediate-directory links, retargeting retirement, and controlled pre-read replacement. Those additional filesystem probes were not run; the user assigned that area to another reviewer. |
| R12 | **Partly met — source evidence only** | `bb1c450` adds `*.rake` to `WATCHED_FILES_GLOB` and introduces the bidirectional extension-list checker. That addresses the original missing-glob cause. `platform-probes.cjs` was not rerun. Missing: the original condition's real-host unopened `.rake` create/change/delete cycle and maintained `.rb`/`.erb` behavior. |
| R13 | **Partly met — source evidence only** | Source inspection shows a configuration subscription before the disabled gate, a stop transition, and trust/folder subscriptions before that gate. `61eb964` adds the missing `enabled` check to the trust callback. No host or stub-host lifecycle experiment was executed here. Missing: live off/on, rapid toggles while starting, multiple folders, untrusted workspace, process/diagnostic cleanup, and no duplicate restart. |
| R14 | **Partly met — source evidence only** | The changed resolver checks required plus trailing positional minimum before accepting rest, and required keyword presence before accepting keyword rest. I did not execute `overload-probe.rb` or the expanded resolver matrix. Missing: minimum/extra/trailing arguments, unknown splats, selected return types, and the hover/signature-help consumer required by the original condition. |
| R15 | **Not met — acceptance not demonstrated** | No new timing, save-to-publish latency, hover-blocking measurement, or detection-control experiment completed. `46c0cd6` itself leaves `024.45` open and reports seconds per analysis after the optimization. This session does not independently validate either that performance improvement or the original acceptance condition; this is not a newly measured timing regression. |
| R16 | **Partly met — source evidence only** | The diff updates the prose protocol version and current Core method list, and adds bidirectional custom-request comparison. The later commit corrects the earlier message's census. I did not execute the checker or its old-name/missing-name/prose-version mutations. Missing: demonstrated failure of those mutations, explicit future-proposal treatment, and full arguments/results/side-effects correspondence. |

### R02: do not misread the retained `after` field

The completed HEAD output is:

```json
"override_rename": {
  "accepted": false,
  "before": 2,
  "after": "NoMethodError"
}
```

In [probes.rb](2026-09-05-critical-review/probes.rb), a refused rename returns `{accepted: false}` without `:source`. The later before/after loop nevertheless attempts `text + "\nConsumer.new.go"` on the absent after-text. That raises `NoMethodError`, which its rescue records. **No HEAD rename edit was applied in that branch.** Treating this field as a second broken-program execution would falsely condemn the repair.

### R06: the undated probe and the actual callers

The original probe calls, unchanged on HEAD, are:

```ruby
server.send(:publish_findings, uri, [], document: newer)
accepted = server.send(:publish_findings, uri, [finding], document: old)
server.send(:clear_findings, uri)
accepted_after_clear = server.send(:publish_findings, uri, [finding], document: old)
```

Both documents have `version: nil`. Although `finding` has an internal generation, the disk branch does not derive its ordering argument from findings. It uses the separate keyword. The completed output is consequently:

```json
"disk_stale_publish": {
  "old_accepted": true,
  "final": [{"code": "unknown-method", "message": "old answer"}]
},
"disk_after_clear": {"old_accepted": true}
```

The `final` entry above omits its unchanged LSP metadata for readability. The two booleans are quoted exactly.

The call-site check was:

```sh
rg -n 'publish_findings|generation:' \
  core/lib/ovallsp/server.rb core/lib/ovallsp/workspace_diagnostics.rb
rg -n 'publish_diagnostics\(' core/lib/ovallsp
```

Relevant output:

```text
core/lib/ovallsp/server.rb:119:        publish: method(:publish_findings),
core/lib/ovallsp/server.rb:582:      publish_findings(document.uri, Diagnostics::MidEditCall.filter(findings, document), document: document)
core/lib/ovallsp/server.rb:667:    def publish_findings(uri, findings, document: nil, generation: nil)
core/lib/ovallsp/workspace_diagnostics.rb:147:      @publish.call(uri, findings, document: document, generation: generation)
core/lib/ovallsp/server.rb:562:        publish_diagnostics(document)
core/lib/ovallsp/server.rb:566:    def publish_diagnostics(document)
core/lib/ovallsp/server.rb:4627:        publish_diagnostics(document)
```

Following those sites in source establishes:

1. Server wires `WorkspaceDiagnostics` to `workspace_findings_for` and `publish_findings`.
2. `workspace_findings_for` returns `[findings, context.generation]` inside `with_index_snapshot`. `[]` still receives a generation.
3. `WorkspaceDiagnostics#publish_for` forwards that generation explicitly.
4. The other call, `Server#publish_diagnostics`, omits the keyword. Its normal callers are `drain_settled_analyses`, which fetches a document from the open-document store, and `republish_open_diagnostics`, which iterates `open_documents`. It is the buffer path, not a remaining ordinary disk reader.
5. The disk branch deliberately permits `generation: nil`; the direct test/API call still can bypass dating. `clear_findings` directly sends a clear, rather than an analysis result, and is not another undated disk-analysis producer.

**Verdict on the specific question:** the two `true` values are a stale probe/API-contract mismatch, not evidence of a remaining normal production disk caller omitting the argument. No such caller was found in the traced implementation. Conversely, this source trace does not prove that the generation represents the correct file-read identity in every interleaving. The original race acceptance tests were not rerun with the new contract, so R06 is not certified fully met.

## 2. New defects

**No additional runtime-demonstrated defect beyond the original review was established before the stop instruction.** I will not turn unexecuted scratch scripts or suspicious source paths into findings.

The material acceptance gap already established is R07: the two reproduced scope/spelling cases are repaired, while branch-sensitive guarding is expressly absent. That is a remaining part of R07, not a new discovery to count twice. R01's swap limitation is also acknowledged by its own commit, but I did not reproduce it and make no HEAD filesystem finding.

The original capability controls still exhibit known limitations:

```text
P key                 HEAD diagnostics            Ruby execution in P
missing_keyword       []                          ArgumentError
extra_keyword         []                          ArgumentError
primitive_typo        []                          NoMethodError
module_typo           []                          NameError
positional_control    argument-count              ArgumentError
custom_typo           unknown-method              NameError
```

These are actual completed results, but the original review already reported them. They are not introduced regressions or newly discovered defects. The original script contains the exact sources and expressions; the after JSON preserves them alongside these results.

## 3. Claims checked

| Commit / claim | What this session establishes |
|---|---|
| `bb1c450`: fourteen findings fixed | The completed P run supports the specific repairs in R02/R03/R04/R07/R08/R09/R10/R11 above. It does **not** support fourteen fully satisfied original acceptance conditions. The message itself acknowledges R07's missing branch semantics and R01's swap limitation. |
| `46c0cd6`: caller and signature refresh connected | Reproduced at HEAD: both publication counts change from the recorded baseline's **1 → 1** to **1 → 2**. This checks the basic connection, not every dependency shape or publication-content condition. |
| `61eb964`: `preflight` 17/17 and 3,387 examples | A preflight attempt was started in the scratch HEAD worktree with copied local Node dependencies. The only completed result captured was **`documented example counts current... ok (0.6s)`**. This supports documented-count consistency; it is not a completed run of 3,387 examples. No full-suite completion or 17/17 verdict was captured. **Not independently reproduced; not shown false.** |
| `bb1c450` / `46c0cd6`: 3,363 / 3,381 examples, 17 checks, 119 environment-dependent examples | No completed historical suite runs. **Not checked.** |
| Pinned mutations: 218 / 224 / 228, all caught | The mutation runner was **not run**. Reading mutation entries is not evidence that they are caught. **Not checked.** |
| All three messages: 205 extension unit tests | No `npm run test:unit` execution completed in this review. **Not checked.** |
| HEAD analysis times: 4.22 / 11.10 / 12.26 seconds | No performance reproduction ran. **Not checked.** |
| `46c0cd6`: 0.2.18/before/after timing table; `61eb964`: within about 10%, including reindex-between-repeats | No sequential paired timing experiment completed. **Not checked.** |
| 8-gem A/B: 0 introduced, 766 removed, controls 38/73; 530-file A/B: 0 introduced, 34 removed, control 23; 648-file A/B: 0 introduced, 42 removed | No corpus driver run completed. No equal corpus digest/different revision pair was established for these counts. **Not checked.** |
| Thor: 57 added rename refusals, none unjustified; ActiveSupport core_ext: 67 additional refusals, none accepted by Ruby | No gem-wide rename census or Ruby pair oracle ran. **Not checked.** |
| Hook census: 42/51 hooks, 55/994 types; memo size about 130 KB after 85 files; 38 examples failing against the old library | No independent derivations completed. **Not checked.** |
| `bb1c450` protocol census: three obsolete names / two missing names | `46c0cd6` explicitly corrects this to **four / five**. The earlier claim is retracted by its successor; I did not independently rerun the census. |

The preflight command was:

```sh
env PATH=/opt/homebrew/opt/ruby@3.4/bin:/opt/homebrew/bin:/usr/bin:/bin \
  XDG_CACHE_HOME=/private/tmp/astra-followup/cache \
  ruby scripts/preflight.rb > /private/tmp/astra-followup/preflight.log 2>&1
```

Working directory: `/private/tmp/astra-followup/head`, on the private Git copy's `release/0.4.0` branch pinned to `61eb964`. Last captured output:

```text
preflight: documented example counts current... ok (0.6s)
preflight: full suite...
```

There is no recorded exit status for the complete preflight attempt. The tool session was no longer available when resumed. Neither a green suite nor a failing suite follows from this incomplete log.

## 4. Clean results

The following are positive measured results from P, with their limits already stated in the table:

- The originally destructive parent rename returns no edit.
- `world!` and `world?` rename results parse and change both shown declaration and reference; ordinary `world` remains accepted, `end` and `world=` remain refused.
- Keyword completion preserves the required keyword colon.
- The controlled slow cold read no longer overwrites `NewVersion`.
- The two basic dependency changes each cause an additional caller publication.
- Explicit and implicit `self` guard spellings are both clean; the unrelated class's missing call is now reported.
- The inherited plain constant is clean and the unrelated same-name constant no longer silences the missing reference. The same-owner and absent-name controls remain correct.
- The original static external-link watcher reproduction contributes no outside declarations through either entrance.
- Both signature-location URI probes decode to existing files, and the POSIX backslash filename round-trips.
- Positional-arity and workspace-method typo controls still report, so the completed diagnostic probe did not merely silence everything.

These clean results deserve credit. They are not substitutes for the missing acceptance experiments.

## 5. Not demonstrated

I did not demonstrate a fourth mutable input invalidating the hierarchy memo, a remaining production signature-reload path missing its clear, a real-gem unjustified rename refusal, or a new failure caused by the frozen ancestor array. I also did not establish correctness of all those paths.

No fresh corpus regression counts, performance medians, memo memory census, mutation-sweep verdict, completed full-suite verdict, VS Code host navigation, host watcher lifecycle, or extension enable/disable lifecycle results are available from this session.

The prepared diagnostic, dependency-refresh, disk-ordering, and containment scripts under `/private/tmp/astra-followup/` were not run. Their existence is not evidence. In particular, I do not assert the prospective constant, hook, macro, dependency, or race counterexamples they contain. Further permission/symlink investigation was expressly left to the separate reviewer.

Only this requested report was written in the supplied working root. No implementation, test, release record, commit, or main-checkout change was made.
