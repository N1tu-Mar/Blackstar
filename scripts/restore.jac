"""BLACKSTART - self-healing. The campus switches around a cut.

    jac run scripts/restore.jac

No LLM calls. Every decision below is arithmetic and a graph walk.

The cut is chosen to strand life-critical load rather than merely stress it.
Charette Switchboard B feeds the Emergency Department and Network Core, both
tier 1, and its only source is one feeder off North Campus Switchgear. Cut that
and the walker cannot reach either of them from anywhere: they are dark, not
short, and no amount of load shedding brings a dark load back.

What restores them is the Charette A-B Tie - a normally-open switch to the
sister board, which has its own standby generator and a critical-branch UPS
behind it. The pathfinder finds that route by closing candidate ties and
letting the islanding walker try to reach the load, which is the same
mechanism that made the island split in the first place.
"""

import from endpoints { LoadSite, CutConductor, RunBlue, ExplainWhy }
import from grid.model { Dashboard, Conductor }
import from grid.islands { all_elements }

glob CRITICAL: list[str] = ["Emergency Department", "Network Core and Telemetry"];


"""Print the fate of the loads this scenario is about."""
def show(tag: str, d: Dashboard) {
    print(f"\n{tag}");
    print(f"  site endurance {d.site_endurance_hours:8.1f} h   "
          f"islands {len(d.islands)}   tier1_stranded={d.tier1_stranded}");
    for e in d.elements {
        if e.name in CRITICAL {
            print(f"    {e.name:32s} {e.status}");
        }
    }
}


"""Show the switching state of every normally-open tie.

Read straight off the graph rather than through GetMap: a walker's `report`
echoes to stdout, and dumping the whole topology twice buries the two lines
this script is actually about.
"""
def show_ties() {
    for n in all_elements() {
        for e in [edge n ->:Conductor:->] {
            if e.normally_open {
                state = "CLOSED (switched in)" if e.closed else "open";
                print(f"    {e.label}: {state}");
            }
        }
    }
}


with entry:__main__ {
    r = root spawn LoadSite(memory_enabled=True);
    show("(1) baseline", r.reports[0]);

    print("\n  normally-open ties at baseline:");
    show_ties();

    c = root spawn CutConductor(label="North to Charette B");
    show("(2) feeder to Charette Switchboard B is cut", c.reports[0]);
    print("      ^ dark, not shed. Shedding cannot bring these back.");

    b = root spawn RunBlue();
    show("(3) after the controller responds", b.reports[0]);

    print("\n  ties after restoration:");
    show_ties();

    print("\n=== WHY IS THE EMERGENCY DEPARTMENT BACK? ===");
    ex = root spawn ExplainWhy(subject="Emergency Department");
    for line in ex.reports[0].lines { print(f"  [{line.ref}] {line.text}"); }
    print("");
}
