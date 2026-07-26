"""BLACKSTART - The mandated report, generated from the provenance graph.

Invariant 5 says every decision is a node with edges to its evidence, and gives
two reasons: the "ask why" demo, and the compliance product wedge. The first was
built (`prov.explain`). This is the second.

Naval Medical Center Portsmouth owes two filings on the same building:

  10 U.S.C. Sec. 2925(a)  -- energy resilience: how long the mission survives
                             without commercial power, what the installation
                             would curtail to get there, and what it learned
                             from exercising it.
  42 CFR 482.15 (CMS)     -- emergency preparedness: a documented plan, tested,
                             and reviewed, with the results on record.

Both are produced today by an engineer reading SCADA logs for three weeks after
the fact. Every fact either filing wants is already a node in this graph the
moment a scenario finishes running. This file is a second reader over the same
archive `explain` walks -- no new state, no new simulation, and no model.

Two properties make the output an audit artifact rather than a summary:

  * Every determination cites the node it came from, in `[f31a]` form, using the
    same refs `explain` prints. A reviewer can walk from any line in the report
    back to the tick and the event that produced it.
  * Nothing here is generated prose. An LLM in this path would make the filing
    an assertion about the run instead of a projection of it. RED's lessons
    appear as quoted findings from the exercise, attributed to the round that
    produced them, and nowhere else.

The report is deliberately willing to say the site failed. A filing that can
only conclude "compliant" is not evidence of anything.
"""

import from grid.model {
    GridNode, Facility, Generator, Battery, Substation,
    Run, Round, Tick, Event, Finding, Decision, LessonNode,
    HasTick, HasRound, Learned, Because, Affected, DecisionAt, FindingAt, EventAt,
    Caused, ExplainLine, IslandView
}
import from grid.prov { active_run, ref_of }
import from grid.islands {
    all_elements, recompute_islands, survey, site_endurance, dark_facilities,
    UTILITY_HOURS
}
import from grid.campus { site_name, site_target_hours, site_config }


# --------------------------------------------------------------- report shape

"""One filing section: a mandate it answers, prose, and cited evidence."""
obj ReportSection {
    has title: str,
        mandate: str = "",
        body: list[str] = [],
        cited: list[ExplainLine] = [];
}


"""The whole filing, ready to render or hand to a reviewer."""
obj ComplianceReport {
    has site: str,
        target_hours: float = 96.0,
        assessed: bool = False,
        determination: str = "",
        worst_endurance_hours: float = 0.0,
        margin_hours: float = 0.0,
        current_endurance_hours: float = 0.0,
        met_target: bool = False,
        tier1_exposed: bool = False,
        assessments_recorded: int = 0,
        assessments_below_target: int = 0,
        rounds_exercised: int = 0,
        elements_total: int = 0,
        load_total_kw: float = 0.0,
        load_curtailed_kw: float = 0.0,
        sections: list[ReportSection] = [];
}


"""Which reporting regimes this site is actually subject to.

A ship repair yard owes 10 U.S.C. 2925 and does not owe the CMS emergency
preparedness rule -- it is not a hospital. Citing 42 CFR 482.15 on a shipyard is
the kind of error that costs credibility with the one reader who would notice, so
the site file declares its own regimes and the filing only cites those.
"""
def mandates -> list {
    return site_config().get("mandates", ["2925", "cms"]);
}


"""True when the CMS emergency preparedness rule applies to this site."""
def cms_applies -> bool {
    return "cms" in mandates();
}


# ------------------------------------------------------------------- gathering

"""Citation ref for archive nodes outside `prov.ref_of`'s union."""
def ref_node(prefix: str, n: Round | LessonNode) -> str {
    return f"{prefix}{str(jid(n))[-4:]}";
}


"""Every endurance assessment on record, oldest first.

`Finding` is the authoritative endurance record rather than `Tick`: a tick
opened by a manual cut carries a placeholder of 0.0 that is never revised,
whereas a finding is only ever written with a measured number.
"""
def finding_order(f: Finding) -> int {
    return f.t * 1000 + f.island_id;
}


"""Every endurance assessment on record, oldest first."""
def all_findings -> list[Finding] {
    return sorted([root --> [?:Finding]], key=finding_order);
}


