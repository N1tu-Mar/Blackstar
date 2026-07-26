# BLACKSTART — Technical Specification

**Version** 0.1 (hackathon build spec)
**Target site** Naval Medical Center Portsmouth, Norfolk VA — a military hospital, therefore simultaneously a CMS-regulated healthcare facility and a DoD installation under 10 U.S.C. §2925.
**Stack** Jac (jaclang + byllm) · jac-cloud for serving/persistence · Claude (`claude-sonnet-5`) as the byllm backend · static SPA frontend.

> **Syntax note.** All Jac shown here targets jaclang ≥ 0.8 with byllm. Edge-filter and `by llm()` syntax has churned across releases — verify against the installed version before copy-pasting. The *design* below does not depend on which spelling wins.

---

## 1. One-paragraph statement of the system

BLACKSTART models a hospital campus electrical network as a live graph. When elements fail, the graph fractures into electrical islands — not because we wrote a partitioning algorithm, but because a walker restricted to energized conductors physically cannot cross a de-energized one. Each island computes its own survival time in hours from on-hand fuel and stored energy. A deterministic controller sheds load by tier until endurance clears the mandated target. Every state change, finding, and decision is written to a persistent provenance chain, so any outcome can be walked backward to its cause. An LLM-driven adversary generates the failure scenarios — and only the scenarios — because failure chains depend on world knowledge (floods run downhill, fuel trucks need roads) that is absent from any electrical dataset.

---

## 2. Design invariants

These are load-bearing. Violating any one of them collapses the argument the project is making.

| # | Invariant | Why |
|---|---|---|
| I1 | **No LLM in the load-shedding path.** BLUE is arithmetic and a sorted list. | Accreditability. Nobody certifies a language model to de-energize an ICU. This is the sentence that makes the rest of the system trustworthy. |
| I2 | **RED never sees topology.** It sees a dashboard: facility names, lit/dark, hours remaining, island count. Never edge lists, never node IDs, never adjacency. | If RED can enumerate edges, a `for` loop replaces it and the entire premise dies. It must *hypothesize* structure — which is also the real adversary's epistemic position. |
| I3 | **Islanding is emergent, never computed.** No connected-components function exists in the codebase. | This is the Jac demonstration. Traversal restricted by edge predicate *is* the algorithm. |
| I4 | **Exactly two LLM calls per round: PLAN and REFLECT.** | Everything else is arithmetic. Also keeps latency budget survivable on stage. |
| I5 | **REFLECT is mandatory, not optional.** Round *N+1* receives a *sentence*, not a scalar. | A scalar makes this hill-climbing, which needs no LLM. The natural-language lesson is the only thing that makes it an agent rather than a search. |
| I6 | **Every decision is a graph node with edges to its evidence.** No log files. | The "ask why" demo, and the compliance product wedge, are both this. |
| I7 | **No database.** `root ++> x` is the entire persistence story. | Jac differentiator; also removes an entire class of demo-day failure. |

---

## 3. Scope

**In scope**
- Topological energization: is this element connected to a source through closed, undamaged conductors?
- Island formation and dissolution as elements open/close.
- Energy-budget endurance (kWh available ÷ kW served), per island.
- Tier-based load shedding to a target endurance.
- Optional (stretch): tie-switch reconfiguration search.
- Full provenance chain and backward explanation.
- Adversarial scenario generation with cross-round memory.

**Explicitly out of scope** — say this to a judge before they ask.
- AC power flow. No voltage, no phase angle, no reactive power, no thermal limits. We solve *connectivity* and *energy budget*, not load flow.
- Protection coordination, relay timing, arc-flash.
- Live SCADA/DNP3 ingest. The demo replays a scenario against a static topology.
- Restoration sequencing / true black-start ordering (name notwithstanding).

Stating these up front converts "your model is simplified" from a gotcha into a design choice.

---

## 4. Data model

### 4.1 Nodes

