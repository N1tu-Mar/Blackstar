"""BLACKSTART - the full arc: attack, survive, recover.

Run it with:  jac run scripts/blackstart.jac

Needs no API key. Three phases, all deterministic:

  1. the hurricane takes both utility feeds and floods a plant generator
  2. the controller sheds load to protect what is left
  3. a repair crew restores one feeder -- and the black start picks service back
     up, lowest tier first, refusing any step that would trip a set or put
     endurance back under the requirement

Phase 3 is what the project is named after. DoD runs Black Start Exercises to
find energy vulnerabilities; NSA Hampton Roads ran one in FY2023.
"""

import from endpoints { LoadSite, CutConductor, RunBlue }
import from grid.campus { site_target_hours }
import from grid.islands { recompute_islands, survey, site_endurance, dark_facilities }
import from grid.restore { black_start }
import from grid.model { Facility, Generator, Substation, GridNode, Conductor }

def shown -> str {
    recompute_islands();
    out: list[str] = [];
    for f in [root --> [?:Facility]] {
        if f.shed or f.island_id == -1 { out.append(f.name); }
    }
    return ", ".join(out) if out else "nothing out of service";
}

with entry:__main__ {
    target = site_target_hours();
    _ = root spawn LoadSite(memory_enabled=True);
    recompute_islands();
    print(f"baseline                 endurance={site_endurance(survey()):8.1f} h   target={target:.0f} h");

    _ = root spawn CutConductor(label="Elizabeth 34.5kV Feeder");
    _ = root spawn CutConductor(label="Effingham 34.5kV Feeder");
    # Flood one plant generator: storm surge up the Elizabeth River.
    for g in [root --> [?:Generator]] {
        if g.name == "CEP Generator 1" { g.online = False; g.damaged = True; }
    }
    recompute_islands();
    print(f"both feeds + GEN 1 lost  endurance={site_endurance(survey()):8.1f} h");

    _ = root spawn RunBlue();
    recompute_islands();
    print(f"after the controller     endurance={site_endurance(survey()):8.1f} h");
    print(f"  out of service: {shown()}");

    # A black start begins when a source comes back. Until then there is nothing
    # to restore *onto* -- which the previous phase demonstrates: with endurance
    # already under target, every candidate is correctly refused.
    print("\n=== repair crew re-energizes the Elizabeth River feeder ===");
    for el in [root --> [?:Facility]] { break; }
    for n in [root --> [?:Substation]] {
        if n.name == "Elizabeth River Substation" { n.damaged = False; n.utility_live = True; }
    }
    for n in [root --> [?:GridNode]] {
        for e in [edge n ->:Conductor:->] {
            if e.label == "Elizabeth 34.5kV Feeder" { e.closed = True; e.damaged = False; }
        }
    }
    recompute_islands();
    print(f"  feeder back              endurance={site_endurance(survey()):8.1f} h");

    print("\n=== BLACK START ===");
    plan = black_start();
    print(f"  {plan.summary}");
    for s in plan.steps {
        print(f"  {s.order:2d}. {s.action:<14s} {s.target:<34s} -> {s.endurance_after:7.1f} h");
    }
    if len(plan.deferred) > 0 {
        print("  held out of service:");
        for d in plan.deferred {
            print(f"      {d.target} ({d.limit}) - tier {d.tier}, {d.kw:.0f} kW");
        }
    }
    print(f"\n  final: {shown()}");
}
