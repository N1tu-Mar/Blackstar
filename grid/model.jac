"""BLACKSTART - Grid data model.

The campus electrical network as a graph. `GridNode` is the shared base
archetype so a single walker ability (`with GridNode entry`) fires on every
element type it reaches.

The load-bearing field is `Conductor.passable`. A walker restricted to
passable conductors physically cannot cross a de-energized one, which is why
islanding is emergent here rather than computed - there is no
connected-components routine anywhere in this project.
"""

# ---------------------------------------------------------------- graph nodes

node GridNode {
    has name: str,
        kind: str = "bus",
        lat: float = 0.0,
        lon: float = 0.0,
        elevation_m: float = 5.0,
        island_id: int = -1,
        damaged: bool = False;
}

node Substation(GridNode) {
    has kv: float = 34.5,
        utility_source: bool = False,
        utility_live: bool = True;
}

node Generator(GridNode) {
    has kw_rating: float = 0.0,
        fuel_gal: float = 0.0,
        online: bool = True,
        fuel_reachable: bool = True;
}

node Battery(GridNode) {
    has kwh_stored: float = 0.0,
        kwh_capacity: float = 0.0,
        max_kw: float = 0.0;
}

node Facility(GridNode) {
    has tier: int = 3,
        kw: float = 0.0,
        category: str = "support",
        shed: bool = False;
}

# ---------------------------------------------------------------- graph edges

edge Conductor: GridNode --> GridNode {
    has label: str = "",
        closed: bool = True,
        damaged: bool = False,
        passable: bool = True,
        normally_open: bool = False;
}

# --------------------------------------------------------- provenance archive

node Run {
    has site: str,
        memory_enabled: bool = True,
        tick: int = 0,
        round_index: int = 0;
}

node Round {
    has index: int,
        scenario_name: str = "",
        hazard: str = "",
        expectation: str = "";
}

node Tick {
    has t: int,
        site_endurance_hours: float = 0.0,
        island_count: int = 0,
        served_kw: float = 0.0;
}

node Event {
    has t: int,
        kind: str,
        target: str,
        detail: str;
}

node Finding {
    has t: int,
        island_id: int,
        endurance_hours: float,
        target_hours: float,
        breach: bool = False,
        tier1_present: bool = False;
}

node Decision {
    has t: int,
        action: str,
        subject: str,
        rule: str;
}

node LessonNode {
    has round_index: int,
        hypothesis: str,
        observed: str,
        revision: str,
        confidence: float = 0.5;
}

# Temporal spine and evidence links. `Because` / `DerivedFrom` / `Caused` are
# what the Explain walker traverses backward to answer "why did X go dark".
edge Next: Tick --> Tick {}
edge AtTick: GridNode --> Tick {}
edge EventAt: Event --> Tick {}
edge FindingAt: Finding --> Tick {}
edge DecisionAt: Decision --> Tick {}
edge Because: Decision --> Finding {}
edge DerivedFrom: Finding --> Tick {}
edge Caused: Event --> Event {}
edge Affected: Decision --> Facility {}
edge HasRound: Run --> Round {}
edge Learned: Round --> LessonNode {}
edge HasTick: Run --> Tick {}
edge HasEvent: Round --> Event {}

# ------------------------------------------------------- wire / view objects

obj FacilityView {
    has name: str,
        category: str,
        tier: int,
        status: str,
        island_id: int;
}

obj IslandView {
    has id: int,
        members: list[str],
        endurance_hours: float,
        has_generation: bool,
        tier1_present: bool,
        served_kw: float;
}

# Everything RED is allowed to observe. Names, kinds, status, and which
# elements ended up sharing an island after a fault - all things visible from
# outside a fence line. Conductors appear NOWHERE in this object: RED sees the
# nodes, never the edges, so it must hypothesize connectivity rather than
# enumerate it.
obj Dashboard {
    has site: str,
        tick: int,
        round_index: int,
        elements: list[FacilityView] = [],
        islands: list[IslandView] = [],
        site_endurance_hours: float = 0.0,
        target_hours: float = 96.0,
        strikes_allowed: int = 2,
        tier1_stranded: bool = False,
        breach: bool = False,
        recent_events: list[str] = [];
}

obj MapNode {
    has name: str,
        kind: str,
        lat: float,
        lon: float,
        tier: int,
        kw: float,
        island_id: int,
        energized: bool,
        shed: bool,
        damaged: bool,
        # Projected server-side into the basemap's viewBox, so the grid and the
        # geography share one coordinate system and the client does no math.
        x: float = 0.0,
        y: float = 0.0;
}

