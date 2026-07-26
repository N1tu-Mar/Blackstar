import from endpoints { LoadSite, RunRound, ExplainWhy }

with entry:__main__ {
    first_shed = "";
    r0 = root spawn LoadSite(memory_enabled=True);
    d0 = r0.reports[0];
    print(f"BASELINE  endurance={d0.site_endurance_hours:.1f}h  islands={len(d0.islands)}");

    for i in [1, 2] {
        res = root spawn RunRound();
        rr = res.reports[0];
        print(f"\n=== ROUND {rr.round_index}  [{rr.scenario_name}]");
        print(f"  hazard: {rr.hazard}");
        for s in rr.strikes {
            print(f"    -> {s.mechanism} on '{s.target_name}': {s.rationale[:80]}");
        }
        o = rr.outcome;
        print(f"  endurance {o.endurance_before:.1f}h -> {o.endurance_after:.1f}h  islands={o.islands_formed}  tier1_stranded={o.tier1_stranded}");
        print(f"  BLUE shed: {o.shed_actions}");
        if len(o.shed_actions) > 0 and first_shed == "" { first_shed = o.shed_actions[0]; }
        print(f"  breach={rr.breach}  unresolved={o.unresolved_targets}");
        print(f"  rejected={o.rejected_strikes}");
        print(f"  LESSON: {rr.lesson.revision[:200]}");
    }

    print(f"\n=== EXPLAIN: {first_shed}");
    ex = root spawn ExplainWhy(subject=first_shed);
    for line in ex.reports[0].lines { print(f"  [{line.ref}] {line.text}"); }
}
