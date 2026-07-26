# BLACKSTART

A live model of a hospital's electrical survival, in Jac.

Naval Medical Center Portsmouth is a hospital — ICUs, operating rooms, ventilators — **and** a DoD installation. One building, two mandates: the CMS emergency preparedness rule and 10 U.S.C. §2925 energy-resilience reporting. Both require knowing how long the mission survives without power. Today both are answered by hand, weeks later, from SCADA logs.

The campus is a graph. When elements fail it fractures into electrical islands, each counting down its own hours of endurance. A deterministic controller sheds load by tier until endurance clears the 96-hour target. An LLM adversary writes the failure scenarios, learns from what survived, and attacks smarter. Every decision is a node you can walk back to.

---

## Quickstart

```bash
cp .env.example .env        # add your ANTHROPIC_API_KEY
jac install
set -a && . ./.env && set +a
jac start --dev main.jac
```

> **Do not run a script and the dev server at the same time.** They share `.jac/data`, and both will be writing the same graph.

> **The `set -a && . ./.env` step is not optional.** `.env` autoload is unreliable in this Jac build; without it every `by llm()` call dies with a bare `AuthenticationError`.

Type-check everything with `jac check .` before you push.

Two runnable scripts prove the system without the UI:

```bash
jac run scripts/demo.jac      # the pitch demo: cuts, shedding, "why did the Galley go dark"
jac run scripts/redloop.jac   # two full RED rounds with memory (~90 s, 4 LLM calls)
jac run scripts/ab.jac        # the A/B: memory on vs off, 3 rounds each (~5 min, 12 LLM calls)

# These two need no API key and make no network call:
jac run scripts/report.jac    # the mandated §2925 / CMS filing, generated from the run graph
jac run scripts/oracle.jac    # the model-free damage bound + a one-strike-kill check (~30 s)

# Refresh the frozen basemap (needs network; do NOT run this on demo day)
python3 scripts/fetch_basemap.py
```

---

## Putting it on the internet

BLACKSTART deploys to **JacHammer** as one application - the same
`jac start main.jac` that runs locally, serving the API and the console from a
single origin. No split, no separate frontend host, no compiled-in API URL.

Set `ANTHROPIC_API_KEY` in the project's environment settings, run a preview to
confirm it boots, then deploy. See **[DEPLOY.md](DEPLOY.md)**.

---

## What is actually working right now

| Piece | File | Status |
|---|---|---|
| Grid data model, all node/edge/obj types | `grid/model.jac` | ✅ done, type-checks |
| 27-element NMCP campus fixture | `grid/campus.jac` | ✅ done, verified numbers |
| Emergent islanding + endurance math | `grid/islands.jac` | ✅ done, verified |
| BLUE deterministic load shedding | `grid/blue.jac` | ✅ done, verified |
| Provenance archive + backward `explain` | `grid/prov.jac` | ✅ verified, cited chain walks to root cause |
| RED adversary (`plan` / `reflect`) | `grid/red.jac` | ✅ verified live, both calls, with memory |
| Public walker API | `endpoints.sv.jac` | ✅ verified via `scripts/demo.jac` |
| Operator console + campus map | `frontend.cl.jac`, `components/GridMap.cl.jac` | ✅ verified in-browser, over real OSM geography |
| Memory A/B | `scripts/ab.jac` | ✅ separates — memory kills a round earlier |
| Mandated §2925 / CMS filing, cited to the archive | `grid/report.jac` | ✅ verified by run, no API key needed |
| ORACLE: model-free damage bound + campus design check | `grid/oracle.jac` | ✅ verified by run, no API key needed |

**The simulation core is verified end to end.** This cascade was produced by an actual run, not by hand:

| State | Site endurance | What happened |
|---|---|---|
| Baseline, both utility feeds up | grid-backed | one island |
| Hurricane takes both utility feeds | **76.1 h** | under the 96 h target |
| BLUE sheds 4 × tier-3, then Imaging | **108.3 h** | clears, holds |
| Round 2 — CEP tie cut *first*, then the river feed | **1.1 h** | two islands, critical wing isolated |
| BLUE sheds all remaining tier-2 | **4.1 h** | `breach = True`, nothing left to shed |

Round 2 is a genuine unrecoverable breach with tier-1 stranded, and it falls out of arithmetic — nobody scripted it.

RED's reasoning is the part that cannot be scripted. Unprompted, round 1 produced this chain: flood the river substation, flood CEP Generator 1 — then **fuel-interdict Generator 2, because the access roads are flooded**. "Trucks need roads" appears in no electrical dataset. The plausibility gate then refused to flood a switchgear sitting at 6.5 m against a 4.0 m surge stage, and REFLECT wrote back:

> "Elevation and flood-susceptibility must be verified per-asset rather than assumed from proximity to a river — North Campus Switchgear is elevated and immune to the modeled surge."

## Does the memory actually help?

Yes, and it took three runs to earn that answer honestly.

