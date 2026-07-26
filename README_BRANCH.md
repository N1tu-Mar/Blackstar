# Branch: `red-calibration-and-setup-strikes`

**The headline is the advisor** (§0). The other three are supporting evidence
for the same argument.

**BLUE is untouched.** So is redaction — none of this shows RED anything it could
not already see, and `redact_for_red` still strips island membership. Every
change is additive: existing fields keep their meaning, and every new field has
a default, so `main`'s behaviour is unchanged if you ignore them.

---

## ⚠️ This adds a THIRD LLM call

Main's README states: *"Two LLM calls exist in the entire system, both in
`grid/red.jac`."* **That sentence is no longer true on this branch** and must be
updated on merge, or the pitch misrepresents the build.

The accurate framing is three calls across three roles:

| Role | Calls | File |
|---|---|---|
| RED — attacks | `draft_scenario`, `reflect_on` | `grid/red.jac` |
| BLUE — decides who loses power | **none, ever** | `grid/blue.jac` |
| ADVISOR — recommends what to build | `draft_hardening` | `grid/advisor.jac` |

This is arguably a *better* pitch than "two calls": it names where intelligence
belongs and where it is banned. **The load-shedding invariant is untouched** —
the advisor is read-only, never writes to the grid, never sheds, never switches.
It reads a finished campaign and returns prose for a human.

---

## 0. The advisor — wargame becomes work order

**The gap this closes:** the project generates attacks but never synthesized a
defense. The pitch calls it a resilience *planning* tool; the output was attack
transcripts and an explain chain. The customer — the engineer who has to file the
§2925 report — needs the inverse.

New endpoint `GetHardeningPlan`, new file `grid/advisor.jac`, runnable via
`scripts/harden.jac`.

The split is the same one the rest of the system uses:

- **Ranking is arithmetic.** A walk over `Run → HasRound → Round → Struck →
  Event`, grouping landed strikes by element. No model. There is nothing for a
  model to add to counting.
- **The recommendation is world knowledge.** "Elizabeth River Substation is your
  most-implicated element" falls out of arithmetic. "Back-feed the critical wing
  from the north campus bus and raise the switchgear above the surge stage" does
  not — it needs to know what mitigations exist for a flood-exposed substation,
  and that is nowhere in this graph.

`scripts/harden.jac` prints the two halves **separately and labelled**, so a
judge can see which is countable and which is generated.

### An honesty constraint worth defending out loud

All strikes in a round land on one tick, so the graph cannot say *which* strike
did the damage — only that an element was hit in a round that ended badly. The
code says `implicated in`, never `caused`, and the `sem` tells the model not to
assert a causal chain the evidence does not carry. `Vulnerability`'s docstring
states this too.

If a judge pushes on "isn't that just correlation?" — yes, and it is labelled as
correlation everywhere it appears. That is the correct answer, and it is stronger
than a causal claim the data cannot support.

The arithmetic also overrides the prose: if the model names a single point of
failure that is not on the ranked list, the code discards it and uses the top of
the ranking.

---

## Why the other three

The project already argues that RED reasons rather than looks things up, and it
argues it two ways: the unprompted fuel-interdiction chain ("trucks need roads"),
and the memory A/B separating. Both are strong. Both are also *narrative* — a
judge has to take the transcript on trust.

These three make the same argument in ways you can point at on screen.

---

## 1. RED commits a forecast (calibration)

`Scenario` carried `expected_effect` as prose. Prose cannot be checked.

RED now also commits `predicted_endurance_hours` **before** the chain runs.
`Outcome.prediction_error_hours` carries the absolute gap against what the
arithmetic actually returned.

Why this is evidence and not decoration: RED forecasts from a view with the
conductors *and* island membership stripped out. Landing close means it holds a
working model of a facility it has never been shown. **A near miss is stronger
evidence than a hit** — a lookup against an oracle would not produce one.

In the round feed:

```
RED predicted 38.0 h, measured 41.2 h (off by 3.2 h)
```

`-1.0` means no forecast was offered, and the line is hidden rather than shown
as a perfect score.

## 2. Setup strikes are named

`Strike` gains `immediate_damage`: `none` / `partial` / `severe` — the cost of
that strike **by itself**, ignoring what it enables later.