```jac
node Element {
    has name: str;
    has kind: str;             # "bus" | "facility" | "generator" | "battery" | "substation"
    has lat: float;
    has lon: float;
    has elevation_m: float;    # gates flood-mechanism plausibility
    has energized: bool = True;
    has island_id: int = -1;
}

node Facility(Element) {
    has tier: int;             # 1 = never shed, 2 = shed under duress, 3 = shed first
    has kw: float;             # nominal demand
    has category: str;         # "icu" | "surgical" | "ed" | "ward" | "imaging" | "admin" | ...
    has shed: bool = False;    # de-energized BY BLUE, distinct from de-energized by damage
}

node Generator(Element) {
    has kw_rating: float;
    has fuel_gal: float;
    has online: bool = True;
    has fuel_reachable: bool = True;   # false => no resupply (road interdiction)
}

node Battery(Element) {
    has kwh_stored: float;
    has kwh_capacity: float;
    has max_kw: float;
}

node Substation(Element) {
    has kv: float;
    has utility_source: bool = False;  # true = grid tie; dead once the utility is lost
}
```

### 4.2 Edges

```jac
edge Conductor {
    has closed: bool = True;
    has damaged: bool = False;
    has ampacity_kw: float;
    has label: str;            # human name; never exposed to RED
}

edge TieSwitch(Conductor) {
    has normally_open: bool = True;   # closed only by BLUE-2 reconfiguration
}
```

**The energized predicate is the whole engine:** a conductor is traversable iff `closed and not damaged`. Cut it and the walker simply cannot reach the far side. That is the "splitting algorithm."

### 4.3 Provenance nodes

```jac
node Run      { has site: str; has memory_enabled: bool; has started_tick: int; }
node Round    { has index: int; has scenario_name: str; has hazard: str; }
node Tick     { has t: int; has site_endurance_hours: float; has island_count: int; }
node Event    { has t: int; has kind: str; has target: str; has detail: str; }
node Finding  { has t: int; has island_id: int; has endurance_hours: float;
                has target_hours: float; has breach: bool; }
node Decision { has t: int; has action: str; has subject: str; has rule: str; }
node LessonN  { has round: int; has text: str; has confidence: float; }
```

### 4.4 Provenance edges

```jac
edge Next;        # Tick -> Tick, temporal spine
edge AtTick;      # Event | Finding | Decision -> Tick
edge Caused;      # Event -> Event  (cascade: flood -> road out -> gen dry)
edge Because;     # Decision -> Finding
edge DerivedFrom; # Finding -> Tick
edge Affected;    # Decision -> Facility
edge Learned;     # Round -> LessonN
edge Informed;    # LessonN -> Round   (which lesson shaped which later round)
```

The explanation walk is `Decision -Because-> Finding -DerivedFrom-> Tick <-AtTick- Event -Caused-> Event ...`. Every line of the rendered narrative carries the ID of the node it came from. That is the Sentinel "cited case file" pattern applied to outages.

### 4.5 Root attachment

```jac
with entry:__main__ {
    run = root ++> Run(site="NMCP", memory_enabled=True, started_tick=0);
}
```

Everything hangs off `Run`. There is no schema migration, no ORM, no connection string. Persistence is reachability from `root`.

---

## 5. Islanding — the emergent partition

```jac
walker Energize {
    has island_id: int;
    has visited: set;

    can spread with Element entry {
        if here in self.visited { disengage; }
        self.visited.add(here);
        here.island_id = self.island_id;
        here.energized = True;
        visit [-->](`?Conductor: closed == True and damaged == False);
    }
}
```

`recompute_islands()` is a fixed ten lines of orchestration, and contains no graph theory:

1. Set `energized = False`, `island_id = -1` on every element.
2. For each `Generator` with `online and fuel_gal > 0`, and each `Substation` with `utility_source` still fed, spawn `Energize` with a fresh island ID *if that source is not already claimed*.
3. Anything still `island_id == -1` after all spawns is dark — no source reaches it.
4. Merge: if a spawn walks into an already-claimed element, the two IDs union (single pass, since sources are few).

There is no `connected_components`, no union-find over the full node set, no BFS we authored. The seed set is "things that make power"; the reachable closure is what the walker can physically touch. **When you cut a conductor mid-demo, nothing in the code notices. The walker just stops.** Say exactly that.

---

## 6. Endurance — the one number on screen

Per island, all arithmetic, no model.

```
GAL_PER_KWH = 0.071          # diesel genset heat rate, industry rule of thumb

