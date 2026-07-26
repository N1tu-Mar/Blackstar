"""BLACKSTART - RED, the adversary.

Two LLM calls in the entire system, both here:

    plan(view, lessons) -> Scenario
    reflect(scenario, outcome) -> Lesson

Look at their declarations. A signature, a `sem`, and no body. There is no
prompt string anywhere in this project.

Why PLAN needs a model: the graph knows conductors and kilowatts. It does not
know that storm surge floods low elevation first, so the river-side substation
and the plant fail together; that a fuel truck needs a passable road, so an
intact generator still runs dry. That is world knowledge, absent from every
electrical dataset, and a plausible failure *sequence* requires it.

Why REFLECT is the one that matters: if round 1 hands round 2 a number, that
is hill-climbing and needs no model. It hands over a sentence instead - "three
islands formed, so a backup route exists that I did not account for; take it
out first" - and there is no variable in this system that holds that. Round
2's opening move exists because of it.

RED sees `Dashboard`. Conductors are not in it.
"""

import from jaclang.byllm.lib { Model }
import from grid.model {
    GridNode, Substation, Generator, Battery, Facility, Conductor,
    Dashboard, FacilityView, IslandView, Strike, Scenario, Outcome, Lesson, Event, Tick
}

# REQUIRED. The ambient `llm` sourced from jac.toml's [byllm.model]
# default_model resolves to None in jac 0.34.5, and every `by llm()` call then
# dies with a bare "'NoneType' object has no attribute". Declaring the model
# explicitly here is what actually binds it.
glob llm: Model = Model(model_name="claude-sonnet-5");
import from grid.islands {
    recompute_islands, survey, site_endurance, dark_facilities, tier1_stranded,
    all_elements, TARGET_HOURS, UTILITY_HOURS
}
import from grid.prov { record_event }
import from grid.campus { site_name, site_flood_stage, site_target_hours }

glob MECHANISMS: list[str] = [
    "flood", "wind", "fuel_interdiction", "cyber_switching",
    "equipment_failure", "fire"
];


# ----------------------------------------------------------------- LOOK

"""What an element looks like from outside the fence."""
def view_of(n: GridNode) -> FacilityView {
    status = "lit";
    if n.damaged { status = "damaged"; }
    elif n.island_id == -1 { status = "dark"; }
    if isinstance(n, Facility) {
        f = n as Facility;
        if f.shed { status = "shed"; }
        return FacilityView(name=f.name, category=f.category, tier=f.tier,
                            status=status, island_id=f.island_id);
    }
    if isinstance(n, Substation) {
        s = n as Substation;
        if s.utility_source and (not s.utility_live) { status = "de-energized"; }
        return FacilityView(name=s.name, category="utility substation", tier=0,
                            status=status, island_id=s.island_id);
    }
    if isinstance(n, Generator) {
        g = n as Generator;
        if not g.online { status = "offline"; }
        return FacilityView(name=g.name, category="standby generator", tier=0,
                            status=status, island_id=g.island_id);
    }
    if isinstance(n, Battery) {
        return FacilityView(name=n.name, category="battery / UPS", tier=0,
                            status=status, island_id=n.island_id);
    }
    return FacilityView(name=n.name, category="switchgear", tier=0,
                        status=status, island_id=n.island_id);
}


"""Project the current grid state into everything RED is allowed to see."""
def build_dashboard(tick: int, round_index: int, events: list[str]) -> Dashboard {
    recompute_islands();
    islands = survey();
    se = site_endurance(islands);
    elems: list[FacilityView] = [];
    for n in all_elements() { elems.append(view_of(n)); }

    breach = False;
    for i in islands {
        if i.tier1_present and i.endurance_hours < site_target_hours() { breach = True; }
    }

    # An adversary escalates; it does not open with everything it has. Round 1
    # gets two strikes, and the budget grows as RED learns. Without this the
    # first round flattens the campus to zero and there is no graded response
    # left to observe.
    allowed = round_index + 1;
    if allowed < 2 { allowed = 2; }
    if allowed > 4 { allowed = 4; }

    return Dashboard(
        site=site_name(),
        tick=tick, round_index=round_index,
        elements=elems, islands=islands,
        site_endurance_hours=se, target_hours=site_target_hours(),
        strikes_allowed=allowed,
        tier1_stranded=tier1_stranded(islands), breach=breach,
        recent_events=events
    );
}


