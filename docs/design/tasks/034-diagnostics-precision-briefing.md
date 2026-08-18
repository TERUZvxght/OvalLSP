# Task 034: Briefing for an external reviewer — the undefined-method check's precision and recall

**Audience:** an external model (GPT-5.6 Sol), asked for root causes and a
structural proposal. **Not** a decision record; nothing here is adopted.

**Lifecycle:** this file exists to be answered. When the answer has been
verified and acted on, it is replaced by whatever 0.2.6 records, and this
one is deleted. Say so here because this repository's own problem is
documents that accumulate without an end state.

**What this file deliberately does not contain:** my diagnosis. Three
review rounds on 0.2.5 found that three of my own confident claims were
false, one of them a *causal* claim that sent work at the wrong subsystem
(`024.78` — I said completion and hover infer different types; they do
not, the qualification is lost during member lookup). So what follows is
measurements, reproductions and code. Hypotheses are marked as such and
are there to be refuted, not built on.

---

## 1. What the product is for

`docs/design/docs/01-product-requirements.md` section 0, which is the only
standard that matters here:

> Ruby/Rails LSP support is markedly weaker than other languages', so
> every guarantee falls to hand-written tests. This product takes the
> basic half back — **type checking and calls to methods that do not
> exist** — so tests can narrow to what they are actually for. **1.0.0**
> is where that becomes usable in practice, with Pylance as the
> reference.

And section 0.4, which decides what is worth fixing:

> A wrong answer is worse than no answer. **But letting 1.0.0 recede
> forever in pursuit of accuracy is worse than either.** So a wrong
> answer on a path people walk daily blocks the release; one on a path
> almost nobody walks is recorded as a known limitation and ships.

The check under discussion is half of what 1.0.0 *is*.

## 2. The measurement

Driven over **213 files** of installed gem source (rack 3.2.6, i18n
1.15.2, concurrent-ruby 1.3.8) by running the real server over stdio.
Reproduced twice, by two independent reviewers.

**54 `unknown-method` findings. 53 are false.** 0.25 per file; 17 of 213
files affected. Identical before and after 0.2.5's changes, so this is
the standing state of the check, not a regression.

Breakdown, recounted:

| n | cause | example |
|---|---|---|
| 12 | a class `include`s a module **defined in the same file, from inside a nested namespace**, and loses its methods | `Rack::Request` includes `Helpers` (`rack/request.rb:784`); `def request_method` is at `:202`; the check reports `Rack::Request has no method named request_method` |
| 31 | metaprogrammed accessors | `attr_atomic`, `attr_volatile`, `singleton_class.send :alias_method, :[], :new` |
| 8 | platform-specific files | JRuby-only sources, unreachable on MRI |
| 2 | `::JSON.parse` inside a namespaced module | did not reproduce in isolation; context-dependent, uncharacterised |
| 1 | **arguably true** | `rack/auth/abstract/handler.rb:21` calls `challenge`, which `Rack::Auth::AbstractHandler` genuinely does not define — an abstract template method supplied by `Rack::Auth::Basic`. Literally a `NoMethodError` if the abstract class were used directly, and still not something a Ruby developer wants reported |

**Why row 1 is the one that matters:** Rails concerns are exactly that
shape — a module included by a class, both inside `module Foo`. So the
check reports confidently on ordinary application code.

**Row 2 should be silence, not a report.** Static analysis cannot see
`attr_atomic`; the check's own stated policy is that a missed report
beats a wrong one.

### The other half: recall

`Billing::Order.recent.first.tracking_label` — a method that does not
exist on that model — **is reported by nothing.** The same wrong call
written `Billing::Order.find(id).tracking_label` **is** reported.

Completion at that same position offers 329 labels and `tracking_label`
is not among them. So the type information exists and the diagnostic path
does not use it. `Model.scope.first.method` is an everyday Rails idiom.

(Recorded as `024.76` and `024.77`. `024.79`: `Model.first.` completes to
nothing while `Model.scope.first.` completes to 329 — likely related,
possibly not.)

## 3. How to reproduce

```bash
cd core && bundle install
# drive the real server; spec/e2e/lsp_client.rb is a usable client
ruby -Ilib -Ispec -e 'require "e2e/lsp_client"' # see spec/e2e/ for usage
```

The measurement above pointed the server at a workspace whose root
contained the unpacked gem sources, opened each `.rb` file, and collected
`textDocument/publishDiagnostics` with `code == "unknown-method"`.

Two traps that cost this project real time: the real-Rails suites need
`rails ~> 8.1` and `sqlite3` as **local** gems or they skip to zero
examples while `rspec` still exits 0; and `grep` in some shells here is a
`ugrep` wrapper that silently skips binary files.

### A twelve-line reproduction of the `include` case

Added after the briefing was written, because a minimal reproduction is
worth more than 213 files. This is a **fact**, not a diagnosis: it shows
what the ancestor walk returns, and stops there.

```ruby
module Rackish
  module Helpers
    def helper_method; end
  end

  class Request
    include Helpers
    def call = helper_method
  end
end
```

`HierarchyIndex#ancestors("Rackish::Request", singleton: false)` returns:

