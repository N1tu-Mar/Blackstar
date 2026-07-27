"""BLACKSTART - the whole agentic pipeline, end to end.

    jac run scripts/pipeline.jac

Drives every stage in order and prints only the lines that matter:

    RED         plans a hazard, learns from what survived      2 model calls/round
    RESTORE     switches around the cut where it can           no model
    ESCALATE    when no switching operation is left            1 model call, w/ tools
    ADVISOR     what to build so it stops happening            1 model call

The point of running them together is the handoff. Restoration is model-free
and reports honestly when it has exhausted every closable tie; only then does
escalation run. So the model is invoked at exactly the point the arithmetic
provably ran out, and you can see the boundary in the output.
"""

import from endpoints {
    LoadSite, RunRound, GetEscalation, GetHardeningPlan, ExplainWhy
}

glob ROUNDS: int = 2;


"""Trim a long model sentence for terminal output."""
def clip(s: str, n: int) -> str {
    return s if len(s) <= n else s[:n] + "...";
}


with entry:__main__ {
    d0 = (root spawn LoadSite(memory_enabled=True)).reports[0];
    print(f"SITE      {d0.site}");
    print(f"BASELINE  {d0.site_endurance_hours:.1f} h against a "
          f"{d0.target_hours:.0f} h mandate\n");

    for i in range(ROUNDS) {
        rr = (root spawn RunRound()).reports[0];
        o = rr.outcome;
        print(f"--- ROUND {rr.round_index}: {rr.scenario_name}");
        print(f"    hazard    {clip(rr.hazard, 90)}");
        for s in rr.strikes {
            flag = "   <- no damage on its own" if s.immediate_damage == "none" else "";
            print(f"    strike    {s.mechanism} on {s.target_name}{flag}");
        }
        for why in o.rejected_strikes {
            print(f"    REFUSED   {why}");
        }
        print(f"    result    {o.endurance_before:.1f} h -> {o.endurance_after:.1f} h, "
              f"{o.islands_formed} islands, tier1_stranded={o.tier1_stranded}");
        # Calibration: RED commits a number before the arithmetic runs.
        if o.prediction_error_hours >= 0.0 {
            print(f"    forecast  predicted {rr.predicted_endurance_hours:.1f} h, "
                  f"measured {o.endurance_after:.1f} h "
                  f"(off by {o.prediction_error_hours:.1f} h)");
        }
        if len(o.shed_actions) > 0 {
            print(f"    BLUE shed {', '.join(o.shed_actions)}");
        }
        print(f"    LESSON    {clip(rr.lesson.revision, 200)}\n");
    }

    print("=" * 70);
    print("  ESCALATION - only runs once switching has been exhausted");
    print("=" * 70);
    e = (root spawn GetEscalation()).reports[0];
    print(f"  author    {e.authored_by}");
    print(f"  {clip(e.assessment, 300)}\n");
    for (i, opt) in enumerate(e.options) {
        why = e.rationales[i] if i < len(e.rationales) else "";
        print(f"    {i + 1}. {opt}");
        if why != "" { print(f"       why: {clip(why, 150)}"); }
    }
    if e.first_action != "" {
        print(f"\n  START WITH: {e.first_action}");
    }

    print("\n" + "=" * 70);
    print("  ADVISOR - what to build so this stops happening");
    print("=" * 70);
    p = (root spawn GetHardeningPlan()).reports[0];
    print(f"  author    {p.authored_by}");
    print(f"  {clip(p.assessment, 300)}\n");
    print(f"  SINGLE POINT OF FAILURE: {p.single_point_of_failure}\n");
    print("  Ranked by the graph (arithmetic, no model):");
    for v in p.vulnerabilities {
        print(f"    {v.element_name} ({v.kind}) - struck in {v.times_struck} of "
              f"{v.scenarios_total}; worst {v.worst_endurance_after:.1f} h; "
              f"stranded critical care in {v.tier1_rounds}");
    }
    if len(p.measures) > 0 {
        print("\n  Recommended (world knowledge, the model's half):");
        for (i, m) in enumerate(p.measures) {
            print(f"    {i + 1}. {clip(m, 160)}");
        }
    }
    print("");
}