"""Strip structural knowledge out of a dashboard before RED sees it.

Invariant I2 says RED sees nodes, never edges. Island *membership* violates the
spirit of that: it hands over "these fourteen things are electrically
together", which is most of the wiring diagram, and it does so fresh every
round. That is why the first two memory A/B runs came back null - blind RED
was being given the same structural map as remembering RED, so memory had
nothing left to contribute.

After redaction RED sees names, categories, tiers, lit/dark/shed status, how
many islands formed, and how bad the endurance is. It does NOT see which
elements landed in which island. It has to infer grouping from what went dark
together, and the only place that inference accumulates is a Lesson.

The UI is never redacted - operators get the whole picture.
"""
def redact_for_red(full: Dashboard) -> Dashboard {
    elems: list[FacilityView] = [];
    for e in full.elements {
        elems.append(FacilityView(
            name=e.name, category=e.category, tier=e.tier,
            status=e.status, island_id=0
        ));
    }
    isles: list[IslandView] = [];
    for i in full.islands {
        isles.append(IslandView(
            id=0, members=[], endurance_hours=i.endurance_hours,
            has_generation=i.has_generation, tier1_present=i.tier1_present,
            served_kw=i.served_kw
        ));
    }
    return Dashboard(
        site=full.site, tick=full.tick, round_index=full.round_index,
        elements=elems, islands=isles,
        site_endurance_hours=full.site_endurance_hours,
        target_hours=full.target_hours, strikes_allowed=full.strikes_allowed,
        tier1_stranded=full.tier1_stranded, breach=full.breach,
        recent_events=full.recent_events
    );
}


# ----------------------------------------------------------------- PLAN

# The LLM-facing shape is deliberately FLAT - parallel arrays instead of a
# nested `list[Strike]`. byllm 0.34.5 cannot build an output schema for an obj
# containing a list of objs; it dies with "'str' object has no attribute
# 'fields'". Flat objs and list[str] fields are reliable, so RED emits those
# and `plan` zips them back into typed Strikes below.
obj ScenarioDraft {
    has name: str,
        hazard: str,
        expected_effect: str,
        predicted_endurance_hours: float,
        targets: list[str],
        mechanisms: list[str],
        rationales: list[str],
        immediate_damages: list[str];
}

sem ScenarioDraft.name = "A short operational codename for this specific attack, two to four words, in the style of a named storm or exercise. For example 'Tidewater Surge' or 'Dark Harbor'. Do not restate the schema or use the word scenario.";
sem ScenarioDraft.hazard = "The physical hazard driving the chain, for example 'Category 2 hurricane, storm surge up the Elizabeth River'.";
sem ScenarioDraft.expected_effect = "What you expect this to do to the facility's endurance and to its critical care areas.";
sem ScenarioDraft.targets = "The element names to strike, in the order they fail. Each must match a name visible on the dashboard exactly. Use no more than the number of strikes the dashboard says you are allowed this round.";
sem ScenarioDraft.mechanisms = "One mechanism per target, same order and same length as targets. Each is exactly one of: flood, wind, fuel_interdiction, cyber_switching, equipment_failure, fire.";
sem ScenarioDraft.rationales = "One sentence per target, same order and same length as targets, saying why a real hazard would cause that failure at that point in the chain.";
sem ScenarioDraft.immediate_damages = "One entry per target, same order and same length as targets. Each is exactly one of: none, partial, severe - how much that strike costs the facility BY ITSELF, ignoring what it enables later. Prefer a chain in which at least one strike is 'none': a strike that does no damage on its own but strips the redundancy a later strike depends on is how real cascades work, and it is precisely the move that a search scoring each strike in isolation can never find.";
sem ScenarioDraft.predicted_endurance_hours = "Your numeric forecast, in hours, of the site endurance this chain leaves after the defensive controller responds. You cannot see the wiring, so this is a genuine prediction from an incomplete model - commit to it before you learn the answer.";

