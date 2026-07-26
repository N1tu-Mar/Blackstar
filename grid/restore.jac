"""BLACKSTART - the black start. Bringing a dead campus back, in order.

The project is named after a real procedure. DoD runs **Black Start Exercises**
to find energy vulnerabilities, and NSA Hampton Roads -- the complex Naval
Medical Center Portsmouth sits in -- ran one in FY2023. Until this file, the
simulator only ever went one direction: elements failed, load shed, endurance
counted down. That is the survival half. A black start is the other half.

Restoration is not shedding run at a different threshold. It is the curtailment
order played **backwards**, and that symmetry is the whole design:

    BLUE sheds     highest tier first, largest load first within a tier
    RESTORE picks up  lowest tier first, largest load first within a tier

So the first thing back is the largest tier-1 load and the last thing back is
the smallest tier-3 load. Running one order forward and the other in reverse
means a facility cannot end a restoration in a state the controller would
immediately have shed out of -- the two halves cannot disagree.

No model runs here, for the same reason no model runs in blue.jac: energizing a
bus in the wrong order is how you damage equipment or trip the sets you just
started, and nobody accredits a language model to sequence that. Every step is
arithmetic plus a fixed priority, and every step is checked before it is kept.

Two admission tests before any load comes back, both from the real constraint
set rather than invented:

  * **Power.** The island's generation must actually cover the load. UFC 4-510-01
    requires a hospital generator to "start and assume its full electrical loads
    within 10 seconds", so a set that cannot carry what you hand it does not
    ride through -- it trips, and takes the loads already restored with it.
  * **Endurance.** Restoring load shortens the countdown. A step that would put
    the site back under its mandated hours is refused and recorded, because
    "we restored everything and then breached" is not a restoration.

Ties are closed first, before any load is picked up. UFC 4-510-01 ¶11-3.3.3
requires double-ended substations to run with a normally-open tie that closes
automatically on loss of a feeder, so reconnecting a stranded board to surviving
generation is the designed response and it costs nothing to try.
"""

import from grid.model {
    GridNode, Substation, Generator, Battery, Facility, Conductor,
    Tick, Finding, IslandView
}
import from grid.islands {
    all_elements, recompute_islands, survey, site_endurance, tier1_stranded,
    dark_facilities, UTILITY_HOURS
}
import from grid.campus { site_target_hours }
import from grid.oracle { take_snapshot, restore }


"""One move in the restoration sequence, with the arithmetic that allowed it."""
obj RestoreStep {
    has order: int = 0,
        action: str = "restore_load",
        target: str = "",
        tier: int = 0,
        kw: float = 0.0,
        endurance_after: float = 0.0,
        reason: str = "";
}


"""A load that could not come back, and which test refused it."""
obj Deferred {
    has target: str = "",
        tier: int = 0,
        kw: float = 0.0,
        limit: str = "",
        reason: str = "";
}


"""The black start: what came back, in what order, and what could not."""
obj RestorePlan {
    has site_target_hours: float = 96.0,
        endurance_before: float = 0.0,
        endurance_after: float = 0.0,
        steps: list[RestoreStep] = [],
        deferred: list[Deferred] = [],
        ties_closed: list[str] = [],
        restored_kw: float = 0.0,
        deferred_kw: float = 0.0,
        loads_restored: int = 0,
        service_complete: bool = False,
        summary: str = "";
}


# Bound on the sequencing loop. Every iteration restores exactly one load or
# closes exactly one tie, both finite, so this only ever catches a bug.
glob MAX_RESTORE_STEPS = 80;


"""Restoration order: lowest tier first, then largest load, then name.

The exact inverse of BLUE's shed key, which is what keeps the two halves from
disagreeing. Name last so the sequence is reproducible.
"""
def restore_rank(f: Facility) -> tuple[int, float, str] {
    return (f.tier, 0.0 - f.kw, f.name);
}


"""Every load currently out of service that restoration is allowed to pick up.

A facility the walker cannot reach at all is not a candidate: it has no path to
generation, so un-shedding it would change nothing but the bookkeeping.
"""
def restorable(_unused: int) -> list[Facility] {
    recompute_islands();
    out: list[Facility] = [];
    for f in [root --> [?:Facility]] {
        if not f.shed { continue; }
        if f.island_id == -1 { continue; }
        out.append(f);
    }
    return sorted(out, key=restore_rank);
}


"""True when every island's served load is inside its generation capacity.

`survey` reports served_kw per island; capacity comes from the generators and
batteries the walker could reach. An island drawing more than it can generate
does not brown out in reality -- the sets trip.
"""
def capacity_ok -> bool {
    recompute_islands();
    cap: dict[int, float] = {};
    draw: dict[int, float] = {};
    for n in all_elements() {
        if n.island_id == -1 { continue; }
        iid = n.island_id;
        if isinstance(n, Generator) {
            g = n as Generator;
            if g.online { cap[iid] = cap.get(iid, 0.0) + g.kw_rating; }
        } elif isinstance(n, Battery) {
            cap[iid] = cap.get(iid, 0.0) + (n as Battery).max_kw;
        } elif isinstance(n, Substation) {
            s = n as Substation;
            # A live utility feed is not a capacity constraint at this scale.
            if s.utility_source and s.utility_live { cap[iid] = cap.get(iid, 0.0) + 1000000.0; }
        } elif isinstance(n, Facility) {
            f = n as Facility;
            if not f.shed { draw[iid] = draw.get(iid, 0.0) + f.kw; }
        }
    }
    for iid in draw.keys() {
        if draw[iid] > cap.get(iid, 0.0) { return False; }
    }
    return True;
}


"""Worst endurance among islands carrying tier-1 load."""
def critical_endurance -> float {
    recompute_islands();
    return site_endurance(survey());
}


