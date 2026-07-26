"""BLACKSTART - produce the mandated filing from a real cascade.

Run it with:  jac run scripts/report.jac

Needs no API key. Drives the same public walkers the console does, so what
prints here is what a reviewer would be handed:

  load the campus -> take out both utility feeds -> let BLUE respond
  -> project the resulting archive into the filing.

The filing is a projection of the run graph. If the cascade changes, so does
every number and every citation in it, with no separate report state to keep
in sync.
"""

import from endpoints { LoadSite, CutConductor, RunBlue, GetReportMarkdown, GenerateReport }

with entry:__main__ {
    _ = root spawn LoadSite(memory_enabled=True);
    _ = root spawn CutConductor(label="Elizabeth 34.5kV Feeder");
    _ = root spawn CutConductor(label="Effingham 34.5kV Feeder");
    _ = root spawn RunBlue();

    head = root spawn GenerateReport();
    if head.reports {
        r = head.reports[0];
        print(f"determination: {r.determination}");
        print(f"worst assessed: {r.worst_endurance_hours:.1f} h "
              f"against {r.target_hours:.0f} h  "
              f"(tier-1 exposed={r.tier1_exposed})");
        print(f"curtailed: {r.load_curtailed_kw:.0f} kW of "
              f"{r.load_total_kw:.0f} kW connected");
        print("");
    }

    md = root spawn GetReportMarkdown();
    if md.reports { print(md.reports[0]); }
}
