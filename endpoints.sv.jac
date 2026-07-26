"""BLACKSTART - Public API.

Every walker here is `:pub`, so the UI reaches them at POST /walker/<Name>
with no login. They are the only surface the frontend touches.

The round loop lives in `RunRound`: LOOK -> PLAN -> RUN -> REFLECT. Two LLM
calls per round, both inside `grid.red`. Everything else on this path is
arithmetic.
"""

import from grid.model {
    GridNode, Substation, Generator, Battery, Facility, Conductor,
    Run, Tick, Event, Finding, Decision,
    Dashboard, MapView, MapNode, MapEdge, MapPaths, Explanation, ExplainLine,
    Scenario, Strike, Outcome, Lesson, RoundResult, IslandView, FacilityView,
    SiteSummary, HardeningPlan, Vulnerability
}
import from grid.advisor { hardening_plan }
import from grid.campus { build_campus, reset_campus, list_sites, set_active_site }
import from grid.basemap { load_basemap, clear_basemap_cache, bx, by }
import from grid.islands {
    recompute_islands, survey, site_endurance, dark_facilities, tier1_stranded,
    all_elements, TARGET_HOURS, UTILITY_HOURS
}
import from grid.blue { run_blue, unshed_all }
import from grid.campus { site_target_hours }
import from grid.red { build_dashboard, redact_for_red, plan, reflect, execute, measure, resolve_target }
import from grid.prov {
    active_run, write_tick, record_event, record_finding, record_decision,
    open_round, record_lesson, all_lessons, explain, link_lessons, why_round
}


"""Ensure a campus exists, building one on first call."""
def ensure_run -> Run {
    r = active_run();
    if r is None { return build_campus(); }
    return r as Run;
}


"""Human-readable log of what has happened, oldest first, most recent N."""
def recent_event_text(limit: int) -> list[str] {
    evs = [root --> [?:Event]];
    ordered = sorted(evs, key=lambda (e: Event) -> int { return e.t; });
    out: list[str] = [];
    for e in ordered { out.append(f"t={e.t}  {e.kind}: {e.target} - {e.detail}"); }
    return out[-limit:] if len(out) > limit else out;
}


"""Record findings, run BLUE, and attach a cited Decision per shed load."""
def blue_pass(tick: Tick, islands: list[IslandView]) -> tuple[list[str], bool] {
    # Findings are written BEFORE shedding, so each Decision cites the
    # endurance number that actually justified it.
    findings: dict[int, Finding] = {};
    for i in islands {
        findings[i.id] = record_finding(
            tick, i.id, i.endurance_hours, site_target_hours(),
            i.tier1_present and i.endurance_hours < site_target_hours(), i.tier1_present
        );
    }

    (actions, breached) = run_blue();

    for name in actions {
        target: Facility | None = None;
        for f in [root --> [?:Facility]] {
            if f.name == name { target = f; }
        }
        if target is None { continue; }
        t = target as Facility;
        cited = findings.get(t.island_id);
        endurance_txt = "under target";
        if cited is not None { endurance_txt = f"{(cited as Finding).endurance_hours:.1f} h"; }
        record_decision(
            tick, "shed", t.name,
            f"tier {t.tier} load, island endurance {endurance_txt} below {site_target_hours():.0f} h target",
            cited, t
        );
    }
    return (actions, breached);
}


# ------------------------------------------------------------------ read API

walker:pub GetDashboard {
    """Everything RED is allowed to see, which is also what the UI shows."""
    has reports: list[Dashboard] = [];

    can go with Root entry {
        run = ensure_run();
        report build_dashboard(run.tick, run.round_index, recent_event_text(12));
    }
}


walker:pub GetMap {
    """Full topology for rendering. The UI gets this; RED never does."""
    has reports: list[MapView] = [];

    can go with Root entry {
        _ = ensure_run();
        recompute_islands();
        view = MapView(nodes=[], edges=[]);
        for n in all_elements() {
            tier = 0;
            kw = 0.0;
            shed = False;
            if isinstance(n, Facility) {
                f = n as Facility;
                tier = f.tier;
                kw = f.kw;
                shed = f.shed;
            }
            view.nodes.append(MapNode(
                name=n.name, kind=n.kind, lat=n.lat, lon=n.lon,
                x=bx(n.lon), y=by(n.lat), tier=tier, kw=kw,
                island_id=n.island_id, energized=(n.island_id != -1),
                shed=shed, damaged=n.damaged
            ));
            for e in [edge n ->:Conductor:->] {
                for tgt in [n ->:Conductor:label == e.label:->] {
                    view.edges.append(MapEdge(
                        source=n.name, target=tgt.name, passable=e.passable,
                        damaged=e.damaged, normally_open=e.normally_open
                    ));
                }
            }
        }
        report view;
    }
}


walker:pub GetBasemap {
    """Real Portsmouth geography as SVG paths. Loaded from disk once, cached."""
    has reports: list[MapPaths] = [];

    can go with Root entry {
        report load_basemap();
    }
}


walker:pub GetLessons {
    """RED's accumulated memory, oldest first."""
    has reports: list[Lesson] = [];

    can go with Root entry {
        _ = ensure_run();
        for l in all_lessons() { report l; }
    }
}


walker:pub GetHardeningPlan {
    """What should this facility actually change?

    The inverse of RunRound. That one asks what an adversary would do; this
    asks what to build because of it - which is the artifact both the CMS
    emergency-preparedness rule and 10 U.S.C. 2925 actually require, and the
    only output here a facility engineer can put in a budget request.

    Read-only. Ranks the campaign already on the graph and returns prose. It
    never sheds, never switches, and never writes to the grid.
    """
    has reports: list[HardeningPlan] = [];

    can go with Root entry {
        _ = ensure_run();
        report hardening_plan();
    }
}