load_kw   = Σ facility.kw for energized, non-shed facilities in island
gen_kw    = Σ g.kw_rating   for online generators in island
fuel_gal  = Σ g.fuel_gal    for online generators in island
batt_kwh  = Σ b.kwh_stored  for batteries in island

if load_kw == 0:                     endurance = ∞      # nothing to serve
elif gen_kw == 0:                    endurance = batt_kwh / load_kw
elif gen_kw >= load_kw:              endurance = fuel_gal / (GAL_PER_KWH * load_kw)
else:                                # generation is short; batteries cover the deficit
    gen_hours  = fuel_gal / (GAL_PER_KWH * gen_kw)
    batt_hours = batt_kwh / (load_kw - gen_kw)
    endurance  = min(gen_hours, batt_hours)
```

**Site endurance** — the headline figure — is `min(endurance)` over every island that contains at least one Tier-1 load. This is why stranding the ICU on a generatorless island collapses the number to near zero rather than merely denting it. That collapse is the round-2 money shot, and it falls out of the definition rather than being staged.

**Target** = 96 hours. Defensible from both mandates: CMS emergency-preparedness planning horizons and DoD energy-resilience reporting both live at that scale.

Sanity check against the demo script: an east-wing island serving 180 kW off 500 gal → `500 / (0.071 × 180)` = **39.1 h**, plus a small battery contribution ≈ **41 h**. Under 96. The rule fires. The cafeteria goes dark.

---

## 7. BLUE — the deliberately boring controller

### 7.1 BLUE-1: load shedding (build this first, then never open the file again)

```jac
walker Shed {
    has target_hours: float = 96.0;

    can run with Run entry {
        for island in islands() {
            while endurance(island) < self.target_hours {
                cand = [f for f in facilities(island)
                        if f.tier > 1 and not f.shed and f.energized];
                if not cand { emit_breach(island); break; }
                # highest tier number first; within a tier, biggest kW first
                victim = sorted(cand, key=|f| (-f.tier, -f.kw))[0];
                victim.shed = True;
                record_decision(action="shed", subject=victim.name,
                                rule=f"tier {victim.tier} <= target {self.target_hours}h");
            }
        }
    }
}
```

Roughly twenty lines. Hard constraints: **Tier 1 is never shed** — if the loop exhausts tiers 2 and 3 and endurance is still short, it emits an `EnduranceBreach` and stops. That honest failure state is what makes round 2 land; a controller that always succeeds proves nothing.

Tiering for NMCP:
- **Tier 1** — ICU, operating suites, emergency department, ventilator wards, fire pump, life-safety egress, network core / comms.
- **Tier 2** — inpatient wards, imaging, pharmacy, clinical lab, sterile processing, elevators.
- **Tier 3** — administration, cafeteria, retail, exterior lighting, non-critical HVAC, parking structures.

### 7.2 BLUE-2: reconfiguration (stretch — only if BLUE-1 ships by 12:45)

This is the honest answer to "Blue is too weak." Shedding is a sorted list; **rewiring is combinatorial search over topology**, and it's what real FLISR schemes do, so it isn't invented.

Greedy, deterministic, still no LLM:

```
improved = True
while improved:
    improved = False
    best = None
    for sw in open_tie_switches():
        sw.closed = True; recompute_islands()
        score = Σ over islands of (tier1_kw_served × min(endurance, target))
        if score > current_score + ε: best = (sw, score)
        sw.closed = False
    if best: close(best.sw); recompute_islands(); record_decision("reconfigure", ...); improved = True