"""Every recorded event, oldest first."""
def event_order(e: Event) -> int {
    return e.t;
}


"""Every recorded event, oldest first."""
def all_events -> list[Event] {
    return sorted([root --> [?:Event]], key=event_order);
}


"""Every BLUE decision, in the order it was taken."""
def decision_order(d: Decision) -> int {
    return d.t;
}


"""Every BLUE decision, in the order it was taken."""
def all_decisions -> list[Decision] {
    return sorted([root --> [?:Decision]], key=decision_order);
}


"""Every adversary round on the active run, oldest first."""
def round_order(r: Round) -> int {
    return r.index;
}


"""Every adversary round on the active run, oldest first."""
def run_rounds(run: Run) -> list[Round] {
    return sorted([run ->:HasRound:->], key=round_order);
}


"""Site-level assessments: the worst island carrying tier-1 load, per tick.

A finding on an island with no critical load says nothing about whether the
mission survives, so it is not a site-level assessment and is excluded here.
"""
def site_assessments -> list[Finding] {
    worst_by_tick: dict[int, Finding] = {};
    for f in all_findings() {
        if not f.tier1_present { continue; }
        held = worst_by_tick.get(f.t);
        if held is None or f.endurance_hours < (held as Finding).endurance_hours {
            worst_by_tick[f.t] = f;
        }
    }
    out: list[Finding] = [];
    for t in sorted(worst_by_tick.keys()) { out.append(worst_by_tick[t]); }
    return out;
}


# -------------------------------------------------------------------- sections

"""Section 1 - the determination, and the assessment that produced it."""
def section_determination(rep: ComplianceReport, assessments: list[Finding]) -> ReportSection {
    sec = ReportSection(
        title="1. Determination",
        mandate="10 U.S.C. 2925(a)(1) - duration the mission can be sustained without commercial power"
    );

    if not rep.assessed {
        sec.body.append(
            "No endurance assessment is on record for this run. Run the controller "
            "or an adversary round before filing: this report projects the archive, "
            "it does not estimate."
        );
        return sec;
    }

    verdict = "MEETS" if rep.met_target else "DOES NOT MEET";
    sec.body.append(
        f"{rep.site} {verdict} its mandated endurance requirement of "
        f"{rep.target_hours:.0f} hours."
    );
    sec.body.append(
        "Worst assessed endurance while carrying life-critical load: "
        f"{rep.worst_endurance_hours:.1f} hours "
        f"({abs(rep.margin_hours):.1f} hours "
        f"{'above' if rep.margin_hours >= 0.0 else 'below'} the requirement)."
    );
    sec.body.append(
        f"{rep.assessments_below_target} of {rep.assessments_recorded} recorded "
        "assessments fell below the requirement."
    );
    if rep.tier1_exposed {
        sec.body.append(
            "At least one life-critical area was left unpowered or below the "
            "endurance requirement during this run. This is a reportable "
            "mission-impact condition, not a margin finding."
        );
    }

    # Cite the assessment that set the headline number.
    worst: Finding | None = None;
    for f in assessments {
        if worst is None or f.endurance_hours < (worst as Finding).endurance_hours {
            worst = f;
        }
    }
    if worst is not None {
        w = worst as Finding;
        sec.cited.append(ExplainLine(
            ref=ref_of("f", w),
            text=f"t={w.t}  island {w.island_id} assessed at {w.endurance_hours:.1f} h "
                 f"against a {w.target_hours:.0f} h requirement; "
                 f"breach={w.breach}, life-critical load present={w.tier1_present}"
        ));
    }
    return sec;
}


