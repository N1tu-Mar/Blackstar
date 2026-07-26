"""BLACKSTART - ORACLE, the adversary with no model in it.

The hardest question this project gets is the one its own pitch notes already
anticipate: *why do you need an LLM? To pick a cable, a loop does that better.*

The answer has been prose. This file makes it a measurement.

ORACLE is a deterministic beam search over strike chains. It uses the same
mechanisms as RED, the same plausibility gate, and the same arithmetic
evaluator, and it is handed two things RED never gets:

  * the complete element list, unredacted;
  * unlimited simulations of the facility, to try chains and undo them.

So ORACLE is not a realistic adversary. A real attacker cannot roll the grid
back and try again, and neither can RED. ORACLE is an **upper bound on
achievable damage** at a given strike budget, and the useful number is the
ratio RED reaches against that bound from a redacted dashboard with one model
call per round.

Read the comparison in both directions honestly:

  * ORACLE finds a worse chain than RED  -> RED left damage on the table, and
    the gap is the cost of planning under uncertainty.
  * RED matches or beats ORACLE          -> RED found something the search could
    not reach inside its beam, which is the interesting case.

And read what the number cannot say. ORACLE produces `flood:X, fuel:Y` and
nothing else. It cannot say *storm surge floods the river vault, then the
access road, so the truck never reaches the generator that was fine*. It has
no hazard, no coherence, and no account of itself, so it can neither be
briefed to a commander nor used to write section 5 of a filing. The chain is
the cheap half of an exercise; the reasoning is what a facility is buying.

Two invariants this file must not violate:

  * **Nothing here writes to the provenance archive.** Dry-runs call `run_blue`
    directly and never `blue_pass` or any `record_*`, so hypothetical futures
    cannot contaminate an audit trail that is supposed to describe what really
    happened.
  * **Every dry-run is exactly undone.** `restore` is the reason the search can
    be run mid-demo without disturbing the live scenario.
"""

import from grid.model {
    GridNode, Substation, Generator, Battery, Facility, Conductor, IslandView,
    Run, Round, Event, HasRound, Struck
}
import from grid.islands {
    all_elements, recompute_islands, survey, site_endurance, tier1_stranded
}
import from grid.blue { run_blue, unshed_all }
import from grid.red { MECHANISMS, plausible, apply_strike }
import from grid.campus { site_target_hours }
import from grid.prov { active_run }


# ------------------------------------------------------------------- snapshots

"""Every mutable field of the grid, captured in traversal order.

Parallel lists indexed by `all_elements()` order rather than a dict keyed by
name: conductor labels are not guaranteed unique in a site file, and relying on
names would make the snapshot silently lossy on a site that reuses one.
"""
obj GridSnapshot {
    has elem_damaged: list[bool] = [],
        elem_island: list[int] = [],
        sub_live: list[bool] = [],
        gen_online: list[bool] = [],
        gen_fuel: list[float] = [],
        gen_reach: list[bool] = [],
        batt_kwh: list[float] = [],
        fac_shed: list[bool] = [],
        cond_closed: list[bool] = [],
        cond_damaged: list[bool] = [],
        cond_passable: list[bool] = [];
}


"""Capture the full mutable state of the grid."""
def take_snapshot -> GridSnapshot {
    snap = GridSnapshot();
    for n in all_elements() {
        snap.elem_damaged.append(n.damaged);
        snap.elem_island.append(n.island_id);

        live = False;
        if isinstance(n, Substation) { live = (n as Substation).utility_live; }
        snap.sub_live.append(live);

        online = False;
        fuel = 0.0;
        reach = False;
        if isinstance(n, Generator) {
            g = n as Generator;
            online = g.online;
            fuel = g.fuel_gal;
            reach = g.fuel_reachable;
        }
        snap.gen_online.append(online);
        snap.gen_fuel.append(fuel);
        snap.gen_reach.append(reach);

        kwh = 0.0;
        if isinstance(n, Battery) { kwh = (n as Battery).kwh_stored; }
        snap.batt_kwh.append(kwh);

        shed = False;
        if isinstance(n, Facility) { shed = (n as Facility).shed; }
        snap.fac_shed.append(shed);
    }
    for n in all_elements() {
        for e in [edge n ->:Conductor:->] {
            snap.cond_closed.append(e.closed);
            snap.cond_damaged.append(e.damaged);
            snap.cond_passable.append(e.passable);
        }
    }
    return snap;
}


