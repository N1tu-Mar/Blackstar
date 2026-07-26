# Branch: `red-calibration-and-setup-strikes`

Three additions to the adversary. Nothing else moves.

**BLUE is untouched.** So is redaction — none of this shows RED anything it could
not already see, and `redact_for_red` still strips island membership. Every
change is additive: existing fields keep their meaning, and every new field has
a default, so `main`'s behaviour is unchanged if you ignore them.

---

## Why these three

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
| `grid/model.jac` | `Strike.immediate_damage`; `Scenario.predicted_endurance_hours`; `Outcome.prediction_error_hours`; `Round` forecast/actual; `Informed` edge; sems |
| `grid/red.jac` | `ScenarioDraft` gains two parallel arrays + sems; `plan` zips them; `measure` takes `predicted` and computes the gap |
| `grid/prov.jac` | `link_lessons`, `why_round` |
| `endpoints.sv.jac` | records forecast/actual on the round, links lessons when memory is on |
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