"""Close any normally-open tie that reconnects stranded load to generation.

Tried before any load is restored. Each candidate is closed, the grid
re-surveyed, and reverted unless it strictly reduces the number of unreachable
facilities or improves the worst critical endurance -- because closing a tie
changes which islands exist, so its effect cannot be read off the state before.
"""
def close_useful_ties(plan: RestorePlan, order: int) -> int {
    n = order;
    guard = 0;
    while guard < 12 {
        guard += 1;
        recompute_islands();
        base_dark = len(dark_facilities());
        base_end = critical_endurance();

        chosen: Conductor | None = None;
        best_dark = base_dark;
        best_end = base_end;

        for el in all_elements() {
            for e in [edge el ->:Conductor:normally_open == True:->] {
                if e.closed { continue; }
                e.closed = True;
                recompute_islands();
                d = len(dark_facilities());
                en = critical_endurance();
                ok = capacity_ok();
                e.closed = False;
                recompute_islands();
                if not ok { continue; }
                better = (d < best_dark) or (d == best_dark and en > best_end + 0.05);
                if better {
                    best_dark = d;
                    best_end = en;
                    chosen = e;
                }
            }
        }

        if chosen is None { break; }
        tie = chosen as Conductor;
        tie.closed = True;
        recompute_islands();
        n += 1;
        plan.steps.append(RestoreStep(
            order=n, action="close_tie", target=tie.label,
            endurance_after=critical_endurance(),
            reason=(
                f"closed tie {tie.label}: reconnected stranded load to surviving "
                f"generation, unreachable facilities {base_dark} -> {best_dark}, "
                f"endurance {base_end:.1f} h -> {best_end:.1f} h"
            )
        ));
        plan.ties_closed.append(tie.label);
    }
    return n;
}


"""Run the black start against the current grid state.

Mutates the grid -- this is an action, not a forecast. Call `dry_run_restore`
instead to see the sequence without taking it.
"""
def black_start -> RestorePlan {
    target = site_target_hours();
    plan = RestorePlan(site_target_hours=target);
    recompute_islands();
    plan.endurance_before = critical_endurance();

    # --- 1. reconfigure before energising anything ------------------------
    order = close_useful_ties(plan, 0);

    # --- 2. pick load back up, lowest tier first -------------------------
    steps = 0;
    while steps < MAX_RESTORE_STEPS {
        steps += 1;
        pool = restorable(0);
        if len(pool) == 0 { break; }

        took = False;
        for f in pool {
            before = critical_endurance();
            f.shed = False;
            recompute_islands();

            if not capacity_ok() {
                f.shed = True;
                recompute_islands();
                plan.deferred.append(Deferred(
                    target=f.name, tier=f.tier, kw=f.kw, limit="power",
                    reason=(
                        f"restoring {f.kw:.0f} kW would put its island over the "
                        f"generation it can actually reach; the sets would trip and "
                        f"take the load already restored with them"
                    )
                ));
                continue;
            }

            after = critical_endurance();
            if after < target {
                f.shed = True;
                recompute_islands();
                plan.deferred.append(Deferred(
                    target=f.name, tier=f.tier, kw=f.kw, limit="endurance",
                    reason=(
                        f"restoring {f.kw:.0f} kW would take endurance to "
                        f"{after:.1f} h, under the {target:.0f} h requirement; held "
                        f"out of service rather than breach"
                    )
                ));
                continue;
            }

            order += 1;
            plan.steps.append(RestoreStep(
                order=order, action="restore_load", target=f.name, tier=f.tier,
                kw=f.kw, endurance_after=after,
                reason=(
                    f"tier {f.tier}, {f.kw:.0f} kW: largest remaining load at the "
                    f"lowest tier still out of service; island carries it and "
                    f"endurance holds at {after:.1f} h against {target:.0f} h"
                )
            ));
            plan.restored_kw += f.kw;
            plan.loads_restored += 1;
            took = True;
            break;
        }
        if not took { break; }
    }

    # --- 3. report -------------------------------------------------------
    recompute_islands();
    plan.endurance_after = critical_endurance();
    for d in plan.deferred { plan.deferred_kw += d.kw; }

    still: list[str] = [];
    for f in [root --> [?:Facility]] {
        if f.shed or f.island_id == -1 { still.append(f.name); }
    }
    plan.service_complete = len(still) == 0;

    if plan.service_complete {
        plan.summary = (
            f"Full service restored in {len(plan.steps)} steps. Endurance "
            f"{plan.endurance_before:.1f} h -> {plan.endurance_after:.1f} h against a "
            f"{target:.0f} h requirement."
        );
    } elif plan.loads_restored == 0 and len(plan.ties_closed) == 0 {
        plan.summary = (
            f"Nothing could be brought back. {len(still)} facilities remain out of "
            f"service: there is no path to generation for them, or the generation "
            f"that is left cannot carry them without breaching {target:.0f} h."
        );
    } else {
        plan.summary = (
            f"Partial restoration: {plan.loads_restored} load(s) and "
            f"{len(plan.ties_closed)} tie(s) back, {plan.restored_kw:.0f} kW returned "
            f"to service. {len(still)} facilities held out ({plan.deferred_kw:.0f} kW) "
            f"to keep endurance at {plan.endurance_after:.1f} h against "
            f"{target:.0f} h. Restoring them needs more generation or more fuel, not "
            f"a different sequence."
        );
    }
    return plan;
}


"""Compute the black start without taking it: snapshot, plan, roll back.

Lets an operator see the sequence -- and the reason each held-out load is held
out -- before committing to it.
"""
def dry_run_restore -> RestorePlan {
    snap = take_snapshot();
    plan = black_start();
    restore(snap);
    return plan;
}
