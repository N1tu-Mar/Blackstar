"""BLACKSTART - produce the mandated filing from a real cascade.

    jac run scripts/report.jac
    BLACKSTART_SITE=nnsy-portsmouth jac run scripts/report.jac

Needs no API key. Site-agnostic: it finds this site's utility feeders by walking
the graph rather than naming them, so it runs on the hospital, the shipyard, or
any site added later.

  load the campus -> open every utility feeder -> let BLUE respond
  -> project the resulting archive into the filing

The filing is a projection of the run graph. Change the cascade and every number
and citation in it changes, with no separate report state to keep in sync.
"""

import from endpoints { LoadSite, CutConductor, RunBlue, GetReportMarkdown, GenerateReport }
import from grid.model { GridNode, Substation, Conductor }
import from grid.islands { all_elements }


"""Labels of the conductors that bring commercial power onto this site.

Found by walking from every utility substation, so it needs no site knowledge.
"""
def utility_feeders -> list[str] {
    out: list[str] = [];
    for n in all_elements() {
        if not isinstance(n, Substation) { continue; }
        if not (n as Substation).utility_source { continue; }
        for e in [edge n ->:Conductor:->] {
            if e.label not in out { out.append(e.label); }
        }
        for e in [edge n <-:Conductor:<-] {
            if e.label not in out { out.append(e.label); }
        }
    }
    return out;
}


with entry:__main__ {
    _ = root spawn LoadSite(memory_enabled=True);

    feeders = utility_feeders();
    print(f"opening {len(feeders)} utility feeder(s): {', '.join(feeders)}\n");
    for label in feeders {
        _ = root spawn CutConductor(label=label);
    }
    _ = root spawn RunBlue();

    head = root spawn GenerateReport();
    if head.reports {
        r = head.reports[0];
        print(f"determination: {r.determination}");
        print(f"worst assessed: {r.worst_endurance_hours:.1f} h "
              f"against {r.target_hours:.0f} h  (tier-1 exposed={r.tier1_exposed})");
        print(f"curtailed: {r.load_curtailed_kw:.0f} kW of "
              f"{r.load_total_kw:.0f} kW connected\n");
    }

    md = root spawn GetReportMarkdown();
    if md.reports { print(md.reports[0]); }
}
