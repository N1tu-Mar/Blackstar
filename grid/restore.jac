"""BLACKSTART - the restoration pipeline. Heal first, shed only what is left.

A chain of node-keyed walkers, one job each, in the shape CivicMesh uses for
crisis navigation. The isomorphism is exact enough to be worth stating:

    a person in crisis          ->  a tier-1 facility with no path to power
    forty aid programs          ->  the generators and feeds still standing
    eligibility rules           ->  capacity, and whether a tie can carry it
    multi-hop escape route      ->  a restoration path through tie switches
    escalate when no match      ->  escalate when no tie reconnects it

    TriageWalker      who is stranded, and how badly            no AI
    PathfinderWalker  BFS over normally-open ties for a path    no AI
    FeasibilityWalker can the source on that path carry it      no AI
    RestoreWalker     close the ties. THIS is the rerouting.    no AI
    EscalationWalker  nothing reconnects it - now what?         AI, with tools

WHY THE FIRST FOUR HAVE NO MODEL IN THEM

Closing a breaker on a hospital is the same class of act as shedding one, and
the reason BLUE has no model applies here unchanged. A restoration path is
also *checkable*: either a walker can reach a live source across passable
conductors or it cannot, and either the source has the kilowatts or it does
not. Arithmetic answers that better than anything else can.

WHY THE LAST ONE DOES

Escalation runs only after the graph has been exhausted - every tie tried, no
path found. At that point the remaining questions are not electrical. Can load
be deferred rather than dropped? Is there a portable generator, and can it be
sited given what is flooded? Does a neighbouring facility have a spare feed,
and did the same storm take that too? None of that is in the graph, and it is
the same class of world knowledge RED needs to write a plausible hazard.

So the model is invoked at exactly the point where the deterministic system
has provably run out - which is the only place it can add something the
arithmetic could not.
"""

import os;
import from byllm.lib { Model }
import from grid.model {
    GridNode, Substation, Generator, Battery, Facility, Conductor,
    Tick, Event, RestorePath, RestoreResult, EscalationAdvice
}
import from grid.islands { recompute_islands, survey, all_elements, endurance_of }
import from grid.campus { site_target_hours }
import from grid.prov { record_event, record_finding, record_decision }

glob llm: Model = Model(
    model_name=os.environ.get("BLACKSTART_MODEL", "claude-sonnet-5")
);

# How many ties deep to search. Two is enough for any real campus - a path
# needing three switching operations is not something an operator executes
# under storm conditions anyway.
glob MAX_HOPS: int = 2;


# ------------------------------------------------------------------- TRIAGE

"""Tier-1 facilities with no path to any source at all.

Dark, not merely short of target. A facility sitting under the endurance
mandate is BLUE's problem and it sheds around it; one the walker cannot reach
has no power at all and no amount of shedding helps it.
"""
def stranded_critical -> list[Facility] {
    out: list[Facility] = [];
    for f in [root --> [?:Facility]] {
        if f.tier == 1 and f.island_id == -1 and (not f.damaged) {
            out.append(f);
        }
    }
    return sorted(out, key=facility_name);
}


"""Sort key. A named def rather than an inline lambda: the block-lambda form
compiles here but dies at runtime with `name '__jac_lambda_N' is not defined`
when the enclosing def is reached through an import chain."""
def facility_name(f: Facility) -> str {
    return f.name;
}


# --------------------------------------------------------------- PATHFINDER

"""Every tie that is open but could be closed - the candidate escape routes.

A damaged tie is not a candidate: the switch is gone, not merely open. This is
the distinction that keeps the search honest, because RED can destroy a tie as
easily as it can open a breaker.
"""
def open_ties -> list[Conductor] {
    out: list[Conductor] = [];
    for n in all_elements() {
        for e in [edge n ->:Conductor:->] {
            if (not e.closed) and (not e.damaged) { out.append(e); }
        }
    }
    return out;
}


"""Does closing this set of ties give `target` a path to a live source?

Answered by mutating, recomputing, and reading the island id - not by a
separate reachability routine. Islanding is already emergent from traversal,
so the honest way to ask "would this reconnect it" is to close the switch and
let the walker try. The caller restores state; nothing here is left changed.
"""
def reconnects(target: Facility, ties: list[Conductor]) -> bool {
    for t in ties { t.closed = True; }
    recompute_islands();
    ok = target.island_id != -1;
    for t in ties { t.closed = False; }
    recompute_islands();
    return ok;
}