"""Put the grid back exactly as it was. Must undo a dry-run completely."""
def restore(snap: GridSnapshot) {
    i = 0;
    for n in all_elements() {
        n.damaged = snap.elem_damaged[i];
        n.island_id = snap.elem_island[i];
        if isinstance(n, Substation) { (n as Substation).utility_live = snap.sub_live[i]; }
        if isinstance(n, Generator) {
            g = n as Generator;
            g.online = snap.gen_online[i];
            g.fuel_gal = snap.gen_fuel[i];
            g.fuel_reachable = snap.gen_reach[i];
        }
        if isinstance(n, Battery) { (n as Battery).kwh_stored = snap.batt_kwh[i]; }
        if isinstance(n, Facility) { (n as Facility).shed = snap.fac_shed[i]; }
        i += 1;
    }
    j = 0;
    for n in all_elements() {
        for e in [edge n ->:Conductor:->] {
            e.closed = snap.cond_closed[j];
            e.damaged = snap.cond_damaged[j];
            e.passable = snap.cond_passable[j];
            j += 1;
        }
    }
    recompute_islands();
}


# ---------------------------------------------------------------------- chains

"""One strike: an element name and the mechanism used against it."""
obj ChainStep {
    has target: str,
        mechanism: str;
}


"""A scored chain. `label` is the reproducible identity used for tie-breaking."""
obj ChainResult {
    has steps: list[ChainStep] = [],
        label: str = "",
        endurance_after: float = 0.0,
        tier1_stranded: bool = False,
        islands_formed: int = 0,
        shed_count: int = 0;
}


"""Render a chain as a stable, sortable string."""
def chain_label(steps: list[ChainStep]) -> str {
    parts: list[str] = [];
    for s in steps { parts.append(f"{s.mechanism}:{s.target}"); }
    return " -> ".join(parts);
}


"""Every single strike the plausibility gate would allow right now.

Built from the *same* gate RED is held to, so the comparison is not rigged by
letting the search flood a hilltop switchgear that RED would be refused.
"""
def candidate_strikes -> list[ChainStep] {
    out: list[ChainStep] = [];
    for n in all_elements() {
        for mech in MECHANISMS {
            (ok, _why) = plausible(mech, n);
            if ok { out.append(ChainStep(target=n.name, mechanism=mech)); }
        }
    }
    return out;
}


"""Resolve a name to an element. Exact match only - ORACLE sees the real list."""
def element_named(name: str) -> GridNode | None {
    for n in all_elements() {
        if n.name == name { return n; }
    }
    return None;
}


"""Run one chain against the grid, score it, and undo it completely.

The scoring is BLUE's own arithmetic: apply the strikes, let the deterministic
controller respond exactly as it would in a real round, then read the site
endurance it managed to hold.
"""
def evaluate(steps: list[ChainStep]) -> ChainResult {
    snap = take_snapshot();

    for s in steps {
        target = element_named(s.target);
        if target is None { continue; }
        t = target as GridNode;
        (ok, _why) = plausible(s.mechanism, t);
        if not ok { continue; }
        (_landed, _detail) = apply_strike(s.mechanism, t);
    }

    recompute_islands();
    # `run_blue`, never `blue_pass`: a dry-run must not write Findings or
    # Decisions into the archive the compliance filing reads from.
    (actions, _breached) = run_blue();
    recompute_islands();
    islands = survey();

    res = ChainResult(
        steps=steps,
        label=chain_label(steps),
        endurance_after=site_endurance(islands),
        tier1_stranded=tier1_stranded(islands),
        islands_formed=len(islands),
        shed_count=len(actions)
    );

    restore(snap);
    return res;
}


# ---------------------------------------------------------------------- search

"""Sort key: lowest endurance first, then most curtailment, then label.

The label tiebreak is what makes the search reproducible. Without it two chains
that do identical damage could swap places between runs and the "worst chain"
would not be a stable fact to report.
"""
def rank_key(r: ChainResult) -> str {
    # Fixed-width numeric prefix so a lexical sort orders numerically.
    hours = r.endurance_after;
    if hours < 0.0 { hours = 0.0; }
    if hours > 99999.0 { hours = 99999.0; }
    inv_shed = 9999 - r.shed_count;
    return f"{int(hours * 10):08d}|{inv_shed:04d}|{r.label}";
}


"""Beam search for the worst chain of at most `depth` strikes.

Exhaustive search is not affordable: ~27 elements against 6 mechanisms is on
the order of 100 plausible single strikes, so depth 3 exhaustively is ~10^6
full simulations. A beam of width `beam` keeps it to roughly
`beam * candidates * depth` evaluations, which is seconds rather than hours.

The beam is a real limitation and it is reported rather than hidden: `searched`
carries how many chains were actually simulated, so a reader can see that the
bound is a bound *from below* on achievable damage. Widening the beam can only
find something equal or worse.
"""
obj OracleResult {
    has best: ChainResult = ChainResult(),
        depth: int = 0,
        beam: int = 0,
        searched: int = 0,
        candidates: int = 0,
        baseline_endurance: float = 0.0,
        target_hours: float = 96.0;
}


