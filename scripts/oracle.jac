"""BLACKSTART - ORACLE alone: the bound on achievable damage, with no model.

Run it with:  jac run scripts/oracle.jac

Needs no API key and makes no network call, which makes it the one part of the
system that is demonstrable when the model is unreachable.

What it prints, in order:

  1. the baseline endurance of the healthy campus;
  2. the worst single strike, searched exhaustively;
  3. the worst two-strike chain, beam-searched;
  4. a restore check -- the grid must be byte-identical to how it started, or
     every dry-run above silently corrupted the live scenario.

Step 4 is the one to watch. Everything else is a number; that one is a proof
that the search is safe to run mid-demo.
"""

import from grid.campus { reset_campus, site_name, site_target_hours }
import from grid.islands { recompute_islands, survey, site_endurance, all_elements }
import from grid.oracle {
    worst_chain, candidate_strikes, take_snapshot, evaluate, ChainStep
}


"""Compare two snapshots field by field. Returns the first mismatch, or ''."""
def snapshot_diff(a: object, b: object) -> str {
    fields = [
        "elem_damaged", "elem_island", "sub_live", "gen_online", "gen_fuel",
        "gen_reach", "batt_kwh", "fac_shed", "cond_closed", "cond_damaged",
        "cond_passable"
    ];
    for f in fields {
        if getattr(a, f) != getattr(b, f) { return f; }
    }
    return "";
}


with entry:__main__ {
    _ = reset_campus();
    recompute_islands();
    target = site_target_hours();
    baseline = site_endurance(survey());

    print(f"site:      {site_name()}");
    print(f"elements:  {len(all_elements())}");
    print(f"target:    {target:.0f} h");
    print(f"baseline:  {baseline:.1f} h");

    before = take_snapshot();
    cands = candidate_strikes();
    print(f"\nplausible single strikes: {len(cands)}");

    # --- depth 1, exhaustive -------------------------------------------------
    d1 = worst_chain(1, 8);
    print(f"\n=== worst single strike  ({d1.searched} chains simulated) ===");
    print(f"  {d1.best.label}");
    print(f"  endurance {baseline:.1f} h -> {d1.best.endurance_after:.1f} h"
          f"   islands={d1.best.islands_formed}"
          f"   tier1_stranded={d1.best.tier1_stranded}"
          f"   curtailed={d1.best.shed_count}");

    # --- depth 2, beam -------------------------------------------------------
    d2 = worst_chain(2, 6);
    print(f"\n=== worst two-strike chain  ({d2.searched} chains simulated) ===");
    print(f"  {d2.best.label}");
    print(f"  endurance {baseline:.1f} h -> {d2.best.endurance_after:.1f} h"
          f"   islands={d2.best.islands_formed}"
          f"   tier1_stranded={d2.best.tier1_stranded}"
          f"   curtailed={d2.best.shed_count}");

    if d2.best.endurance_after < d1.best.endurance_after {
        print(f"  -> the second strike is worth "
              f"{d1.best.endurance_after - d2.best.endurance_after:.1f} h of further damage");
    } else {
        print("  -> a second strike bought the adversary nothing at this budget");
    }

    # --- campus design check ------------------------------------------------
    # The memory A/B can only measure learning if round 1 does not already end
    # the campaign. This is the check that had to be discovered by observing a
    # null A/B twice; running it takes seconds and needs no API key.
    print(f"\n=== campus design check ===");
    if d1.best.tier1_stranded or d1.best.endurance_after <= 0.001 {
        print(f"  ONE-STRIKE KILL: '{d1.best.label}' strands life-critical load on its own.");
        print( "  A single move ends the campaign, so RED has nothing left to learn in");
        print( "  later rounds and the memory A/B will saturate at zero for both arms.");
        print( "  Fix the topology (add a redundant path or sectionalize) rather than");
        print( "  re-running the A/B and hoping for separation.");
    } elif d1.best.endurance_after < target {
        print(f"  one strike takes the site under its {target:.0f} h requirement "
              f"({d1.best.endurance_after:.1f} h) but does not strand tier 1.");
        print( "  Graded response survives, so the A/B has room to measure learning.");
    } else {
        print(f"  no single strike breaches the {target:.0f} h requirement. "
              f"The campus is robust to one move.");
    }

    # --- the part that matters: did every dry-run undo itself? --------------
    after = take_snapshot();
    drift = snapshot_diff(before, after);
    print(f"\n=== restore check ===");
    if drift == "" {
        print(f"  clean: grid identical after {d1.searched + d2.searched} dry-runs");
    } else {
        print(f"  CORRUPTED: '{drift}' differs after the search. Do not trust the numbers above.");
    }
}