"""Search tie combinations for one that reconnects this facility.

Breadth-first over hop count so the fewest switching operations wins - an
operator closing one breaker under storm conditions is a different proposition
from one closing three. Combinations at each depth are enumerated in a fixed
order, so the same outage always yields the same plan.

This is the Pathfinder pattern: a multi-hop walk over typed edges, run only
when the direct answer has already failed.
"""
def find_path(target: Facility) -> RestorePath {
    cands = open_ties();
    # depth 1: one switching operation
    for c in cands {
        if reconnects(target, [c]) {
            return RestorePath(
                facility=target.name, found=True, hops=1,
                tie_labels=[c.label]
            );
        }
    }
    # depth 2: pairs, in fixed order
    if MAX_HOPS >= 2 {
        for i in range(len(cands)) {
            for j in range(i + 1, len(cands)) {
                pair = [cands[i], cands[j]];
                if reconnects(target, pair) {
                    return RestorePath(
                        facility=target.name, found=True, hops=2,
                        tie_labels=[cands[i].label, cands[j].label]
                    );
                }
            }
        }
    }
    return RestorePath(facility=target.name, found=False, hops=0, tie_labels=[]);
}


# -------------------------------------------------------------- FEASIBILITY

"""Would the island formed by this path actually carry the load?

Reconnecting a facility to a source that cannot serve it is not a restoration,
it is a way to brown out two wings instead of one. Closing a tie merges two
islands, so the test is whether the merged island still clears the mandate
with the restored load on it.
"""
def feasible(target: Facility, ties: list[Conductor]) -> tuple[bool, float] {
    for t in ties { t.closed = True; }
    recompute_islands();
    hours = 0.0;
    ok = False;
    if target.island_id != -1 {
        members: list[GridNode] = [];
        for n in all_elements() {
            if n.island_id == target.island_id { members.append(n); }
        }
        hours = endurance_of(members);
        ok = hours >= site_target_hours();
    }
    for t in ties { t.closed = False; }
    recompute_islands();
    return (ok, hours);
}


"""Resolve tie labels back to the live edges they name."""
def ties_named(labels: list[str]) -> list[Conductor] {
    out: list[Conductor] = [];
    for n in all_elements() {
        for e in [edge n ->:Conductor:->] {
            if e.label in labels and (not e.damaged) { out.append(e); }
        }
    }
    return out;
}


# ----------------------------------------------------------------- RESTORE

"""Close the ties on an approved path, for real, and log it.

The only place in this project that ever closes a breaker. It runs after the
path has been found AND checked for capacity, and it records an Event so the
restoration shows up in the same provenance chain as everything else - an
operator asking "why is the ICU back" gets the same kind of answer as one
asking why the galley went dark.
"""
def apply_path(tick: Tick, target: Facility, path: RestorePath, hours: float) -> None {
    ties = ties_named(path.tie_labels);
    for t in ties { t.closed = True; }
    recompute_islands();
    _ = record_event(
        tick, "restoration", target.name,
        f"closed {', '.join(path.tie_labels)} - {target.name} back on a "
        f"{hours:.1f} h island after {path.hops} switching operation(s)",
        None
    );
    # A Finding and a Decision, not just an Event.
    #
    # `explain` answers a question by finding the most recent Decision naming a
    # subject and walking its evidence back. Restoration that logged only an
    # Event was invisible to it - asking "why is the Emergency Department back"
    # returned "no decision on record, it was never shed", which is true and
    # useless. Closing a breaker on a hospital is a decision and belongs in the
    # audit trail on the same footing as shedding one.
    f = record_finding(
        tick, target.island_id, hours, site_target_hours(),
        hours < site_target_hours(), True
    );
    _ = record_decision(
        tick, "restore", target.name,
        f"tier {target.tier} load was dark; closing "
        f"{', '.join(path.tie_labels)} reconnects it to a source that holds "
        f"{hours:.1f} h against a {site_target_hours():.0f} h target",
        f, target
    );
}