"""Search for the worst chain ORACLE can find at this budget."""
def worst_chain(depth: int, beam: int) -> OracleResult {
    recompute_islands();
    baseline = site_endurance(survey());
    cands = candidate_strikes();

    out = OracleResult(
        depth=depth, beam=beam, candidates=len(cands),
        baseline_endurance=baseline, target_hours=site_target_hours()
    );

    # Frontier of surviving prefixes; starts as the single empty chain.
    frontier: list[list[ChainStep]] = [[]];
    best: ChainResult | None = None;
    searched = 0;

    for _level in range(depth) {
        scored: list[ChainResult] = [];
        for prefix in frontier {
            used: list[str] = [];
            for p in prefix { used.append(p.target); }
            for c in cands {
                # One strike per element per chain: hitting an already-damaged
                # element a second way adds cost without adding effect.
                if c.target in used { continue; }
                chain: list[ChainStep] = [];
                for p in prefix { chain.append(p); }
                chain.append(c);
                res = evaluate(chain);
                searched += 1;
                scored.append(res);
            }
        }
        if len(scored) == 0 { break; }

        ordered = sorted(scored, key=rank_key);
        if best is None or rank_key(ordered[0]) < rank_key(best as ChainResult) {
            best = ordered[0];
        }

        frontier = [];
        kept = 0;
        for r in ordered {
            if kept >= beam { break; }
            frontier.append(r.steps);
            kept += 1;
        }
    }

    out.searched = searched;
    if best is not None { out.best = best as ChainResult; }
    return out;
}


# ------------------------------------------------------------------ comparison

"""RED's achieved damage measured against ORACLE's bound at the same budget."""
obj Verdict {
    has red_endurance: float = 0.0,
        oracle_endurance: float = 0.0,
        baseline_endurance: float = 0.0,
        target_hours: float = 96.0,
        strikes: int = 0,
        chains_searched: int = 0,
        oracle_chain: str = "",
        red_reached_bound: bool = False,
        gap_hours: float = 0.0,
        efficiency: float = 0.0,
        summary: str = "";
}


"""Compare an achieved endurance against the bound for the same strike budget.

`efficiency` is the fraction of the damage ORACLE could find that RED actually
achieved: 1.0 means RED matched an adversary with the full single-line diagram
and thousands of rehearsals. Above 1.0 means it beat that adversary.
"""
def compare(red_endurance: float, strikes: int, beam: int) -> Verdict {
    o = worst_chain(strikes, beam);
    v = Verdict(
        red_endurance=red_endurance,
        oracle_endurance=o.best.endurance_after,
        baseline_endurance=o.baseline_endurance,
        target_hours=o.target_hours,
        strikes=strikes,
        chains_searched=o.searched,
        oracle_chain=o.best.label
    );

    red_damage = o.baseline_endurance - red_endurance;
    oracle_damage = o.baseline_endurance - o.best.endurance_after;
    v.gap_hours = red_endurance - o.best.endurance_after;
    v.red_reached_bound = red_endurance <= o.best.endurance_after;
    v.efficiency = (red_damage / oracle_damage) if oracle_damage > 0.001 else 0.0;

    if v.red_reached_bound {
        v.summary = (
            "RED matched or beat an adversary holding the full single-line diagram "
            f"and {o.searched} rehearsals, planning from a redacted dashboard."
        );
    } else {
        v.summary = (
            f"RED left {v.gap_hours:.1f} h on the table against the bound. The search "
            f"needed the unredacted element list and {o.searched} simulations to find "
            "it, and cannot say what hazard would produce it."
        );
    }
    return v;
}


# -------------------------------------------------------------------- coverage

"""One element ORACLE can hurt, and whether the RED campaign ever tried it."""
obj Blindspot {
    has element_name: str = "",
        kind: str = "",
        mechanism: str = "",
        endurance_after: float = 0.0,
        strands_tier1: bool = False,
        struck_by_red: bool = False,
        self_inflicted: bool = False;
}


"""How much of the attack surface the campaign actually exercised."""
obj Coverage {
    has elements_total: int = 0,
        elements_struck: int = 0,
        rounds_run: int = 0,
        oracle_worst: float = 0.0,
        red_worst_element: str = "",
        blindspots: list = [],
        exercised: list = [],
        summary: str = "";
}


"""Kind label for an element, matching the advisor's vocabulary."""
def kind_label(n: GridNode) -> str {
    if isinstance(n, Substation) { return "substation"; }
    if isinstance(n, Generator) { return "generator"; }
    if isinstance(n, Battery) { return "battery / UPS"; }
    if isinstance(n, Facility) { return "facility"; }
    return "switchgear";
}