"""Write the next failure chain a real hazard would produce at this facility.

You are modeling a hazard, not choosing from a menu. You can see the buildings
and the visible infrastructure, but you cannot see the wiring between them -
you have to infer how this place is connected from what stayed lit and what
went dark. Order the strikes so that earlier ones change what later ones can
accomplish. Use the lessons to avoid repeating a move that did not work.
"""
def draft_scenario(view: Dashboard, lessons: list[Lesson]) -> ScenarioDraft by llm();

sem draft_scenario.view = "Everything observable about the facility right now: element names, kinds, lit or dark status, which elements share an island, and hours of endurance remaining. Conductors are deliberately not shown.";
sem draft_scenario.lessons = "What earlier rounds taught you about this facility's hidden electrical structure. Empty on the first round.";


"""Zip RED's flat draft back into an ordered chain of typed strikes."""
def plan(view: Dashboard, lessons: list[Lesson]) -> Scenario {
    d = draft_scenario(view, lessons);

    # Models sometimes echo the schema's own name back as the value. Catch it
    # here rather than trusting the prompt, and fall back to the hazard.
    label = d.name.strip();
    low = label.lower();
    if low == "" or "scenariodraft" in low or low.startswith("scenario") {
        label = d.hazard.split(",")[0].strip() if d.hazard else "Unnamed scenario";
    }

    out = Scenario(name=label, hazard=d.hazard, expected_effect=d.expected_effect,
                   strikes=[], predicted_endurance_hours=d.predicted_endurance_hours);
    limit = len(d.targets);
    # The budget is enforced here, not merely requested in the prompt.
    if limit > view.strikes_allowed { limit = view.strikes_allowed; }
    for i in range(limit) {
        mech = d.mechanisms[i] if i < len(d.mechanisms) else "equipment_failure";
        why = d.rationales[i] if i < len(d.rationales) else "";
        # Default to "severe" rather than "none" on a short array: an unlabelled
        # strike must not be mistaken for a deliberate setup move, which is the
        # one claim this field exists to support.
        dmg = d.immediate_damages[i] if i < len(d.immediate_damages) else "severe";
        if dmg not in ["none", "partial", "severe"] { dmg = "severe"; }
        out.strikes.append(Strike(
            target_name=d.targets[i], mechanism=mech,
            delay_ticks=i + 1, rationale=why, immediate_damage=dmg
        ));
    }
    return out;
}


# ----------------------------------------------------------------- REFLECT

"""Compare what you expected against what actually happened.

State the belief about this facility's wiring that you now hold and did not
hold before. Be specific about which element to take out first next time and
why. A number is not a lesson; a corrected topology belief is.
"""
# Declared locally for the same reason as ScenarioDraft: a `by llm()` return
# type must live in the SAME module as the function. An imported obj resolves
# to its name string in byllm's schema walker and dies with "'str' object has
# no attribute 'fields'". `reflect` copies this into the shared model.Lesson.
obj LessonDraft {
    has hypothesis: str,
        observed: str,
        revision: str,
        confidence: float;
}

sem LessonDraft.hypothesis = "What you believed about how this facility is wired, before this round.";
sem LessonDraft.observed = "What actually happened that your belief did not predict.";
sem LessonDraft.revision = "The specific corrected belief about the topology, and which element to take out first next time.";
sem LessonDraft.confidence = "How confident you are in the revision, 0.0 to 1.0.";