| | round 1 | round 2 | round 3 | total held | first kill |
|---|---|---|---|---|---|
| **memory ON** | 100.6 h | **0.0 h** | 0.0 h | **100.6** | **round 2** |
| memory OFF | 100.6 h | 44.0 h | 0.0 h | 144.6 | round 3 |

Remembering RED stranded critical care a full round earlier and held the site 44 hours lower.

The first two runs came back null, and both nulls were real defects rather than a flat result:

1. **A one-strike kill.** Both CEP generators fed only through the plant bus, so a single `equipment_failure` orphaned 3000 kW. RED found it in round 1 of both arms and the site bottomed out immediately. Fixed by sectionalizing the bus.
2. **The dashboard was leaking the answer.** RED could see island *membership* every round — "these fourteen elements are electrically together" is most of the wiring diagram, handed to both arms for free. A memoryless RED performed exactly as well as a remembering one. `redact_for_red` now strips membership and island IDs, so a Lesson is the only place structural knowledge can accumulate.

If you re-run it and the arms come out level again, suspect the second failure mode first: something in the view is telling RED what it should have had to learn.

---

## Any grid, not just Portsmouth

A site is data. The simulator contains no knowledge of any particular campus:
islanding, endurance, BLUE, the provenance chain and RED are all site-agnostic,
and `grid/campus.jac` is a loader rather than a fixture.

Switch sites from the picker at the top of the console, or pin one at boot:

```bash
BLACKSTART_SITE=<id> jac start --dev main.jac
```

Two ship with the repo — **Naval Medical Center Portsmouth** (coastal, storm
surge) and **Walter Reed, Bethesda** (inland, creek and stormwater flooding,
its own flood stage in local elevation terms). Each has its own graded
cascade: Portsmouth 76.1 → 108.3 h, Walter Reed 74.1 → 91.2 → 106.3 h.

Adding a third is one JSON file plus one command:

1. Write `data/sites/<id>.json` — elements, conductors, the render window, the
   mandated endurance target, and the local flood stage.
2. `python3 scripts/fetch_satellite.py <id>` — reads the view box out of your
   JSON, so imagery and projection cannot drift apart.
3. `BLACKSTART_SITE=<id> jac start --dev main.jac`.

Schema and guidance on what makes a site worth simulating are in
[`data/sites/README.md`](data/sites/README.md). The short version: the
topology needs a redundant path, generation that is not a single point of
failure, a spread of elevations, and roughly 20–30 elements — otherwise RED
has nothing to discover and the memory A/B has nothing to measure.

What is *not* portable is the tier assignment. Deciding that the ICU is tier 1
and the galley is tier 3 is a judgement a facility's own engineers make, and
it is the input the whole defence rests on. The tool computes consequences of
that list; it does not author it.

Two additions layered on top of the core, both additive and both runnable without a
model: the mandated filing that invariant 5 promises, and a deterministic adversary
that measures what RED's model actually buys. See
[`ORACLE_AND_REPORT.md`](ORACLE_AND_REPORT.md) — including the one-strike kill it
found on the current campus.

---

## Design invariants

Do not break these. Each one is load-bearing for the argument the project makes.

1. **No LLM in the load-shedding path.** BLUE is arithmetic and a sorted list. Nobody accredits a language model to de-energize an ICU. `grid/blue.jac` is ~20 lines; it is done, leave it alone.
2. **RED sees nodes, never edges — and never island membership.** `Dashboard` carries element names, kinds, tiers, lit/dark status, how many islands formed and how bad endurance is. It carries **no conductors and no island grouping** (`redact_for_red` in `grid/red.jac` strips both before RED plans; the UI is never redacted). If RED can enumerate the wiring, a `for` loop replaces it and the whole premise dies. Membership is the subtler leak: handing over "these fourteen things are electrically together" is most of the wiring diagram, delivered fresh every round, which lets a *memoryless* RED perform as well as a remembering one. Redaction is what makes a Lesson the only place structural knowledge accumulates.
3. **Islanding is emergent, never computed.** There is no connected-components routine anywhere in this repo. `Energize` is filtered to passable conductors, so a cut edge is not one it declines to take — it is one it cannot see.
4. **REFLECT is mandatory.** Round *N+1* receives a *sentence*, not a scalar. A number makes this hill-climbing, which needs no model.
5. **Every decision is a node with edges to its evidence.** No log files. The `explain` chain is the product.
6. **No database.** `root ++> x` is the entire persistence story.

---

## Architecture

```
main.jac              entry — wires server API to client
endpoints.sv.jac      public walkers: /walker/<Name>
grid/
  model.jac           nodes, edges, view objs      ← shared contract, coordinate changes
  campus.jac          the 27-element NMCP fixture  ← shared fixture
  islands.jac         Energize walker + endurance
  blue.jac            deterministic shedding       ← DONE, do not touch
  red.jac             dashboard, resolver, plausibility gate, plan/reflect
  prov.jac            tick/event/finding/decision chain + explain
frontend.cl.jac       operator console
frontend.impl.jac     handler bodies
components/           client components
```