```

Objective explicitly weights Tier-1 kW served × endurance, so it prefers landing critical load on surviving generation over merely maximizing lit floor space. Every closure is a `Decision` node with its score delta recorded — auditable, replayable, no model involved. If this ships, BLUE stops being a checklist without giving up I1.

---

## 8. RED — the adversary

Four steps per round: **LOOK → PLAN → RUN → REFLECT**. Two of them are LLM calls.

### 8.1 The dashboard contract (I2 — the single most important interface in the system)

```jac
obj IslandView   { has id: int; has members: list[str]; has endurance_hours: float;
                   has has_generation: bool; }
obj FacilityView { has name: str; has category: str; has tier: int;
                   has status: str; }        # "lit" | "dark" | "shed"
obj Dashboard {
    has site: str;
    has tick: int;
    has facilities: list[FacilityView];
    has islands: list[IslandView];
    has site_endurance_hours: float;
    has target_hours: float;
    has recent_events: list[str];            # prose, e.g. "North Substation opened at tick 47"
}
```

**Present:** human facility names, category, tier, lit/dark/shed, island groupings *after* a fault, endurance, prose event log.
**Absent:** every edge, every switch identifier, every node ID, adjacency in any form, and kW values.

Island membership does leak grouping information *after* a cut — and that is intentional and realistic. An adversary watching a hospital sees which windows go dark. It is the learning signal REFLECT feeds on. What RED never gets is the drawing set.

Because RED sees names rather than IDs, it must name targets in natural language — "the substation feeding the north campus" — and a resolver maps that to an element.

### 8.2 The two calls

```jac
obj Strike {
    has target_name: str;       # natural language; resolver maps it
    has mechanism: str;         # flood | wind | fuel_interdiction | cyber_switching |
                                # equipment_failure | fire
    has delay_ticks: int;
    has rationale: str;
}
obj Scenario {
    has name: str;
    has hazard: str;            # "Category 2 hurricane, storm surge from the Elizabeth River"
    has strikes: list[Strike];
    has expected_effect: str;
}
obj Outcome {
    has islands_formed: int;
    has endurance_before: float;
    has endurance_after: float;
    has facilities_dark: list[str];
    has tier1_stranded: bool;
    has shed_actions: list[str];
    has unresolved_targets: list[str];
}
obj Lesson {
    has hypothesis: str;        # what RED believed about the topology
    has observed: str;          # what actually happened
    has revision: str;          # the corrected belief
    has confidence: float;
}

"""Given only what an outside observer can see of this facility, and what you
learned from previous attempts, produce the next failure sequence a real hazard
would plausibly cause."""
def plan(view: Dashboard, lessons: list[Lesson]) -> Scenario by llm();

