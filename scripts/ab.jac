"""BLACKSTART - the A/B: does RED's memory actually help?

The honest test of the whole premise. Two identical campuses, three rounds
each. One RED carries its lessons forward; the other plans blind every round.
If memory does not beat no-memory, REFLECT is decoration.

Run it with:  jac run scripts/ab.jac
Costs 12 LLM calls, roughly three minutes.

If the two arms come out level, the usual cause is a graph small enough that
round one already reveals the whole structure. Fix by growing the campus or
hiding more from the dashboard - not by rerunning and hoping.
"""

import from endpoints { LoadSite, RunRound }

glob ROUNDS: int = 3;


"""Play one arm and report endurance after each round."""
def play(memory: bool) -> list[float] {
    _ = root spawn LoadSite(memory_enabled=memory);
    out: list[float] = [];
    label = "MEMORY ON " if memory else "MEMORY OFF";
    for i in range(ROUNDS) {
        res = root spawn RunRound();
        rr = res.reports[0];
        o = rr.outcome;
        out.append(o.endurance_after);
        strikes = ", ".join([f"{s.mechanism}:{s.target_name}" for s in rr.strikes]);
        print(f"  [{label}] round {i + 1}: {o.endurance_before:7.1f}h -> {o.endurance_after:7.1f}h  "
              f"islands={o.islands_formed}  tier1_stranded={o.tier1_stranded}");
        print(f"              struck: {strikes}");
    }
    return out;
}


"""Lowest endurance the site reached across an arm - the number that matters."""
def worst(xs: list[float]) -> float {
    lo = xs[0];
    for x in xs {
        if x < lo { lo = x; }
    }
    return lo;
}


with entry:__main__ {
    print("=== ARM A: memory ON (RED carries lessons forward) ===");
    a = play(True);

    print("\n=== ARM B: memory OFF (RED plans blind every round) ===");
    b = play(False);

    print("\n=== RESULT ===");
    print(f"  memory ON  endurance by round: {[f'{x:.1f}' for x in a]}   worst {worst(a):.1f}h");
    print(f"  memory OFF endurance by round: {[f'{x:.1f}' for x in b]}   worst {worst(b):.1f}h");
    delta = worst(b) - worst(a);
    if delta > 0.5 {
        print(f"  -> memory made RED MORE dangerous: it drove the site {delta:.1f} h lower.");
    } elif delta < (0.0 - 0.5) {
        print(f"  -> memory did NOT help this run: blind RED did {(0.0 - delta):.1f} h better.");
    } else {
        print("  -> no separation. Grow the campus or hide more from the dashboard.");
    }
}