walker:pub ExplainWhy {
    """Walk backward from a facility's fate to the event that caused it."""
    has subject: str = "",
        reports: list[Explanation] = [];

    can go with Root entry {
        _ = ensure_run();
        report explain(self.subject);
    }
}


# ----------------------------------------------------------------- write API

walker:pub ListSites {
    """Every site the server can load."""
    has reports: list[SiteSummary] = [];

    can go with Root entry {
        for s in list_sites() { report s; }
    }
}


walker:pub LoadSite {
    """Rebuild from scratch and clear all history.

    Pass `site_id` to switch sites; omit it to reload the current one.
    """
    has memory_enabled: bool = True,
        site_id: str = "",
        reports: list[Dashboard] = [];

    can go with Root entry {
        if self.site_id != "" {
            if set_active_site(self.site_id) { clear_basemap_cache(); }
        }
        for n in [root --> [?:Tick]] { del n; }
        for n in [root --> [?:Event]] { del n; }
        for n in [root --> [?:Finding]] { del n; }
        for n in [root --> [?:Decision]] { del n; }
        run = reset_campus();
        run.memory_enabled = self.memory_enabled;
        report build_dashboard(0, 0, []);
    }
}


walker:pub CutConductor {
    """Manually open one named conductor. This is demo step two."""
    has label: str = "",
        reports: list[Dashboard] = [];

    can go with Root entry {
        run = ensure_run();
        run.tick += 1;
        tick = write_tick(run, run.tick, 0.0, 0, 0.0);
        # Distinguish "already open" from "no such conductor". Re-cutting an
        # open feeder is a no-op, not a miss, and logging it as one puts noise
        # in the evidence chain.
        exists = False;
        opened = False;
        for n in all_elements() {
            for e in [edge n ->:Conductor:->] {
                if e.label != self.label { continue; }
                exists = True;
                if e.closed {
                    e.closed = False;
                    e.damaged = True;
                    record_event(tick, "manual_cut", e.label,
                                 f"{e.label} opened by operator", None);
                    opened = True;
                }
            }
        }
        if not exists {
            record_event(tick, "manual_cut_missed", self.label,
                         "no conductor by that name", None);
        } elif not opened {
            # Nothing changed, so do not advance the clock or leave an event.
            run.tick -= 1;
        }
        recompute_islands();
        report build_dashboard(run.tick, run.round_index, recent_event_text(12));
    }
}


walker:pub RunBlue {
    """Run the deterministic controller alone, with no adversary."""
    has reports: list[Dashboard] = [];

    can go with Root entry {
        run = ensure_run();
        run.tick += 1;
        recompute_islands();
        islands = survey();
        tick = write_tick(run, run.tick, site_endurance(islands), len(islands), 0.0);
        blue_pass(tick, islands);
        report build_dashboard(run.tick, run.round_index, recent_event_text(12));
    }
}


walker:pub RunRound {
    """One full adversary round: LOOK -> PLAN -> RUN -> REFLECT."""
    has reports: list[RoundResult] = [];

    can go with Root entry {
        run = ensure_run();
        run.round_index += 1;

        # LOOK - project only what an outside observer could see.
        before_dash = build_dashboard(run.tick, run.round_index, recent_event_text(12));
        before = before_dash.site_endurance_hours;

        # PLAN - LLM call 1. Memory off means it plans blind every round.
        lessons: list[Lesson] = [];
        if run.memory_enabled { lessons = all_lessons(); }
        # RED plans against a redacted view: no island membership, so the only
        # place structural knowledge accumulates is a Lesson.
        scenario = plan(redact_for_red(before_dash), lessons);

        rnd = open_round(run, run.round_index, scenario.name, scenario.hazard,
                         scenario.expected_effect);
        rnd.predicted_endurance_hours = scenario.predicted_endurance_hours;
        rnd.opening_endurance_hours = before;
        # Record which lessons were actually in context. With memory off none
        # were, and no edge is written - so the A/B is visible on the graph.
        if run.memory_enabled { _ = link_lessons(rnd); }

        # RUN - resolve, gate, apply, then let BLUE respond.
        run.tick += 1;
        tick = write_tick(run, run.tick, before, len(before_dash.islands), 0.0);
        (unresolved, rejected) = execute(scenario, tick, rnd);

        recompute_islands();
        islands = survey();
        (actions, breached) = blue_pass(tick, islands);

        recompute_islands();
        after_islands = survey();
        tick.site_endurance_hours = site_endurance(after_islands);
        tick.island_count = len(after_islands);

        outcome = measure(before, actions, breached, unresolved, rejected,
                          scenario.predicted_endurance_hours);
        rnd.actual_endurance_hours = outcome.endurance_after;
        rnd.tier1_stranded = outcome.tier1_stranded;

        # REFLECT - LLM call 2. This is what makes it a loop, not a lookup.
        lesson = reflect(scenario, outcome);
        record_lesson(rnd, lesson);

        report RoundResult(
            round_index=run.round_index,
            scenario_name=scenario.name,
            hazard=scenario.hazard,
            expectation=scenario.expected_effect,
            predicted_endurance_hours=scenario.predicted_endurance_hours,
            strikes=scenario.strikes,
            shed_actions=actions,
            breach=breached,
            memory_enabled=run.memory_enabled,
            outcome=outcome,
            lesson=lesson,
            dashboard=build_dashboard(run.tick, run.round_index, recent_event_text(12))
        );
    }
}
