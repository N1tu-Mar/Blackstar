# The filing, and the bound

Two additions. Both are **additive** — three new files plus small appends to
`endpoints.sv.jac` and the console. `grid/blue.jac`, `grid/red.jac`,
`grid/model.jac`, `grid/islands.jac`, `grid/prov.jac` and `grid/campus.jac` are
untouched, so nothing in the verified core moved and Ayaan's RED branch does not
conflict.

Everything below was **run**, not just type-checked. `jac check .` is clean
(20 passed, 0 errors) on jac 0.34.7.

---

## 1. `grid/report.jac` — the mandated filing

Invariant 5 gives two reasons the provenance chain exists: the "ask why" demo,
and *the compliance product wedge*. The first was built. This is the second.

Before this, §2925 and CMS appeared in the repo exactly twice: one README
sentence and a `"blurb"` string in `scripts/extract_site.py`. The pitch asserted
the wedge; nothing produced the artifact. Now a run projects into the filing a
facility is legally required to file, with every line citing the archive node it
was read from — the same `[f77a6]` refs `explain` prints, so a reviewer can walk
any determination back to the event that caused it.

Six sections, each tagged with the statute it answers: determination, mission
impact, curtailment actions, sequence of events, adversarial exercise record,
and basis of determination. No generated prose anywhere — an LLM in this path
would make the filing an assertion *about* the run instead of a projection *of*
it.

Verified output from `jac run scripts/report.jac` (no API key needed):

```
**Determination:** DOES NOT MEET the 96-hour requirement
**Worst assessed endurance:** 76.1 h (19.9 h shortfall)
**Scope:** 27 elements, 2590 kW connected load, 770 kW curtailed

## 3. Load curtailment actions
*10 U.S.C. 2925(a)(3) - load the installation would curtail to sustain the mission*

- `[d700b]` step 1  t=3  shed Galley and Food Service - tier 3 load, island endurance 76.1 h below 96 h target
- `[f77a6]`         derived from: island 3 at 76.1 h against 96 h
- `[d1aef]` step 5  t=3  shed Radiology and MRI - tier 2 load, island endurance 76.1 h below 96 h target
```

One thing worth keeping: the filing separates *the worst state reached* from
*the final state*. BLUE recovers Portsmouth to 108.3 h, but the site passed
through 76.1 h to get there, and section 2 says so explicitly rather than
reporting a clean run. A filing that can only conclude "compliant" is not
evidence of anything.

**API:** `GenerateReport`, `GetReportMarkdown`, `GetReportLines`.
**UI:** *File the legal report*.

---

## 2. `grid/oracle.jac` — the adversary with no model in it

The hardest question this project gets is the one its own pitch notes
anticipate: *why do you need an LLM? To pick a cable, a loop does that better.*

The answer has been prose. ORACLE makes it a measurement. It is a deterministic
beam search over strike chains using the **same** mechanisms as RED, the **same**
plausibility gate, and the **same** arithmetic evaluator — handed two things RED
never gets: the unredacted element list, and unlimited rehearsals.

So ORACLE is not a realistic adversary. It is an **upper bound on achievable
damage**, and the number that matters is the ratio RED reaches against it from a
redacted dashboard with one model call per round. `compare(red_endurance, strikes, beam)`
returns that.

Read honestly in both directions, and note what the bound cannot say: ORACLE
emits `flood:X -> fuel:Y` and nothing else. No hazard, no coherence, no account
of itself. It cannot be briefed to a commander or used to write section 5 of a
filing. The chain is the cheap half of an exercise.

Two properties it must keep, both enforced:

- **It writes nothing to the archive.** Dry-runs call `run_blue` directly, never
  `blue_pass` or any `record_*`, so hypothetical futures cannot contaminate an
  audit trail meant to describe what really happened.
- **Every dry-run is exactly undone.** `scripts/oracle.jac` ends by diffing a
  snapshot taken before the search against one taken after. That check is why
  this is safe to click mid-demo.

### It found a one-strike kill

From `jac run scripts/oracle.jac` (no API key, ~30 s):

```
plausible single strikes: 119

=== worst single strike  (119 chains simulated) ===
  cyber_switching:North Campus Switchgear
  endurance 999.0 h -> 0.0 h   islands=3   tier1_stranded=True

=== campus design check ===
  ONE-STRIKE KILL: 'cyber_switching:North Campus Switchgear' strands
  life-critical load on its own.

=== restore check ===
  clean: grid identical after 928 dry-runs
```

This matters for the A/B. The README already records that one null result was
caused by a one-strike kill through the plant bus, fixed by sectionalizing it.
**A second one still exists** — `cyber_switching` on North Campus Switchgear
opens every breaker at that node and strands tier 1 by itself, and a two-strike
chain buys the adversary nothing beyond it. If a round can end the campaign in
one move, RED has nothing left to learn and both arms of the A/B saturate.

That question — *does this campus admit a one-strike kill?* — previously had to
be discovered by observing a null A/B twice. It is now a script that runs in
seconds without an API key.

**API:** `RunOracle(depth, beam)` — clamped to depth ≤ 3, beam ≤ 12 so one click
cannot park the request thread.
**UI:** *Worst attack, no AI*.

---

## Notes for whoever picks this up

- **`grid/blue.jac` was left alone**, per the README. Worth knowing that
  `Conductor.normally_open` is set by `campus.jac`, drawn by `GridMap`, and never
  read by BLUE — the tie switches are on the map and BLUE cannot close one.
  Reconfiguration (which tie to close to re-form islands around surviving
  generation) is the Option B in the pitch notes, and ORACLE's snapshot/restore
  is the machinery it would need. Deliberately not attempted mid-hackathon.
- **Avoid block-bodied lambdas in `grid/` modules.** Four in one module produced
  `name '__jac_lambda_1' is not defined` at runtime on 0.34.7 while
  type-checking clean. Named key functions are used instead. `prov.jac`'s two
  still work, so this only bites as you add more.
- **`RED` still has no offline path.** `grid/red.jac:36` hardcodes
  `Model(model_name="claude-sonnet-5")` with no fallback, so a missing key, a
  rate limit or venue wifi kills the two beats the pitch rests on. Both scripts
  added here run without a key, which makes them the demo of last resort, but
  they are not a substitute for fixing that.