"""The deterministic half of the pipeline, end to end.

Triage -> Pathfinder -> Feasibility -> Restore, for every stranded tier-1
load. Returns what was restored and what is still stranded; the second list is
what escalation is for.
"""
def restore_pass(tick: Tick) -> RestoreResult {
    res = RestoreResult();
    recompute_islands();
    for f in stranded_critical() {
        res.considered.append(f.name);
        # Re-check before acting. Restoring one load usually restores its
        # neighbours - the Emergency Department and Network Core share a
        # switchboard, so the tie that reconnects one reconnects both. The
        # stranded list was computed before any switching, so without this a
        # second, redundant operation gets ordered for a load that is already
        # back. Every avoided switching operation is one fewer thing an
        # operator does wrong in a storm.
        recompute_islands();
        if f.island_id != -1 {
            res.already_restored.append(f.name);
            continue;
        }
        path = find_path(f);
        if not path.found {
            res.unreachable.append(f.name);
            continue;
        }
        ties = ties_named(path.tie_labels);
        (ok, hours) = feasible(f, ties);
        if not ok {
            # A path exists but the source behind it cannot carry the load.
            # Recorded rather than taken: browning out the wing that still
            # works is not an improvement.
            res.infeasible.append(
                f"{f.name} via {', '.join(path.tie_labels)} "
                f"(would leave {hours:.1f} h, under the mandate)"
            );
            continue;
        }
        apply_path(tick, f, path, hours);
        res.restored.append(f.name);
        res.paths.append(path);
    }
    recompute_islands();
    return res;
}


# --------------------------------------------------------------- ESCALATION
# The one place a model runs, and only after the graph is exhausted.

obj EscalationDraft {
    has assessment: str,
        options: list[str],
        rationales: list[str],
        first_action: str;
}

sem EscalationDraft.assessment = "Two sentences on what it means that no switching operation can restore these loads. Say plainly whether this is a topology problem the facility must fix or a transient the storm will lift.";
sem EscalationDraft.options = "Two to four things the duty engineer could do in the next hour that are NOT switching, since switching has already been exhausted. Real actions: relocate a service to a wing that still has power, bring a portable generator to a named location, defer an elective procedure, request mutual aid, run a temporary cable. Each must be specific about what and where.";
sem EscalationDraft.rationales = "One sentence per option, same order and length, saying why it is available given what is damaged and flooded.";
sem EscalationDraft.first_action = "The single option to start in the next fifteen minutes, copied verbatim from your options list.";

"""Advise the duty engineer when no switching operation can restore a load.

The graph has been searched to its limit: every closable tie was tried, alone
and in pairs, and none of them gives these facilities a path to power that can
carry them. Electrical options are gone.

What is left is not an electrical question. Whether a service can move to
another wing, whether a portable set can physically reach a flooded yard,
whether a neighbouring facility is on the same storm and therefore no help,
whether a procedure can be deferred - none of that is in the graph, and it is
the reason a model is worth calling here rather than earlier.

Recommend nothing that requires closing a breaker. That has been tried.
"""
def escalate(
    site: str,
    stranded: list[str],
    damaged: list[str],
    hazard_so_far: list[str]
) -> EscalationDraft by llm(tools=[surviving_capacity, what_is_damaged]);

sem escalate.site = "The facility.";
sem escalate.stranded = "Tier-1 loads with no restorable path to power.";
sem escalate.damaged = "Elements physically destroyed, which cannot be switched back in.";
sem escalate.hazard_so_far = "What has happened to this site, in order.";

# --- tools. Read-only lookups; the model calls these to check itself. ---

"""How much generation is still standing, and on which islands."""
def surviving_capacity -> list[str] {
    recompute_islands();
    out: list[str] = [];
    for i in survey() {
        out.append(
            f"island {i.id}: {i.served_kw:.0f} kW served, "
            f"{i.endurance_hours:.1f} h endurance, "
            f"{'has generation' if i.has_generation else 'no local generation'}"
        );
    }
    return out;
}

"""Which elements are destroyed rather than merely switched out."""
def what_is_damaged -> list[str] {
    out: list[str] = [];
    for n in all_elements() {
        if n.damaged { out.append(f"{n.name} ({n.kind}) - destroyed"); }
    }
    return out if out else ["nothing is destroyed; every loss is a switching state"];
}

sem surviving_capacity = "Current islands with their served load, endurance and whether they have local generation. Call this before recommending anything that needs power from somewhere.";
sem what_is_damaged = "Elements physically destroyed. Destroyed things cannot be switched back in and cannot host equipment. Call this before recommending a location.";