"""Compare what you expected against what happened. State the topological belief
you now hold that you did not hold before."""
def reflect(scenario: Scenario, outcome: Outcome) -> Lesson by llm();
```

**There is no prompt string anywhere in the codebase.** A signature, a docstring, no body. Put those eight lines on screen — it is the strongest Jac moment in the demo.

### 8.3 Why PLAN needs a model

The graph knows conductors and kilowatts. It does not know that storm surge floods low elevation first, so the two substations on the river side fail *together*; that a fuel truck needs a passable road, so an intact generator can still run dry; that a surgical suite matters more mid-operation. None of that is in SMART-DS, and none of it is in any downloadable dataset. It is world knowledge, and a plausible failure *sequence* requires it. A loop over edges cheerfully emits sequences no hurricane would ever produce.

The defensible line: **the simulation knows physics, the model knows context, and a scenario worth planning against needs both.**

### 8.4 Why REFLECT is the one that matters

If round 1 hands round 2 a number (`damage: 340`), that's hill-climbing and needs no LLM. If it hands over a sentence —

> "Cutting the main feed didn't strand anything. Three islands formed instead of two, so a backup route exists that I didn't account for. Take that route out first next time."

— there is no variable in the system that holds it. Round 2's opening move exists *because of that sentence*. Teams that build PLAN and skip REFLECT end up with a model picking from a list, which is precisely what judging criteria call "wrapping an API call."

### 8.5 Target resolution and plausibility gating

Deterministic guards on model output — good engineering, and worth showing.

```jac
def resolve_target(name: str) -> Element? {
    # 1. exact case-insensitive match on Element.name
    # 2. token-overlap score over name + category + campus-zone alias table
    # 3. threshold; below it, return None
}
```

A miss is **not** silently repaired. It records `unresolved_targets`, feeds REFLECT, and RED learns the facility doesn't have the thing it thought it had. Misses are informative.

Plausibility gate, applied before any strike lands:

| Mechanism | Precondition |
|---|---|
| `flood` | `target.elevation_m < flood_stage_m` for the declared hazard |
| `fuel_interdiction` | target is a `Generator`; sets `fuel_reachable = False`, capping fuel at what's on site |
| `wind` | target is overhead (`Conductor.label` marks overhead vs. duct bank) |
| `cyber_switching` | target is a switchable element; opens it, does not damage it |
| `equipment_failure` | any element; damages it |
| `fire` | any element; damages it and adjacent-in-same-building elements |

A strike failing its gate is rejected with a reason, and the reason goes into `Outcome`. RED learns the physical constraints of its own hazard rather than being handed them.

### 8.6 Round loop

```
LOOK    → build Dashboard from current graph state
PLAN    → scenario = plan(dashboard, lessons if memory_enabled else [])
RUN     → for t in 1..M:
            apply strikes due at t (resolve → gate → mutate graph)
            recompute_islands()
            compute endurance per island → Finding nodes
            BLUE shed / reconfigure → Decision nodes
            write Tick node, chain with Next, attach Events/Findings/Decisions
            push dashboard frame to UI