# Real Portsmouth geography, pre-projected to SVG path strings. Flat lists of
# strings cross the wire reliably; nested coordinate arrays do not.
obj MapPaths {
    has width: float = 1600.0,
        height: float = 900.0,
        attribution: str = "",
        # Satellite imagery as a data URI, frozen into the repo and inlined so
        # the page needs no tile server and no static-asset route.
        satellite: str = "",
        water: list[str] = [],
        buildings: list[str] = [],
        roads_major: list[str] = [],
        roads_minor: list[str] = [];
}

obj MapEdge {
    has source: str,
        target: str,
        passable: bool,
        damaged: bool,
        normally_open: bool;
}

obj MapView {
    has nodes: list[MapNode] = [],
        edges: list[MapEdge] = [];
}

# One selectable site, for the picker.
obj SiteSummary {
    has id: str,
        name: str,
        blurb: str = "",
        elements: int = 0,
        active: bool = False;
}

obj ExplainLine {
    has ref: str,
        text: str;
}

obj Explanation {
    has subject: str,
        found: bool = False,
        lines: list[ExplainLine] = [];
}

# ------------------------------------------------- RED's structured payloads

obj Strike {
    has target_name: str,
        mechanism: str,
        delay_ticks: int = 1,
        rationale: str = "";
}

obj Scenario {
    has name: str,
        hazard: str,
        strikes: list[Strike] = [],
        expected_effect: str = "";
}

obj Outcome {
    has islands_formed: int = 0,
        endurance_before: float = 0.0,
        endurance_after: float = 0.0,
        facilities_dark: list[str] = [],
        tier1_stranded: bool = False,
        shed_actions: list[str] = [],
        unresolved_targets: list[str] = [],
        rejected_strikes: list[str] = [];
}

obj Lesson {
    has hypothesis: str,
        observed: str,
        revision: str,
        confidence: float = 0.5;
}

# One full LOOK -> PLAN -> RUN -> REFLECT round, as returned to the UI.
obj RoundResult {
    has round_index: int = 0,
        scenario_name: str = "",
        hazard: str = "",
        expectation: str = "",
        strikes: list[Strike] = [],
        shed_actions: list[str] = [],
        breach: bool = False,
        memory_enabled: bool = True,
        outcome: Outcome = Outcome(),
        lesson: Lesson = Lesson(hypothesis="", observed="", revision=""),
        dashboard: Dashboard = Dashboard(site="", tick=0, round_index=0);
}

# `sem` statements are the prompt. There is no prompt string anywhere in this
# project - only these field descriptions plus the function signatures.
#
# NOTE: these are FIELD-level only. An object-level `sem Scenario = "..."`
# crashes byllm's schema generator ('str' object has no attribute 'fields'),
# because the description is handed to the type walker in place of the type.
sem Strike.target_name = "The element to hit, named exactly as it appears on the dashboard. You may only name things you can actually see.";
sem Strike.mechanism = "Exactly one of: flood, wind, fuel_interdiction, cyber_switching, equipment_failure, fire.";
sem Strike.delay_ticks = "Ticks after the previous strike that this one lands, 1 to 6.";
sem Strike.rationale = "Why a real hazard would produce this, in one sentence.";

sem Scenario.name = "Short operational name for this failure chain.";
sem Scenario.hazard = "The physical hazard driving the chain, for example 'Category 2 hurricane, storm surge up the Elizabeth River'.";
sem Scenario.expected_effect = "What you expect this to do to the facility's endurance and to its critical care areas.";

sem Outcome.islands_formed = "How many separate energized islands the grid broke into.";
sem Outcome.endurance_before = "Site endurance in hours before the scenario ran.";
sem Outcome.endurance_after = "Site endurance in hours after the scenario and the controller's response.";
sem Outcome.facilities_dark = "Facilities left with no path to any power source.";
sem Outcome.tier1_stranded = "True if any critical-care load ended up below the survival target.";
sem Outcome.shed_actions = "Loads the defensive controller chose to drop, in the order it dropped them.";
sem Outcome.unresolved_targets = "Names you asked for that do not exist at this facility.";
sem Outcome.rejected_strikes = "Strikes refused as physically implausible, with the reason.";

sem Lesson.hypothesis = "What you believed about how this facility is wired, before this round.";
sem Lesson.observed = "What actually happened that your belief did not predict.";
sem Lesson.revision = "The specific corrected belief about the topology, and which element to take out first next time.";
sem Lesson.confidence = "How confident you are in the revision, 0.0 to 1.0.";
