"""BLACKSTART - what the campaign never tested.

Run it with:  jac run scripts/coverage.jac

Needs no API key. Reports the blind spot in a red-team exercise: every element
a single plausible strike can hurt, split by whether RED ever tried it.

The advisor answers "what did we learn from the attacks we ran". This answers
"what did we never attack", and only the second one can find the element that
ends the site in one move without anybody having guessed to aim there.
"""

import from grid.campus { reset_campus, site_name }
import from grid.oracle { coverage }

with entry:__main__ {
    _ = reset_campus();
    cov = coverage(6);

    print(f"site:      {site_name()}");
    print(f"elements:  {cov.elements_total}");
    print(f"exercised: {cov.elements_struck} by {cov.rounds_run} RED scenario(s)");
    print("");
    print(cov.summary);

    if len(cov.blindspots) > 0 {
        print("\n=== never tested by RED, and damaging ===");
        for b in cov.blindspots {
            flag = "STRANDS TIER 1" if b.strands_tier1 else "under requirement";
            print(f"  {b.element_name} ({b.kind})");
            print(f"      {b.mechanism} -> {b.endurance_after:.1f} h   [{flag}]");
        }
    }

    if len(cov.exercised) > 0 {
        print("\n=== already exercised by RED ===");
        for b in cov.exercised {
            print(f"  {b.element_name} ({b.kind}) - {b.mechanism} -> {b.endurance_after:.1f} h");
        }
    }
}