"""Section 2 - which life-critical areas were affected, and how."""
def section_mission_impact(rep: ComplianceReport) -> ReportSection {
    sec = ReportSection(
        title="2. Mission impact",
        mandate="10 U.S.C. 2925(a)(2) - effect on mission-critical functions"
    );

    recompute_islands();
    dark_names: list[str] = [];
    for f in dark_facilities() { dark_names.append(f.name); }

    critical: list[Facility] = [];
    for f in [root --> [?:Facility]] {
        if f.tier == 1 { critical.append(f); }
    }

    exposed = 0;
    for f in critical {
        state = "sustained";
        if f.name in dark_names { state = "DE-ENERGIZED"; }
        elif f.shed { state = "CURTAILED"; }
        if state != "sustained" { exposed += 1; }
        sec.body.append(f"  {f.name} ({f.category}, {f.kw:.0f} kW) - {state}");
    }
    # Status is read from the FINAL state of the run. It is a separate question
    # from the determination in section 1, which is the worst assessment reached
    # at any point. Conflating them produces a filing that says a hospital was
    # never at risk because the controller recovered it in time.
    sec.body.insert(0, (
        f"{len(critical)} areas are designated life-critical (tier 1). "
        f"In the final state of this run, {exposed} were not being served."
    ));

    if exposed == 0 and rep.met_target {
        sec.body.append(
            "No life-critical area lost power at any point, and the requirement was "
            "met throughout. Curtailment fell entirely on tier 2 and tier 3 load."
        );
    } elif exposed == 0 {
        sec.body.append(
            f"Every life-critical area was being served by the end of the run, but "
            f"the site passed through {rep.worst_endurance_hours:.1f} h against a "
            f"{rep.target_hours:.0f} h requirement on the way there. Recovery by the "
            f"controller does not discharge the reporting obligation: the exposure "
            f"in section 1 occurred and is the reportable condition."
        );
    }

    # Cite every breaching assessment - these are the mission-impact records.
    for f in all_findings() {
        if not f.breach { continue; }
        sec.cited.append(ExplainLine(
            ref=ref_of("f", f),
            text=f"t={f.t}  island {f.island_id} carried life-critical load at "
                 f"{f.endurance_hours:.1f} h, below the {f.target_hours:.0f} h requirement"
        ));
    }
    return sec;
}


"""Section 3 - the curtailment actions, each with the arithmetic that forced it.

This is the section a reviewer actually argues with, so every action carries
the endurance assessment it was derived from rather than a policy citation.
"""
def section_curtailment(rep: ComplianceReport) -> ReportSection {
    sec = ReportSection(
        title="3. Load curtailment actions",
        mandate="10 U.S.C. 2925(a)(3) - load the installation would curtail to sustain the mission"
    );

    decisions = all_decisions();
    shed_actions: list[Decision] = [];
    for d in decisions {
        if d.action == "shed" { shed_actions.append(d); }
    }

    if len(shed_actions) == 0 {
        sec.body.append("No load was curtailed during this run.");
        return sec;
    }

    sec.body.append(
        f"{len(shed_actions)} curtailment actions were taken, in the order shown. "
        f"Total curtailed load: {rep.load_curtailed_kw:.0f} kW."
    );
    sec.body.append(
        "No life-critical (tier 1) load was curtailed. The controller will report "
        "a breach rather than curtail tier 1."
    );

    step = 1;
    for d in shed_actions {
        sec.cited.append(ExplainLine(
            ref=ref_of("d", d),
            text=f"step {step}  t={d.t}  {d.action} {d.subject} - {d.rule}"
        ));
        # The finding that justified it, so the chain is one hop deep in the filing.
        for f in [d ->:Because:->] {
            sec.cited.append(ExplainLine(
                ref=ref_of("f", f),
                text=f"        derived from: island {f.island_id} at "
                     f"{f.endurance_hours:.1f} h against {f.target_hours:.0f} h"
            ));
        }
        step += 1;
    }
    return sec;
}


"""Section 4 - the sequence of events, replacing the log archaeology."""
def section_sequence -> ReportSection {
    sec = ReportSection(
        title="4. Sequence of events",
        mandate=("42 CFR 482.15(d) - record of the event and the response"
                 if cms_applies() else "10 U.S.C. 2925(a) - record of the event and the response")
    );

    events = all_events();
    if len(events) == 0 {
        sec.body.append("No events are on record for this run.");
        return sec;
    }

    sec.body.append(
        f"{len(events)} events are on record, reconstructed from the run graph "
        "rather than from operator logs."
    );
    for e in events {
        line = f"t={e.t}  {e.kind}: {e.target} - {e.detail}";
        # An event caused by an earlier one records that link; surface it, since
        # the causal chain is the part a reviewer cannot get from a flat log.
        causes = [e <-:Caused:<-];
        if len(causes) > 0 {
            names: list[str] = [];
            for c in causes { names.append(c.target); }
            line += f"  (following: {', '.join(names)})";
        }
        sec.cited.append(ExplainLine(ref=ref_of("e", e), text=line));
    }
    return sec;
}