def reflect_on(attempt: str, result: str) -> LessonDraft by llm();

sem reflect_on.attempt = "The failure chain you planned, in order, and what you expected it to achieve.";
sem reflect_on.result = "What the grid actually did: islands formed, endurance before and after, what went dark, what the controller shed, and which of your strikes could not be resolved or were physically rejected.";


"""Render the scenario and its outcome as prose, then reflect on the gap.

Both sides are flattened to strings for the same reason `plan` emits a flat
draft: byllm 0.34.5 cannot schema an obj carrying list-typed fields on this
path. Prose is also simply a better prompt than a struct dump.
"""
def reflect(scenario: Scenario, outcome: Outcome) -> Lesson {
    plan_lines: list[str] = [f"Scenario '{scenario.name}' - hazard: {scenario.hazard}."];
    step = 1;
    for s in scenario.strikes {
        plan_lines.append(f"Step {step}: {s.mechanism} against {s.target_name}. {s.rationale}");
        step += 1;
    }
    plan_lines.append(f"Expected: {scenario.expected_effect}");

    res: list[str] = [
        f"The grid broke into {outcome.islands_formed} island(s).",
        f"Site endurance went from {outcome.endurance_before:.1f} h to {outcome.endurance_after:.1f} h against a 96 h target.",
        f"Critical care left below target: {outcome.tier1_stranded}."
    ];
    if len(outcome.facilities_dark) > 0 {
        res.append(f"Went completely dark: {', '.join(outcome.facilities_dark)}.");
    } else {
        res.append("Nothing lost power entirely.");
    }
    if len(outcome.shed_actions) > 0 {
        res.append(f"The controller shed, in order: {', '.join(outcome.shed_actions)}.");
    } else {
        res.append("The controller did not need to shed anything.");
    }
    if len(outcome.unresolved_targets) > 0 {
        res.append(f"These targets do not exist at this facility: {', '.join(outcome.unresolved_targets)}.");
    }
    if len(outcome.rejected_strikes) > 0 {
        res.append(f"Physically rejected: {'; '.join(outcome.rejected_strikes)}.");
    }

    d = reflect_on("\n".join(plan_lines), "\n".join(res));
    return Lesson(hypothesis=d.hypothesis, observed=d.observed,
                  revision=d.revision, confidence=d.confidence);
}


# ----------------------------------------------------------------- RESOLVE

"""Normalize a name for loose matching."""
def norm(s: str) -> str {
    out = "";
    for ch in s.lower() {
        if ch.isalnum() or ch == " " { out += ch; }
        else { out += " "; }
    }
    return " ".join(out.split());
}


"""Map a natural-language target to a real element, or None on a miss.

A miss is not repaired. It is recorded and fed to REFLECT, so RED learns the
facility does not have the thing it thought it had.
"""
def resolve_target(name: str) -> GridNode | None {
    want = norm(name);
    if want == "" { return None; }

    # Exact match first.
    for n in all_elements() {
        if norm(n.name) == want { return n; }
    }

    # Token overlap, scored, with a floor so nonsense does not resolve.
    best: GridNode | None = None;
    best_score = 0.0;
    want_tokens = want.split();
    for n in all_elements() {
        cand = norm(n.name).split();
        hits = 0;
        for t in want_tokens {
            if t in cand { hits += 1; }
        }
        if hits == 0 { continue; }
        denom = float(len(want_tokens) + len(cand) - hits);
        score = float(hits) / denom if denom > 0.0 else 0.0;
        if score > best_score {
            best_score = score;
            best = n;
        }
    }
    return best if best_score >= 0.34 else None;
}


# ----------------------------------------------------------------- GATE

