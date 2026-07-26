"""BLACKSTART - Provenance archive and backward explanation.

Every state change, finding, and decision is a node with edges to its
evidence. There are no log files here and no database: `root ++> x` is the
entire persistence story, and the audit trail is the graph.

`explain` answers "why did the Galley go dark" by walking backward from the
shed decision through the finding that justified it, to the tick it was
derived from, to the events that landed on that tick. Every rendered line
carries the id of the node it came from - the difference between a summary
and evidence.

Narration is templated, not generated. An LLM in this path would undermine the
point of the chain being the truth.
"""

import from grid.model {
    Run, Round, Tick, Event, Finding, Decision, LessonNode, Facility, IslandView,
    Next, AtTick, EventAt, FindingAt, DecisionAt, Because, DerivedFrom, Caused,
    Affected, HasRound, Learned, HasTick, HasEvent,
    Explanation, ExplainLine, Lesson
}


"""The active Run, or None before a campus is loaded."""
def active_run -> Run | None {
    runs = [root --> [?:Run]];
    return runs[0] if len(runs) > 0 else None;
}


"""Short citation ref for a node, e.g. 'd311'."""
def ref_of(prefix: str, n: Tick | Event | Finding | Decision) -> str {
    return f"{prefix}{str(jid(n))[-4:]}";
}


"""Open a new tick snapshot and chain it after the previous one."""
def write_tick(run: Run, t: int, endurance: float, island_count: int, served: float) -> Tick {
    tick = Tick(t=t, site_endurance_hours=endurance, island_count=island_count, served_kw=served);
    run +>:HasTick:+> tick;
    prior = [run ->:HasTick:->];
    # Chain the temporal spine: newest tick follows the one before it.
    best: Tick | None = None;
    for p in prior {
        if p.t < t {
            if best is None or p.t > (best as Tick).t { best = p; }
        }
    }
    if best is not None { (best as Tick) +>:Next:+> tick; }
    return tick;
}


"""Record something that happened to the grid."""
def record_event(tick: Tick, kind: str, target: str, detail: str, cause: Event | None) -> Event {
    ev = Event(t=tick.t, kind=kind, target=target, detail=detail);
    root ++> ev;
    ev +>:EventAt:+> tick;
    if cause is not None { (cause as Event) +>:Caused:+> ev; }
    return ev;
}


"""Record an endurance assessment for one island at one tick."""
def record_finding(tick: Tick, island_id: int, endurance: float, target: float,
                   breach: bool, tier1: bool) -> Finding {
    f = Finding(t=tick.t, island_id=island_id, endurance_hours=endurance,
                target_hours=target, breach=breach, tier1_present=tier1);
    root ++> f;
    f +>:FindingAt:+> tick;
    f +>:DerivedFrom:+> tick;
    return f;
}


"""Record a BLUE action and link it to the finding that justified it."""
def record_decision(tick: Tick, action: str, subject: str, rule: str,
                    because: Finding | None, target: Facility | None) -> Decision {
    d = Decision(t=tick.t, action=action, subject=subject, rule=rule);
    root ++> d;
    d +>:DecisionAt:+> tick;
    if because is not None { d +>:Because:+> (because as Finding); }
    if target is not None { d +>:Affected:+> (target as Facility); }
    return d;
}


"""Open a new adversary round on the run."""
def open_round(run: Run, index: int, name: str, hazard: str, expectation: str) -> Round {
    r = Round(index=index, scenario_name=name, hazard=hazard, expectation=expectation);
    run +>:HasRound:+> r;
    return r;
}


"""Persist a lesson learned in a round. LLM objs never become nodes directly."""
def record_lesson(rnd: Round, lesson: Lesson) -> LessonNode {
    ln = LessonNode(round_index=rnd.index, hypothesis=lesson.hypothesis,
                    observed=lesson.observed, revision=lesson.revision,
                    confidence=lesson.confidence);
    rnd +>:Learned:+> ln;
    return ln;
}


"""Every lesson so far, oldest first - RED's memory."""
def all_lessons -> list[Lesson] {
    out: list[Lesson] = [];
    run = active_run();
    if run is None { return out; }
    rounds = [(run as Run) ->:HasRound:->];
    ordered = sorted(rounds, key=lambda (r: Round) -> int { return r.index; });
    for r in ordered {
        for ln in [r ->:Learned:->] {
            out.append(Lesson(hypothesis=ln.hypothesis, observed=ln.observed,
                              revision=ln.revision, confidence=ln.confidence));
        }
    }
    return out;
}


"""Walk backward from a facility's fate to the event that caused it.

Returns cited lines, most recent decision first, then the finding that
justified it, then the events on that tick and whatever caused them.
"""
def explain(subject: str) -> Explanation {
    out = Explanation(subject=subject, found=False, lines=[]);

    # Most recent decision naming this subject.
    latest: Decision | None = None;
    for d in [root --> [?:Decision]] {
        if d.subject != subject { continue; }
        if latest is None or d.t > (latest as Decision).t { latest = d; }
    }
    if latest is None {
        out.lines.append(ExplainLine(ref="-", text=f"No decision on record for '{subject}'. It was never shed."));
        return out;
    }

    out.found = True;
    d = latest as Decision;
    out.lines.append(ExplainLine(
        ref=ref_of("d", d),
        text=f"t={d.t}  {d.action} {d.subject} - rule: {d.rule}"
    ));

    # The finding that justified it.
    ticks: list[Tick] = [];
    for f in [d ->:Because:->] {
        out.lines.append(ExplainLine(
            ref=ref_of("f", f),
            text=f"island {f.island_id} endurance {f.endurance_hours:.1f} h against a {f.target_hours:.0f} h target"
        ));
        for tk in [f ->:DerivedFrom:->] { ticks.append(tk); }
    }

    # The events that landed on that tick, and their causes.
    for tk in ticks {
        evs = [tk <-:EventAt:<-];
        ordered = sorted(evs, key=lambda (e: Event) -> str { return e.kind; });
        for e in ordered {
            out.lines.append(ExplainLine(
                ref=ref_of("e", e),
                text=f"t={e.t}  {e.kind}: {e.target} - {e.detail}"
            ));
            for c in [e <-:Caused:<-] {
                out.lines.append(ExplainLine(
                    ref=ref_of("e", c),
                    text=f"t={c.t}  caused by {c.kind}: {c.target} - {c.detail}"
                ));
            }
        }
    }

    return out;
}
