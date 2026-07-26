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

> **The `set -a && . ./.env` step is not optional.** `.env` autoload is unreliable in this Jac build; without it every `by llm()` call dies with a bare `AuthenticationError`.

Type-check everything with `jac check .` before you push.

---

## What is actually working right now

| Piece | File | Status |
|---|---|---|
| Grid data model, all node/edge/obj types | `grid/model.jac` | ✅ done, type-checks |
| 27-element NMCP campus fixture | `grid/campus.jac` | ✅ done, verified numbers |
| Emergent islanding + endurance math | `grid/islands.jac` | ✅ done, verified |
| BLUE deterministic load shedding | `grid/blue.jac` | ✅ done, verified |
| Provenance archive + backward `explain` | `grid/prov.jac` | ✅ written, type-checks |
| RED adversary (`plan` / `reflect`) | `grid/red.jac` | ⚠️ `plan` verified live; `reflect` needs one more run to confirm |
| Public walker API | `endpoints.sv.jac` | ✅ written, type-checks |
| Operator console | `frontend.cl.jac` | ⚠️ minimal — proves the round trip, needs the map |

**The simulation core is verified end to end.** This cascade was produced by an actual run, not by hand:

| State | Site endurance | What happened |
|---|---|---|
| Baseline, both utility feeds up | grid-backed | one island |
| Hurricane takes both utility feeds | **76.1 h** | under the 96 h target |
| BLUE sheds 4 × tier-3, then Imaging | **108.3 h** | clears, holds |
| Round 2 — CEP tie cut *first*, then the river feed | **1.1 h** | two islands, critical wing isolated |
| BLUE sheds all remaining tier-2 | **4.1 h** | `breach = True`, nothing left to shed |

Round 2 is a genuine unrecoverable breach with tier-1 stranded, and it falls out of arithmetic — nobody scripted it.

`reflect` has been verified in isolation against the live API and produces exactly the reasoning the design needs. Given only an outcome sentence it returned:

> "The actual topology includes at least one additional redundant or interconnecting tie-line that was not accounted for… indicating the grid has more segmentation and redundancy than originally modeled."

---

## Design invariants

Do not break these. Each one is load-bearing for the argument the project makes.

1. **No LLM in the load-shedding path.** BLUE is arithmetic and a sorted list. Nobody accredits a language model to de-energize an ICU. `grid/blue.jac` is ~20 lines; it is done, leave it alone.
2. **RED sees nodes, never edges.** `Dashboard` contains element names, kinds, status, and island grouping. It contains **no conductors**. If RED can enumerate the wiring, a `for` loop replaces it and the whole premise dies. It must hypothesize connectivity — which is also the real adversary's position.
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

---

## Who builds what

Each of these is one file, so nobody blocks anybody.

| Owner | Task | File |
|---|---|---|
| — | **Campus map**: SVG, lat/lon projected, colored by `island_id`, dashed red for damaged conductors. `GetMap` already returns everything you need. | `components/GridMap.cl.jac` |
| — | **Endurance gauge**: the headline number against the 96 h line, colored on crossing. | `components/EnduranceGauge.cl.jac` |
| — | **A/B harness**: two runs, `memory_enabled` true vs false, 3 rounds each, side-by-side endurance counters. `LoadSite` already takes the flag. | new `ab.jac` |
| — | **BLUE-2 reconfiguration** (stretch): greedy tie-switch closure search maximizing tier-1 kW × endurance. Spec in `TECH_SPEC.md` §7.2. Two `TieSwitch` conductors already exist in the campus. | `grid/blue.jac` |
| — | **Round history panel**: `RunRound` already returns a full `RoundResult` with strikes, outcome and lesson. | `components/RoundFeed.cl.jac` |

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
