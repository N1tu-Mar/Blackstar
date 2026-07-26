"""BLACKSTART - N-1 criticality: rank the campus by what each loss costs.

Run it with:  jac run scripts/criticality.jac

No API key, no model. The classic contingency sweep utilities actually use: fail
one element at a time, let the controller respond, measure what the site is left
holding, sort.

Run twice, and the reason is the interesting part. From a healthy campus the
result is nearly binary, because UFC 4-510-01 requires two utility feeders on
separated substations -- the design is N-1 robust by mandate, so losing almost
anything still leaves the site grid-backed. The gradient only appears once
commercial power is gone. So the second sweep is the one an engineer wants: given
that the hurricane already took the grid, what is now the weakest point.
"""

import from grid.campus { reset_campus, site_name }
import from grid.oracle { criticality, Criticality }
import from grid.islands { recompute_islands }
import from grid.model { GridNode, Substation, Conductor }


"""Print one ranked sweep."""
def show(ranked: list[Criticality]) {
    print(f"  {'element':<34s} {'kind':<20s} {'via':<17s} {'left':>7s}  heat");
    for c in ranked {
        flag = "  TIER-1 STRANDED" if c.strands_tier1 else "";
        bar = "#" * int(c.share * 20.0 + 0.5);
        print(f"  {c.element_name:<34s} {c.kind:<20s} {c.mechanism:<17s} "
              f"{c.endurance_after:7.1f}  {bar:<20s}{flag}");
    }
}


"""Take both utility feeds out, the way the hurricane does."""
def drop_utility {
    for n in [root --> [?:Substation]] {
        if n.utility_source { n.utility_live = False; }
    }
    for n in [root --> [?:GridNode]] {
        for e in [edge n ->:Conductor:->] {
            if e.label == "Elizabeth 34.5kV Feeder" or e.label == "Effingham 34.5kV Feeder" {
                e.closed = False;
            }
        }
    }
    recompute_islands();
}

with entry:__main__ {
    _ = reset_campus();
    print(f"{site_name()} - N-1 contingency sweep\n");

    ranked = criticality();
    print(f"=== healthy campus, both feeders up ({len(ranked)} elements) ===");
    show(ranked);
    print("  -> nearly binary: two separated feeders are mandated, so the design");
    print("     is N-1 robust and only the switchboards are single points.\n");

    drop_utility();
    print("=== after the hurricane takes both utility feeders ===");
    show(criticality());
}