```
::Rackish::Request  synthesised=false
Object              synthesised=true
Kernel              synthesised=true
BasicObject         synthesised=true
```

`Helpers` is absent. The chain still reaches `BasicObject`, every entry
present is `ancestor_known?`, none declares `method_missing`, and none is
reopened elsewhere — so `closed_nominal?` returns true and the check
reports `helper_method` as undefined on a class that plainly has it.

What this establishes: an `include` can be missing from the chain while
every test `closed_nominal?` applies still passes. What it does **not**
establish: that this accounts for the 12 findings in that category, or
that resolution is where the fix belongs.

## 4. The code

### `Diagnostics::Engine#unknown_method_findings`
`core/lib/ovallsp/diagnostics/engine.rb:102`

Reports only when the receiver's type is a single `Types::Nominal` whose
ancestor chain is judged **closed**. Everything rests on that judgement.

### `Diagnostics::Engine#closed_nominal?`
`core/lib/ovallsp/diagnostics/engine.rb` (search the name)

```ruby
def closed_nominal?(nominal, singleton, context)
  entries = context.hierarchy_index.ancestors(nominal.name, singleton: singleton)
  return false if entries.empty?
  return false unless chain_reaches_root?(context.hierarchy_index.ancestors(nominal.name, singleton: false))
  return false unless entries.all? { |entry| ancestor_known?(entry, context) }
  return false if entries.any? { |entry| declares_method_missing?(entry.name, context) }

  entries.none? { |entry| !entry.synthesised? && reopened_elsewhere?(entry.name, context) }
end
```

### `Semantic::HierarchyIndex#instance_ancestors_locked`
`core/lib/ovallsp/semantic/hierarchy_index.rb:231`

```ruby
@includes_by_owner.fetch(canonical, []).reverse_each { |fact| entries.concat(ancestor_entries_for(fact, visited)) }
```

`canonical_name` (`:191`) is `@workspace_index.resolve_type_name(name) || name.to_s` —
its own comment says it falls back to the written name "rather than
refusing to resolve", and points at `024.47`.

### Design constraints these must respect

- `docs/design/tasks/015-confidence-aware-diagnostics.md`: **誤検出率を最優先**
  — the false-positive rate is the top priority, above catching
  everything. A missed report is acceptable; a wrong one is not.
- `024.13`: container receivers are deliberately **not** normalised here,
  because a workspace reopening a core class made its chain look closed
  while gems kept adding to it — `[1,2].second` (ActiveSupport, absent
  from stdlib RBS) was reported as unknown.
- The `ActiveSupport::TestCase` case, in `closed_nominal?`'s own comment:
  asking only about the receiver made every `class FooTest <
  ActiveSupport::TestCase` report the whole gem's API as unknown.

## 5. Hypotheses — to be refuted, not built on

Marked because this document's author has had a causal claim disproved
once already this release.

- **H1:** `closed_nominal?` treats "every ancestor I could find resolved"
  as "the ancestor list is complete". A bare-named module referenced from
  inside a nested namespace fails to resolve, contributes no entry, and
  the chain is then judged closed *without it*. If true, the check is
  confidently reporting about a receiver whose method set it does not
  know.
- **H2:** the metaprogramming cases (31 of 54) are a different failure:
  the chain really is complete, and the methods are simply not in it. If
  so, no improvement to resolution helps them, and they need a distinct
  answer — possibly "a class whose body contains an unrecognised
  class-level call is not closed".
- **H3 (weakest):** the recall gap and the precision gap are the same
  defect seen from both sides — the diagnostic path and completion do not
  ask the type engine the same question.

## 6. What is actually being asked

**Q1.** `closed_nominal?` must decide whether a receiver's method set is
fully known. What is a sound structure for that decision, given that
"unresolved" and "absent" are currently indistinguishable in the ancestor
walk? An answer that makes the check silent more often is acceptable —
by section 0.4 and by 015's stated policy, silence beats a wrong report.
An answer that requires the resolution to become perfect first is not
useful, because that is `024.47` and it is a separate, larger task.

**Q2.** Diagnostics and completion demonstrably have different answers at
the same position — completion knows `tracking_label` is absent, the
check does not report it. What is the right shape for them to ask one
question? Note that a previous attempt to unify a rule of this kind was
**rolled back**: 0.2.1 moved a type-name shadowing rule into resolution
and broke every bare name written inside its own namespace (`024.47`).
And 0.1.12 restructured for its own sake, made zero net progress across
four review rounds, and was rolled back entirely (`024.15`). A proposal
that does not say what it would cost and what would be lost cannot be
weighed against those.

## 7. What a useful answer looks like

- Names the mechanism, in terms of the code above, and says which of
  H1–H3 it refutes.
- Proposes a structure, with **what would be lost** stated explicitly.
- Says what would have to be true for the proposal to be the wrong shape.
- Distinguishes what is 0.2.6-sized from what is not. This release is a
  patch: no capability row moves, and section 0.4 says shipping matters.
- Prefers making the check *honest* over making it *clever*. 53 wrong
  reports out of 54 means, by this project's own standard, that the check
  is currently worse than its own absence.