REFLECT → lesson = reflect(scenario, outcome); Round -Learned-> LessonN
```

---

## 9. Provenance and the "ask why" walk

```jac
walker Explain {
    has subject: str;          # "Cafeteria"
    has chain: list[str] = [];

    can start with Run entry {
        d = latest_decision_affecting(self.subject);
        visit d;
    }
    can step with Decision entry {
        self.chain.append(f"[{here.id}] {here.action} {here.subject} — rule: {here.rule}");
        visit [-->](`?Because);
    }
    can step with Finding entry {
        self.chain.append(f"[{here.id}] island {here.island_id} endurance "
                          f"{here.endurance_hours:.0f}h vs target {here.target_hours:.0f}h");
        visit [-->](`?DerivedFrom);
    }
    can step with Tick entry {
        visit [<--](`?AtTick)(`?Event);
    }
    can step with Event entry {
        self.chain.append(f"[{here.id}] t={here.t} {here.kind}: {here.target} — {here.detail}");
        visit [-->](`?Caused);
    }
}
```

Output for the demo query, each line carrying its source node ID:

```
Why did the Cafeteria go dark?
  [e112] t=47  switch_open: North Substation — storm surge, elevation 1.2 m below stage
  [e118] t=47  island_split: East Wing lost its path to Generator B
  [f204] island 3 endurance 41h vs target 96h
  [d311] shed Cafeteria — rule: tier 3 <= target 96h
```

Narration is **templated, not generated** — the chain is the truth, and an LLM in this path would undermine I1 and I6. An optional third call for prose polish is specced but defaults **off**; the count stays at two.

Hospitals reconstruct this from SCADA logs over roughly three weeks. That comparison is the product.

---

## 10. Datasets and ingestion

| # | Source | Use | Location |
|---|---|---|---|
| 1 | **SMART-DS** (NREL) | The graph. Real feeder GeoJSON — conductors, switches, protective devices, 15-min load shapes | `data.openei.org/submissions/2981` |
| 2 | **EAGLE-I** (ORNL) | Real county-level outage records at 15-min resolution, for scenario grounding | `osti.gov/biblio/1975202` |
| 3 | **HIFLD Hospitals** | Facility locations and the `military` facility category | mirror — see caveat |
| 4 | **MIRTA** | DoD installation boundaries | `catalog.data.gov/dataset/military-installations-ranges-and-training-areas` |

**HIFLD caveat.** HIFLD Secure now requires a GII account, profile, and approved Data Use Agreement. Open layers remain reachable through mirrors (the Data Rescue Project portal hosts HIFLD Open Hospitals; NASA NCCS keeps a public feature service including hospitals and VHA facilities). **Verify the link and save the file the night before. Do not plan to fetch this at 11 AM.**

**Skip:** live weather, AIS, EIA, PVWatts, standalone ComStock. SMART-DS already carries load profiles, and weather does not change in a four-minute demo.

### 10.1 Ingestion pipeline (`scripts/build_campus.py` → `data/portsmouth_campus.json`)

1. Load the SMART-DS feeder GeoJSON.
2. **Cluster to campus scale: 20–30 nodes.** SMART-DS feeders run to thousands of elements. Contract by electrical distance to the nearest named building, preserving switch topology at the boundaries. *Say this out loud in the demo* — "we contracted a real feeder to campus granularity" beats being caught pretending otherwise.
3. Attach named NMCP facilities (Charette Health Care Center, the tower wings, central energy plant, ambulatory clinics) with tier, kW, and category from a hand-authored table.
4. Attach elevation from the GeoJSON/DEM so the flood gate has something real to test against.
5. Place generators and batteries at the central energy plant plus wing-level units; set `fuel_gal` from typical 96-hour sizing so the demo's opening endurance sits comfortably above 96 h.
6. Emit normalized JSON; `ingest.jac` builds the graph from it. **Ingestion runs offline. Nothing touches the network at demo time.**

**Node-count floor is a correctness requirement, not aesthetics.** On 12 nodes, round 1 reveals the entire structure and REFLECT has nothing left to learn — the A/B collapses. Target 20–30 nodes with meaningful redundancy (at least one alternate path and at least one tie switch), or hide more from the dashboard.

---

## 11. Interfaces

Walkers exposed by `jac serve` (jac-cloud), all local:

| Endpoint | Purpose |
|---|---|
| `POST /walker/load_site` | Build graph from `data/portsmouth_campus.json` |
| `GET  /walker/dashboard` | Current `Dashboard` object (also RED's input) |
| `POST /walker/cut` | Manual conductor cut — the demo's step ② |
| `POST /walker/run_round` | Full LOOK→PLAN→RUN→REFLECT round |
| `POST /walker/explain` | `{subject: "Cafeteria"}` → cited chain |
| `GET  /walker/lessons` | Accumulated `LessonN` nodes, rendered on screen |
| `POST /walker/reset` | `{memory_enabled: bool}` → fresh `Run` for the A/B |

**Frontend** (`web/`): single page, no build step if possible.
- Geographic SVG map — lat/lon projected to fixed screen coordinates. Elements as circles sized by kW, conductors as lines. **Island color = `island_id`**, so a split is visually instant. Dark = gray, shed = amber outline, damaged conductor = dashed red.
- The headline endurance number, large, with the 96-hour target line. Color transitions as it crosses.
- Event ticker, left. RED's lesson notes, right — visible on screen so step ④ can point at them.
- Poll `/walker/dashboard` at 500 ms during a round, or SSE if time allows. Polling is fine; do not spend demo-day hours on transport.

---

## 12. The A/B (memory on vs. off)

The empirical claim, and the thing a skeptical judge will ask for.

- Two `Run` nodes, identical seed graph, `memory_enabled` true and false.
- Off: `plan(view, [])` every round — no lesson accumulation.
- Run N=3 rounds each; the metric is **site endurance after each round** and **rounds until Tier-1 strand**.
- Display as two counters side by side.

**Run this by 3:15 PM, not 5:00.** If memory doesn't beat no-memory, the overwhelmingly likely cause is a graph too small to learn anything from — fix by growing to 20–30 nodes or hiding more from the dashboard. That fix needs hours, not minutes.

If it still doesn't separate: **report it honestly** with the numbers, and argue REFLECT on the qualitative record — the lessons themselves are on screen and legible. A team that shows a null result and explains it reads as more credible than one that hides it.

---

## 13. Build order and hard deadlines

| By | Deliverable | Notes |
|---|---|---|
| Night before | Datasets downloaded and verified locally; NMCP layout sketched; `jaseci-labs/jac` starred | Verify the HIFLD mirror actually resolves |
| 10:00 | `model.jac` + `ingest.jac` — graph loads, renders on the map | |
| 11:15 | `islands.jac` — manual cut splits the map, colors change | This is demo step ② and the core Jac claim |
| 12:00 | Endurance math + headline number | |
| **12:45** | **BLUE-1 complete. Close the file.** | Twenty lines. It is done. Do not revisit. |
| 14:00 | `red.jac` — Dashboard builder, resolver, `plan()` wired, one round runs | |
| 14:45 | REFLECT wired; lessons render on screen | I5 — do not defer this |
| **15:15** | **A/B run executed** | Leaves time to fix a null result |
| 16:00 | `provenance.jac` + `Explain` walker; the "why" query renders cited | |
| 17:00 | Demo rehearsed end to end, twice, from a cold start | |
| Stretch | BLUE-2 reconfiguration | Only if everything above is genuinely done |

---

## 14. Failure modes and mitigations

| Risk | Mitigation |
|---|---|
| LLM latency stalls the demo | Pre-warm on load; cache round-1 scenario to disk and replay if the call exceeds ~8 s; every LLM call has a hardcoded fallback scenario |
| Venue network dies | Everything local except the two LLM calls. Cached scenarios cover both. Record a full screen capture the night before as an absolute fallback |
| RED names something unresolvable | By design: recorded as `unresolved_targets`, fed to REFLECT. Never crashes a round |
| RED produces physically absurd strikes | Plausibility gate (§8.5) rejects with a reason; the reason becomes learning signal |
| Islands don't visibly split | Verify at 11:15 with a hand cut. If the layout hides it, move node coordinates — a split that doesn't read on screen is worth nothing |
| A/B shows no difference | See §12. Detect at 3:15, fix by growing the graph, or report honestly |
| Endurance number never crosses the target | Tune `fuel_gal` in the campus JSON so the *opening* state sits just above 96 h. One cut should push it under |
| Judge asks about power flow | §3. Answer it before they ask |

---

## 15. Positioning

### The gap
Gridware builds sensors that detect and locate outages — hardware, detection. Squid does AI grid planning in the browser for new infrastructure. Neither tells a hospital which wing to keep alive at 2 AM, nor explains the decision afterward.

> "Gridware tells you the pole broke. Squid helps you plan what to build. Neither one tells a hospital which wing to keep alive at 2 AM, or explains it afterward. That's the gap."

### The compliance wedge
| Customer | Mandate | How it's done today |
|---|---|---|
| Military installation | 10 U.S.C. §2925 — report outage duration, mission impact, tolerable downtime | By hand, weeks later, from logs |
| Hospital | CMS emergency preparedness rule — documented, tested, reviewed plan | By hand, consultants |

Both customers are *legally required* to produce this report, both produce it manually, both produce it annually. Enter as the report generator — mandatory, budgeted, low-risk. Expand into resilience planning and the live control layer from inside.

### Federal precedent for the adversarial angle
DOE funded $2.5M for the Midwest Center for Microgrid Cybersecurity (Argonne, IIT, UIC, ComEd) to build tools for microgrid cyber resilience and corrective action. Red-teaming microgrids is a funded federal research area — this is a working version of it.

### Why one building solves the dual-mandate problem
Naval Medical Center Portsmouth is a hospital: ICUs, operating rooms, ventilators — no strain on a social-impact framing. It is also a DoD installation where §2925 applies — no strain on a defense framing. **One demo, no reload, no "this also works for."** It *is* both, which is what dual-use actually means.

> "Naval Medical Center Portsmouth. It's a hospital, so it has ICUs and operating rooms. It's also a military installation, so federal law requires it to report how long its mission survives without power. Same building, two mandates, one system."

### Prior-winner pattern
Sentinel (graph + agents + **cited evidence**), CivicMesh (civic crisis stakes), Ori (agents in a physical system), Inocula (adversarial over a graph). All four: graph + agents + evidence + real-world domain. BLACKSTART sits squarely in it.

Steal specifically: **from Sentinel**, the citations — the incident report must show, per line, which snapshot node it came from; that's the difference between "the AI wrote a summary" and "here's the evidence." **From Ori**, agents in a physical system, not a chat window — lean into the map, the cascade, things going dark. **From Inocula**, don't hide RED; lead with it.

---

## 16. Demo script (4 minutes)

1. **Show the map.** "This is a real distribution feeder from a national lab, contracted to campus scale. Real conductors, real switches, real facility names."
2. **Break it.** Cut a conductor. The map splits, colors diverge. → *"We never wrote that. In Jac you can't walk down a cut conductor, so the split just happens."*
3. **Watch the number.** 41 hours against a 96-hour target. Cafeteria goes amber. → *"That's the rule doing its job. Boring on purpose."*
4. **Round 2.** RED plans again, takes the backup route out **first**, then the feed. The split forms wrong. ICU stranded. Number collapses. → *"We didn't write that move. It read what happened in round one."* **Point at the lesson text on screen.**
5. **Ask why.** `explain("Cafeteria")` → the cited four-line chain. → *"Hospitals spend three weeks reconstructing that from logs."*
6. **Show the two functions.** Signature, docstring, no body. → *"There's no prompt anywhere in this codebase."*

### Two sentences to memorize
> "The defense is a dumb checklist on purpose. The intelligence is on what goes wrong, because you can't script a disaster."

> "The grid doesn't just survive the failure. It can tell you why."

### Pushback
- **"Isn't that just a priority list?"** — "Yes, and it should be. That part is solved. What isn't solved is knowing what to plan for, and being able to explain what happened. That's what we built."
- **"Why do you need an LLM?"** — "To pick a cable, we don't; a loop does that better. We need it to write a sequence that makes sense in the real world. Floods go downhill. Trucks need roads. That's not in our data."
- **"Does the memory actually help?"** — "Here's the same run with memory off." [both counters]
- **"Blue is too weak."** — Either (A) own it: intelligence goes exactly where it belongs and nowhere else; or (B) point at BLUE-2, where reconfiguration is genuine combinatorial search over topology and is what FLISR does in the field.

---

## 17. Repository layout

```
blackstart/
  src/
    model.jac        # nodes, edges, obj schemas
    ingest.jac       # normalized JSON -> graph
    islands.jac      # Energize walker, endurance math
    blue.jac         # Shed walker (+ Reconfigure, stretch)
    red.jac          # Dashboard builder, resolver, plausibility gate, plan/reflect
    provenance.jac   # snapshot writer, Explain walker
    api.jac          # entry walkers exposed by jac serve
  data/
    portsmouth_campus.json     # generated, committed
    smartds_feeder.geojson     # raw
    eaglei_norfolk.csv         # raw
    hifld_hospitals.geojson    # raw — VERIFY MIRROR THE NIGHT BEFORE
  scripts/
    build_campus.py            # ingestion, run offline
  web/
    index.html  app.js  style.css
  TECH_SPEC.md
```