"""Reject strikes the physical world would not produce.

Deterministic guard on model output. A rejection carries its reason, and the
reason is fed back to REFLECT so RED learns the constraints of its own hazard
rather than being handed them.
"""
def plausible(mech: str, target: GridNode) -> tuple[bool, str] {
    if mech not in MECHANISMS {
        return (False, f"unknown mechanism '{mech}'");
    }
    if mech == "flood" and target.elevation_m > site_flood_stage() {
        return (False, f"{target.name} sits at {target.elevation_m:.1f} m, above the {site_flood_stage():.1f} m surge stage");
    }
    if mech == "fuel_interdiction" and (not isinstance(target, Generator)) {
        return (False, f"{target.name} is not a generator; there is no fuel supply to interdict");
    }
    return (True, "");
}


# ----------------------------------------------------------------- RUN

"""Apply one strike to the graph. Returns (landed, detail)."""
def apply_strike(mech: str, target: GridNode) -> tuple[bool, str] {
    if mech == "fuel_interdiction" {
        g = target as Generator;
        stranded = g.fuel_gal * 0.25;
        g.fuel_gal = stranded;
        g.fuel_reachable = False;
        return (True, f"road access lost; on-site fuel capped at {stranded:.0f} gal");
    }

    if mech == "cyber_switching" {
        # Opens breakers without damaging anything - recoverable, and the way
        # a tie gets taken out of service.
        opened = 0;
        for e in [edge target ->:Conductor:->] {
            if e.closed { e.closed = False; opened += 1; }
        }
        for e in [edge target <-:Conductor:<-] {
            if e.closed { e.closed = False; opened += 1; }
        }
        return (True, f"unauthorized switching opened {opened} breakers at {target.name}");
    }

    # flood / wind / fire / equipment_failure all physically damage the element.
    target.damaged = True;
    if isinstance(target, Substation) {
        s = target as Substation;
        if s.utility_source { s.utility_live = False; }
    }
    if isinstance(target, Generator) { (target as Generator).online = False; }
    return (True, f"{target.name} damaged by {mech}");
}


"""Play a whole scenario against the grid, recording every event.

Returns the unresolved target names and the rejected strike reasons, both of
which become learning signal rather than errors.
"""
def execute(scenario: Scenario, tick: Tick) -> tuple[list[str], list[str]] {
    unresolved: list[str] = [];
    rejected: list[str] = [];
    prior: Event | None = None;

    for s in scenario.strikes {
        target = resolve_target(s.target_name);
        if target is None {
            unresolved.append(s.target_name);
            continue;
        }
        tgt = target as GridNode;
        (ok, why) = plausible(s.mechanism, tgt);
        if not ok {
            rejected.append(f"{s.mechanism} on {s.target_name}: {why}");
            continue;
        }
        (_landed, detail) = apply_strike(s.mechanism, tgt);
        ev = record_event(tick, s.mechanism, tgt.name, detail, prior);
        prior = ev;
    }

    recompute_islands();
    return (unresolved, rejected);
}


"""Summarize what the scenario actually did, for REFLECT to read."""
def measure(before: float, shed_actions: list[str], breached: bool,
            unresolved: list[str], rejected: list[str],
            predicted: float) -> Outcome {
    recompute_islands();
    islands = survey();
    dark = [f.name for f in dark_facilities()];
    after = site_endurance(islands);
    # A near miss is stronger evidence than a hit. RED forecasts from a view
    # with the wiring removed, so landing close means it holds a working model
    # of a facility it cannot see - which a lookup against an oracle would not
    # demonstrate. -1 marks "no forecast offered" rather than a perfect one.
    err = abs(predicted - after) if predicted > 0.0 else -1.0;
    return Outcome(
        islands_formed=len(islands),
        endurance_before=before,
        endurance_after=after,
        facilities_dark=dark,
        tier1_stranded=breached or tier1_stranded(islands),
        shed_actions=shed_actions,
        unresolved_targets=unresolved,
        rejected_strikes=rejected,
        prediction_error_hours=err
    );
}
