"""BLACKSTART - BLUE, the deterministic controller.

This file is boring on purpose and it is meant to stay that way.

Nobody accredits a language model to de-energize an ICU, so no model runs
here. Shedding order is a sorted list and a while loop: highest tier number
first, largest load first within a tier, tier 1 never. If tiers 2 and 3 are
exhausted and endurance is still short, BLUE reports a breach rather than
touching tier 1 - that honest failure state is what makes round 2 mean
something.
"""

import from grid.model { GridNode, Facility, IslandView }
import from grid.islands { recompute_islands, survey }
import from grid.campus { site_target_hours }


"""The next load to drop on this island, or None if only tier 1 remains."""
def pick_victim(island_id: int) -> Facility | None {
    best: Facility | None = None;
    for f in [root --> [?:Facility]] {
        if f.island_id != island_id { continue; }
        if f.shed or f.tier <= 1 { continue; }
        if best is None {
            best = f;
            continue;
        }
        b = best as Facility;
        # Highest tier number first; within a tier, biggest kW first.
        if f.tier > b.tier or (f.tier == b.tier and f.kw > b.kw) { best = f; }
    }
    return best;
}


"""Shed load until every island clears the target, or nothing is left to shed.

Returns (actions, breached). `actions` is one entry per facility dropped, in
the order dropped. `breached` is True when an island carrying tier-1 load
still sits under target with only tier-1 load left on it.
"""
def shed_to_target(target: float) -> tuple[list[str], bool] {
    actions: list[str] = [];
    breached = False;
    guard = 0;

    while guard < 60 {
        guard += 1;
        recompute_islands();
        islands = survey();

        victim: Facility | None = None;
        stuck = False;
        for i in islands {
            if i.endurance_hours >= target { continue; }
            cand = pick_victim(i.id);
            if cand is not None {
                victim = cand;
                break;
            }
            # Under target with nothing sheddable left on this island.
            if i.tier1_present { stuck = True; }
        }

        if victim is None {
            breached = stuck;
            break;
        }
        v = victim as Facility;
        v.shed = True;
        actions.append(v.name);
    }

    recompute_islands();

    # A tier-1 load that went fully dark belongs to no island, so `survey`
    # never reports it and the loop above cannot see it. That is the worst
    # outcome there is, and it must not be recorded as a clean run.
    for f in [root --> [?:Facility]] {
        if f.tier == 1 and f.island_id == -1 { breached = True; }
    }
    return (actions, breached);
}


"""Run BLUE at the active site's mandated target."""
def run_blue -> tuple[list[str], bool] {
    return shed_to_target(site_target_hours());
}


"""Restore every shed load. Used when resetting a scenario."""
def unshed_all {
    for f in [root --> [?:Facility]] { f.shed = False; }
}