"""Section 5 - the adversarial exercise and what it exposed.

CMS wants the plan tested and reviewed. This is the test record: the scenarios
that were run, and the structural weakness each one exposed, quoted from the
round that produced it.
"""
def section_exercise(run: Run) -> ReportSection {
    sec = ReportSection(
        title="5. Adversarial exercise record",
        mandate=("42 CFR 482.15(d)(2) - testing of the emergency preparedness plan; "
                 "10 U.S.C. 2925(a)(4) - vulnerabilities identified"
                 if cms_applies() else
                 "10 U.S.C. 2925(a)(4) - vulnerabilities identified")
    );

    rounds = run_rounds(run);
    if len(rounds) == 0 {
        sec.body.append(
            "No adversarial rounds were exercised in this run. The endurance "
            "determination above reflects only the failures explicitly applied."
        );
        return sec;
    }

    sec.body.append(
        f"{len(rounds)} scenarios were exercised against the campus. Scenarios were "
        "generated against an observer's view of the site -- facility names, "
        "lit/dark status and endurance only, with no access to the "
        "single-line diagram."
    );
    if not run.memory_enabled {
        sec.body.append(
            "Note: this run was exercised with scenario memory disabled, so each "
            "scenario was planned without reference to earlier findings."
        );
    }

    for r in rounds {
        sec.cited.append(ExplainLine(
            ref=ref_node("r", r),
            text=f"round {r.index}  '{r.scenario_name}' - {r.hazard}"
        ));
        for ln in [r ->:Learned:->] {
            sec.cited.append(ExplainLine(
                ref=ref_node("l", ln),
                text=f"        finding (confidence {ln.confidence:.2f}): {ln.revision}"
            ));
        }
    }
    return sec;
}


"""Section 6 - basis of determination. The paragraph an accreditor reads first."""
def section_basis(rep: ComplianceReport) -> ReportSection {
    sec = ReportSection(
        title="6. Basis of determination",
        mandate="Method statement"
    );

    sec.body.append(
        "Endurance is computed arithmetically from generation capacity, fuel on "
        "hand, stored energy and served load, per electrical island. No language "
        "model participates in the endurance calculation or in any curtailment "
        "decision. The curtailment order is fixed: highest tier number first, "
        "largest load first within a tier, and tier 1 never."
    );
    sec.body.append(
        "Electrical islands are not computed by a partitioning routine. They are "
        "the reachable sets of a traversal restricted to passable conductors, so "
        "an open conductor is not an edge the traversal declines to cross -- it "
        "is one it cannot see. Islanding therefore cannot drift out of agreement "
        "with switch state."
    );
    sec.body.append(
        "Language models were used only to generate the exercise scenarios in "
        "section 5 and to state the structural weakness each one exposed. Every "
        "number in sections 1 through 4 is arithmetic over recorded state."
    );
    sec.body.append(
        "Every line above carries the identifier of the archive node it was read "
        "from. This filing is a projection of the run graph, not a summary "
        f"written about it: {rep.assessments_recorded} assessments, "
        f"{len(all_events())} events and {len(all_decisions())} decisions were "
        "read to produce it."
    );
    return sec;
}


# ------------------------------------------------------------------- assembly