Two LLM calls exist in the entire system, both in `grid/red.jac`: `draft_scenario` and `reflect_on`. Everything else is arithmetic.

---

## Jac 0.34.5 gotchas — found the hard way

This build differs sharply from the `jaclang` Python package most docs describe. These cost real hours; read them before writing code.

**byLLM**

- **A `glob llm: Model = Model(model_name="...")` is required.** The ambient model from `jac.toml`'s `[byllm.model] default_model` resolves to `None`, and every call dies with a bare `'NoneType' object has no attribute` — no stack, no hint. See the top of `grid/red.jac`.
- **A `by llm()` return type must be declared in the SAME module as the function.** An imported obj resolves to its name *string* in the schema walker: `'str' object has no attribute 'fields'`. This is why `ScenarioDraft` and `LessonDraft` live in `red.jac` and are copied into the shared `model.jac` types.
- **No nested `list[Obj]` on a `by llm()` return type.** Same crash. RED emits parallel `list[str]` arrays and `plan` zips them into typed `Strike`s.
- **Claude 5 rejects `temperature`.** `by llm(temperature=0.2)` fails at runtime with `temperature is deprecated for this model`. Removed from `jac.toml` and every call site.
- Use `sem`, not docstrings, for anything the model should read.

**Language**

- Function **docstrings go *before* the `def`**, never inside the body — inside gives a misleading `Missing ';'` (E0002).
- Comments are `#`. `//` is a lexer error.
- Node/edge filters nest as `[root --> [?:Facility]]`. The backtick form `` (`?Facility) `` does not parse here.
- Edge attribute filters need a comparison: `[->:Conductor:passable == True:->]`. A bare `:passable:` crashes the compiler with `'Name' object has no attribute 'left'`.
- `def f() -> X` warns on empty parens — write `def f -> X`.
- Declare edge endpoints (`edge Conductor: GridNode --> GridNode`) or traversals return `Unknown`.
- Use `skip`, not `disengage`, when a walker hits an already-visited node — `disengage` abandons sibling branches and silently truncates the island.

**Tooling**

- `jac clean --all` removes the venv and does **not** reliably restore the byLLM capability afterward. Prefer `rm -rf .jac/cache`.
- Iterating a list of function references segfaults the runtime. Call them individually.

**Client code (compiles to JavaScript)**

- **Constructing a wire `obj` client-side does not initialize its list defaults.** `MapPaths()` as a state default yielded `iterable is not iterable` at render. Pass flat `list[str]` props instead of an object with list fields.
- **Client modules cannot use project-root imports.** `import from grid.model` compiles but Vite then looks for `./grid/model.js` relative to the component. Use `sv import from ..endpoints { ... }`.
- **JSX comments `{/* ... */}` are a parse error.**

- **`dict.get()`, `min()` and `max()` do not survive compilation to JS.** They yield `NaN` silently — React then renders an empty SVG and only warns in the console. `components/GridMap.cl.jac` uses explicit loops instead. If a chart renders blank, check the browser console for `Received NaN for the ... attribute` before anything else.
- QA the running UI with `jac browse open http://localhost:8002/` → `snapshot` / `console` / `screenshot`. The URL needs its scheme or it navigates to `about:blank`.

---

## Who builds what

Each of these is one file, so nobody blocks anybody.

| Owner | Task | File |
|---|---|---|
| — | **Map polish**: a few labels still overprint where elements sit within ~20 m of each other (Charette UPS / Switchboard A). Wants leader lines or a real label-placement solver. | `components/GridMap.cl.jac` |
| — | **Endurance gauge**: the headline number against the 96 h line, colored on crossing. | `components/EnduranceGauge.cl.jac` |
| — | **BLUE-2 reconfiguration** (stretch): greedy tie-switch closure search maximizing tier-1 kW × endurance. Spec in `TECH_SPEC.md` §7.2. Two `TieSwitch` conductors already exist in the campus. | `grid/blue.jac` |
| — | **Endurance gauge**: the headline number is plain text today. Wants a real gauge against the 96 h line, colour crossing the threshold. | `components/EnduranceGauge.cl.jac` |

Full design rationale, demo script, dataset notes and the business framing are in **`TECH_SPEC.md`**.

---

## API

All walkers are `:pub` — `POST /walker/<Name>`, no auth.

| Walker | Purpose |
|---|---|
| `LoadSite` | Rebuild the campus, clear history. Takes `memory_enabled`. |
| `GetDashboard` | What RED sees, and what the UI shows. |
| `GetMap` | Full topology for rendering. RED never gets this. |
| `RunBlue` | Controller alone, no adversary. |
| `RunRound` | Full LOOK → PLAN → RUN → REFLECT. Two LLM calls. |
| `GetLessons` | RED's accumulated memory. |
| `ExplainWhy` | Cited backward chain for a facility. Takes `subject`. |
| `CutConductor` | Manually open a named conductor. Takes `label`. |

---

## Security

`.env` is gitignored and must stay that way. Rotate the key after the event.