"""Blindspot ordering: tier-1 stranders first, then worst endurance, then name."""
def blindspot_key(b: Blindspot) -> tuple[int, float, str] {
    return (0 if b.strands_tier1 else 1, b.endurance_after, b.element_name);
}


"""Every element name a landed RED strike has ever hit."""
def struck_names -> list[str] {
    out: list[str] = [];
    run = active_run();
    if run is None { return out; }
    for r in [(run as Run) ->:HasRound:->] {
        for e in [r ->:Struck:->] {
            nm = (e as Event).target;
            if nm not in out { out.append(nm); }
        }
    }
    return out;
}


"""Which parts of the attack surface the campaign never touched.

The advisor ranks what RED actually struck. That is the right input for "what
did we learn" and the wrong input for "what did we miss": a campaign can only
implicate elements the adversary chose to hit, and RED chooses from a redacted
view. ORACLE evaluates every plausible single strike, so the difference between
the two sets is the exercise's blind spot.

A blind spot that strands life-critical load on its own is the most important
line in any hardening plan, and by construction it is the line a red-team
transcript can never contain.

Only elements whose best single strike actually does damage are reported --
listing every untouched element would bury the finding in noise.
"""
def coverage(beam: int) -> Coverage {
    recompute_islands();
    baseline = site_endurance(survey());
    target = site_target_hours();
    already = struck_names();

    run = active_run();
    rounds = 0;
    if run is not None { rounds = len([(run as Run) ->:HasRound:->]); }

    cov = Coverage(
        elements_total=len(all_elements()),
        elements_struck=len(already),
        rounds_run=rounds
    );

    # Worst single strike available per element, evaluated the same way BLUE
    # would experience it.
    worst_by_element: dict[str, Blindspot] = {};
    for c in candidate_strikes() {
        res = evaluate([c]);
        held = worst_by_element.get(c.target);
        if held is None or res.endurance_after < (held as Blindspot).endurance_after {
            target_node = element_named(c.target);
            kind = "unknown";
            if target_node is not None { kind = kind_label(target_node as GridNode); }
            # Is the struck element itself a tier-1 load? Then any stranding it
            # causes is trivially itself.
            own_tier1 = False;
            if target_node is not None and isinstance(target_node, Facility) {
                own_tier1 = (target_node as Facility).tier == 1;
            }
            worst_by_element[c.target] = Blindspot(
                element_name=c.target, kind=kind, mechanism=c.mechanism,
                endurance_after=res.endurance_after,
                strands_tier1=res.tier1_stranded,
                struck_by_red=(c.target in already),
                self_inflicted=own_tier1
            );
        }
    }

    blind: list[Blindspot] = [];
    seen: list[Blindspot] = [];
    for name in worst_by_element.keys() {
        b = worst_by_element[name];
        # Only report elements where a single strike actually costs something.
        hurts = b.strands_tier1 or b.endurance_after < target;
        if not hurts { continue; }
        # Destroying a tier-1 facility strands tier-1 load by definition. That is
        # a tautology, not a finding, and listing it buries the real result. The
        # interesting case is infrastructure whose loss strands critical care it
        # does not itself contain.
        if b.self_inflicted { continue; }
        if b.struck_by_red { seen.append(b); } else { blind.append(b); }
        if b.endurance_after < cov.oracle_worst or cov.oracle_worst == 0.0 {
            if cov.oracle_worst == 0.0 or b.endurance_after < cov.oracle_worst {
                cov.oracle_worst = b.endurance_after;
                cov.red_worst_element = b.element_name;
            }
        }
    }

    cov.blindspots = sorted(blind, key=blindspot_key);
    cov.exercised = sorted(seen, key=blindspot_key);

    killers = [b for b in cov.blindspots if b.strands_tier1];
    if rounds == 0 {
        cov.summary = (
            f"No RED campaign has run yet. {len(cov.blindspots)} elements can be "
            f"taken under the {target:.0f} h requirement by a single strike."
        );
    } elif len(killers) > 0 {
        k = killers[0];
        cov.summary = (
            f"{rounds} scenario(s) exercised {cov.elements_struck} of "
            f"{cov.elements_total} elements. {len(killers)} element(s) the campaign "
            f"never touched strand life-critical load on a single strike -- worst is "
            f"{k.mechanism} on {k.element_name}. A red-team transcript cannot "
            f"surface this, because RED never tried it."
        );
    } else {
        cov.summary = (
            f"{rounds} scenario(s) exercised {cov.elements_struck} of "
            f"{cov.elements_total} elements. No untested element strands "
            f"life-critical load on its own; {len(cov.blindspots)} can still take "
            f"the site under its {target:.0f} h requirement."
        );
    }
    return cov;
}