"""Build the filing for the active run."""
def build_report -> ComplianceReport {
    target = site_target_hours();
    rep = ComplianceReport(site=site_name(), target_hours=target);

    run = active_run();
    if run is None {
        rep.determination = "No run on record.";
        rep.sections.append(section_determination(rep, []));
        return rep;
    }
    r = run as Run;

    # Inventory, from live grid state.
    recompute_islands();
    elements = all_elements();
    rep.elements_total = len(elements);
    for n in elements {
        if isinstance(n, Facility) {
            f = n as Facility;
            rep.load_total_kw += f.kw;
            if f.shed { rep.load_curtailed_kw += f.kw; }
        }
    }
    rep.current_endurance_hours = site_endurance(survey());

    # Determination, from the assessment archive.
    assessments = site_assessments();
    rep.assessments_recorded = len(assessments);
    rep.assessed = len(assessments) > 0;
    rep.rounds_exercised = len(run_rounds(r));

    if rep.assessed {
        worst = assessments[0].endurance_hours;
        below = 0;
        for f in assessments {
            if f.endurance_hours < worst { worst = f.endurance_hours; }
            if f.endurance_hours < target { below += 1; }
            if f.breach { rep.tier1_exposed = True; }
        }
        rep.worst_endurance_hours = worst;
        rep.margin_hours = worst - target;
        rep.assessments_below_target = below;
        rep.met_target = worst >= target;
    }

    for f in dark_facilities() {
        if f.tier == 1 { rep.tier1_exposed = True; }
    }
    if rep.tier1_exposed { rep.met_target = False; }

    rep.determination = (
        f"{'MEETS' if rep.met_target else 'DOES NOT MEET'} the "
        f"{target:.0f}-hour requirement"
    ) if rep.assessed else "NOT ASSESSED";

    rep.sections.append(section_determination(rep, assessments));
    rep.sections.append(section_mission_impact(rep));
    rep.sections.append(section_curtailment(rep));
    rep.sections.append(section_sequence());
    rep.sections.append(section_exercise(r));
    rep.sections.append(section_basis(rep));
    return rep;
}


"""Render the filing as markdown, ready to hand to a reviewer or paste into a filing."""
def render_markdown(rep: ComplianceReport) -> str {
    out: list[str] = [];
    out.append("# Energy resilience and emergency preparedness report");
    out.append("");
    out.append(f"**Installation:** {rep.site}");
    out.append(f"**Mandated endurance requirement:** {rep.target_hours:.0f} hours");
    out.append(f"**Determination:** {rep.determination}");
    if rep.assessed {
        out.append(
            f"**Worst assessed endurance:** {rep.worst_endurance_hours:.1f} h "
            f"({abs(rep.margin_hours):.1f} h "
            f"{'margin' if rep.margin_hours >= 0.0 else 'shortfall'})"
        );
    }
    out.append(
        f"**Scope:** {rep.elements_total} elements, {rep.load_total_kw:.0f} kW "
        f"connected load, {rep.load_curtailed_kw:.0f} kW curtailed, "
        f"{rep.rounds_exercised} scenarios exercised"
    );
    out.append("");
    out.append(
        ("Statutory basis: 10 U.S.C. 2925(a) (energy resilience reporting) and "
         "42 CFR 482.15 (CMS emergency preparedness). "
         if cms_applies() else
         "Statutory basis: 10 U.S.C. 2925(a) (energy resilience reporting). ")
        + "Bracketed identifiers refer to nodes in the run archive and can be "
          "walked back to their cause."
    );
    out.append("");

    for sec in rep.sections {
        out.append(f"## {sec.title}");
        if sec.mandate != "" {
            out.append("");
            out.append(f"*{sec.mandate}*");
        }
        out.append("");
        for line in sec.body { out.append(line); }
        if len(sec.cited) > 0 {
            out.append("");
            out.append("Evidence:");
            out.append("");
            for c in sec.cited { out.append(f"- `[{c.ref}]` {c.text}"); }
        }
        out.append("");
    }
    return "\n".join(out);
}


"""Flatten the filing into cited lines, for a client that renders one list.

Section titles and prose carry an empty ref; evidence keeps the archive id it
was read from, so the console can render both with the same row component the
`explain` panel already uses.
"""
def flatten_lines(rep: ComplianceReport) -> list[ExplainLine] {
    out: list[ExplainLine] = [];
    out.append(ExplainLine(ref="", text=f"DETERMINATION: {rep.determination}"));
    for sec in rep.sections {
        out.append(ExplainLine(ref="", text=sec.title));
        for b in sec.body { out.append(ExplainLine(ref="", text=b)); }
        for c in sec.cited { out.append(c); }
    }
    return out;
}