The `sem` tells RED plainly that a strike doing nothing on its own, but
stripping the redundancy a later strike depends on, is a legitimate and often
superior move — and that a search scoring each strike in isolation can never
find it.

This behaviour *already appeared unprompted*: round 2 cutting the CEP tie before
the river feed is exactly this shape. What was missing is that nothing **named**
it, so a judge watching the feed could not tell that the harmless-looking move
was the one that mattered. Now it renders as:

```
-> cyber_switching on CEP Bus Tie - no damage on its own
```

An unlabelled strike defaults to `severe`, so a short array from the model is
never mistaken for a deliberate setup move.

## 3. RED's moves cite their cause

Invariant 5 says every decision is a node with edges to its evidence. That held
for BLUE — a `Decision` points at the `Finding` that justified it — but **RED's
moves had no recorded cause at all**.

New edge `Informed: LessonNode --> Round`, written when a lesson was in RED's
context as it planned. `why_round(rnd)` walks them back, oldest first.

With memory **off**, no edge is written. So the A/B is now legible on the graph
itself, not only in the endurance totals.

---

## What changed

| File | Change |
|---|---|
| `grid/advisor.jac` | **new** — ranking (arithmetic) + `draft_hardening` (the third call) |
| `scripts/harden.jac` | **new** — campaign, then the plan, halves printed separately |
| `grid/model.jac` | `Vulnerability`, `HardeningPlan`; `Struck` edge; `Round` opening endurance + `tier1_stranded`; `Strike.immediate_damage`; `Scenario.predicted_endurance_hours`; `Outcome.prediction_error_hours`; `Informed` edge; sems |
| `grid/red.jac` | `ScenarioDraft` gains two parallel arrays + sems; `plan` zips them; `measure` takes `predicted` and computes the gap |
| `grid/prov.jac` | `link_lessons`, `why_round` |
| `endpoints.sv.jac` | `GetHardeningPlan`; records forecast/actual/opening/tier1 on the round; links lessons when memory is on; passes the round into `execute` |
| `grid/red.jac` (exec) | `execute` takes the round and links **landed** strikes via `Struck` — refused and unresolved strikes are never linked, so they cannot score |
| `components/RoundFeed.cl.jac` | calibration line, setup-strike marker |

Parallel `list[str]` arrays rather than a nested `list[Obj]`, per the byLLM
constraint documented in the main README.

---

## Verification status — read this before demoing

**Type-checked, not run.**

`jac check .` gives **15 passed / 2 failed — identical to clean `main`**, same
error counts. The `campus.jac` and `basemap.jac` failures are **pre-existing on
this checkout** and come from an older toolchain (PyPI `jaclang` 0.16.7 vs the
team's Jac 0.34.5), not from these changes. All five touched files pass with
zero errors.

**Runtime is not verified here.** It needs the team's Jac 0.34.5 and an
`ANTHROPIC_API_KEY`. Before trusting the calibration line on stage:

```bash
set -a && . ./.env && set +a
jac run scripts/redloop.jac
```

Two things to confirm on that run:

1. **RED returns a sensible number** for `predicted_endurance_hours`. If it comes
   back `0.0` every round, the field is not reaching the schema — check it is
   declared on `ScenarioDraft` in `red.jac` and not imported.
2. **At least one strike is labelled `none`.** If every strike says `severe`,
   the model is ignoring the setup-strike guidance and the `sem` needs
   sharpening. That is a prompt-contract fix, not a code fix.

Then re-run `scripts/ab.jac` to confirm the A/B still separates — these changes
should not affect it, but the A/B is the load-bearing claim and it is cheap to
re-confirm.

For the advisor specifically:

```bash
jac run scripts/harden.jac
```

Three things to confirm:

3. **The ranking is non-empty.** If it is, `Struck` edges are not being written —
   check `execute` is receiving the round.
4. **The measures are things a contractor could build**, not "improve
   resilience" or "monitor more closely". If they come back vague, sharpen
   `sem HardeningDraft.measures` — a prompt fix, not a code fix.
5. **The single point of failure matches the top of the ranking.** If it silently
   differs, the override in `hardening_plan` is doing its job and the model is
   naming something off-list — worth knowing.
