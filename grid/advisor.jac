"""BLACKSTART - the advisor. Turning a wargame into a work order.

RED generates attacks. This turns a campaign of them into the thing a facility
engineer can actually act on: which element to harden first, and what to do
about it.

That inversion is the point. A red-team transcript tells you that you lost. A
resilience plan tells you what to change, and it is the artifact both mandates
behind this project - CMS emergency preparedness and 10 U.S.C. 2925 - actually
require. Everything up to now has been the wargame; this is its output.

THE SPLIT, which is the same one the rest of the system uses:

    ranking          arithmetic over the campaign graph.       NO AI.
    recommendation   what to physically do about it.           AI.

Ranking is a walk: group landed strikes by element, count how often each was
implicated in a round that ended badly, take the worst endurance any such round
reached. There is nothing for a model to add to counting, and a model that
"ranked" would be inventing a number the graph already knows.

The recommendation is the opposite case. "Elizabeth River Substation is your
most-implicated element" falls out of arithmetic. "Back-feed the critical wing
from the north campus bus and raise the switchgear above the surge stage" does
not - it needs to know what mitigations exist for a flood-exposed substation,
which is world knowledge and is nowhere in this graph.

NOT A CONTROL PATH. The advisor never writes to the grid, never sheds, never
opens a breaker. It reads a finished campaign and returns prose for a human.
The invariant that no model touches the load-shedding decision is untouched.
"""

import os;
# byllm 0.6.19 exposes this as `byllm.lib`; the `jaclang.byllm.lib` path only
# exists on older builds and dies here with a bare ModuleNotFoundError at import.
import importlib;
import importlib.util;

# byLLM lives at a different import path depending on how jac was installed, and
# Jac has no try/except around imports, so resolve it at runtime instead:
#
#   official `jac` binary (0.34.x)   -> byLLM is bundled at jaclang.byllm
#   pip `jaclang` + `byllm`          -> byLLM is top-level as byllm
#
# Hardcoding either one breaks the build on the other machine, which it did
# twice: `byllm.lib` dies with ModuleNotFoundError under the binary, and
# `jaclang.byllm.lib` dies the same way under the pip pair. Verified against
# both.
glob _byllm_lib = importlib.import_module(
    "jaclang.byllm.lib"
    if importlib.util.find_spec("jaclang.byllm") is not None
    else "byllm.lib"
);
glob Model = _byllm_lib.Model;
import from grid.model {
    Run, Round, Event, LessonNode, GridNode, Facility, Substation, Generator,
    Battery, Vulnerability, HardeningPlan, Lesson,
    HasRound, Struck, Learned
}
import from grid.islands { all_elements, TARGET_HOURS }
import from grid.prov { active_run, all_lessons }

# Same reason as grid/red.jac: the ambient model from jac.toml resolves to None
# and every call dies without a stack. Declare it explicitly.
# The model is env-selectable, so a dead Anthropic key or a rate limit can be
# routed around without editing code. Default is unchanged:
#   BLACKSTART_MODEL=gemini/gemini-2.0-flash   (needs GOOGLE_API_KEY)
#   BLACKSTART_MODEL=openai/gpt-4o             (needs OPENAI_API_KEY)
#
# NOT a substitute for a working key. `mockllm` does not work here: it requires
# canned `config={"outputs": [...]}` matching each by-llm return schema, and a
# bare Model(model_name="mockllm") dies with a KeyError on 'outputs'. Verified.
#
# The genuinely key-free demo is the deterministic half, which is most of the
# system: scripts/oracle.jac, report.jac, coverage.jac, criticality.jac and
# blackstart.jac all run with no model and no network.
#
# temperature=None so byllm's 0.7 default is not sent - claude-sonnet-5 rejects
# the parameter as deprecated. See the longer note in grid/red.jac.
glob llm: Model = Model(
    model_name=os.environ.get("BLACKSTART_MODEL", "claude-sonnet-5"),
    call_params={"temperature": None}
);

# How many vulnerabilities to carry into the recommendation. Beyond about four
# the advice stops being a priority list and starts being a wish list.
glob TOP_N: int = 4;


# ----------------------------------------------------------------- RANK

"""What kind of thing an element is, for the plan's prose."""
def kind_of(name: str) -> str {
    for n in all_elements() {
        if n.name != name { continue; }
        if isinstance(n, Substation) { return "substation"; }
        if isinstance(n, Generator) { return "generator"; }
        if isinstance(n, Battery) { return "battery / UPS"; }
        if isinstance(n, Facility) { return "facility"; }
        return "switchgear";
    }
    return "unknown";
}


"""Rank every element by how badly the rounds that hit it turned out.

Pure arithmetic over the campaign graph: Run -> HasRound -> Round -> Struck ->
Event. Only landed strikes are linked, so a name RED invented or a strike the
plausibility gate refused contributes nothing.

The score is deliberately conservative. Rounds that stranded critical care
dominate; the worst endurance reached breaks ties; raw frequency breaks those.
Frequency alone would reward whatever RED happens to open with.
"""
def rank_vulnerabilities -> list[Vulnerability] {
    run = active_run();
    if run is None { return []; }
    rounds = [(run as Run) ->:HasRound:->];
    if len(rounds) == 0 { return []; }

    # element name -> accumulated score
    hits: dict[str, int] = {};
    worst: dict[str, float] = {};
    t1: dict[str, int] = {};
    mechs: dict[str, list[str]] = {};

    for r in rounds {
        rnd = r as Round;
        for e in [rnd ->:Struck:->] {
            ev = e as Event;
            name = ev.target;
            hits[name] = hits.get(name, 0) + 1;
            # The endurance the site was left holding after this round. Lower
            # is worse, so keep the minimum across every round that hit it.
            prev = worst.get(name, 1000000.0);
            if rnd.actual_endurance_hours < prev {
                worst[name] = rnd.actual_endurance_hours;
            }
            if rnd.tier1_stranded { t1[name] = t1.get(name, 0) + 1; }
            seen = mechs.get(name, []);
            if ev.kind not in seen {
                seen.append(ev.kind);
                mechs[name] = seen;
            }
        }
    }

    out: list[Vulnerability] = [];
    for name in hits.keys() {
        out.append(Vulnerability(
            element_name=name,
            kind=kind_of(name),
            times_struck=hits.get(name, 0),
            scenarios_total=len(rounds),
            worst_endurance_after=worst.get(name, 0.0),
            tier1_rounds=t1.get(name, 0),
            mechanisms=mechs.get(name, [])
        ));
    }
    # Critical-care strandings first, then the worst endurance reached, then
    # frequency, then name so the order is total and the demo is repeatable.
    return sorted(out, key=vuln_key);
}


"""Total ordering for vulnerabilities. Worst first."""
def vuln_key(v: Vulnerability) -> tuple[int, float, int, str] {
    return (0 - v.tier1_rounds, v.worst_endurance_after,
            0 - v.times_struck, v.element_name);
}


# ----------------------------------------------------------------- ADVISE

# Declared here, not in model.jac: a `by llm()` return type must live in the
# same module as the function, and parallel `list[str]` rather than a nested
# `list[Obj]`. Both constraints are documented in the main README.
obj HardeningDraft {
    has assessment: str,
        single_point_of_failure: str,
        measures: list[str],
        rationales: list[str],
        expected_gains: list[str];
}

sem HardeningDraft.assessment = "Two or three sentences a facility engineer would act on, in the register of a resilience assessment. Say what the campaign revealed about how this site fails, not what the adversary did. Name the pattern across scenarios rather than retelling any one of them.";
sem HardeningDraft.single_point_of_failure = "The exact element name whose loss most reliably ends this facility's endurance, copied verbatim from the ranked list you were given. One name.";
sem HardeningDraft.measures = "One concrete physical mitigation per ranked element, in the same order as the list you were given. Each is a thing a contractor could be scoped to build: a tie to a second bus, raising switchgear above a stated flood elevation, a second fuel route, an automatic transfer switch. Not 'improve resilience' and not 'monitor more closely'.";
sem HardeningDraft.rationales = "One sentence per measure, same order and length, explaining why that specific intervention addresses the way this element actually failed across the campaign.";
sem HardeningDraft.expected_gains = "One short phrase per measure, same order and length, describing the endurance or continuity you would expect to recover. Be honest when a measure only removes a single point of failure without adding hours.";

"""Recommend what to physically change at this facility.

You are advising the engineer responsible for keeping this site powered, having
just watched an adversary attack a model of it several times. You are given the
ranked elements and what the adversary concluded. The ranking is already
computed and is not yours to second-guess - your job is to say what to do about
it, in terms of real equipment and real construction.

An element being implicated is co-occurrence, not proof of cause: several
strikes land together, so the record shows which elements were hit in rounds
that ended badly, not which one did the damage. Recommend accordingly, and do
not assert a causal chain the evidence does not carry.
"""
def draft_hardening(
    site: str,
    target_hours: float,
    ranked: list[str],
    adversary_conclusions: list[str]
) -> HardeningDraft by llm();

sem draft_hardening.site = "The facility being assessed.";
sem draft_hardening.target_hours = "The endurance mandate this site has to meet, in hours.";
sem draft_hardening.ranked = "The elements most implicated in bad outcomes, worst first, each with how often it was struck, the worst endurance any round hitting it ended at, and how many of those rounds stranded critical care.";
sem draft_hardening.adversary_conclusions = "What the adversary wrote down about this site's hidden structure across the campaign. Treat as hypotheses formed from outside the fence, not as ground truth.";


"""One ranked element rendered for the model."""
def vuln_line(v: Vulnerability) -> str {
    mech = ", ".join(v.mechanisms) if v.mechanisms else "none recorded";
    return (f"{v.element_name} ({v.kind}) - struck in {v.times_struck} of "
            f"{v.scenarios_total} scenarios; worst endurance in a round that "
            f"hit it: {v.worst_endurance_after:.1f} h; rounds that stranded "
            f"critical care: {v.tier1_rounds}; mechanisms used: {mech}");
}


"""Deterministic plan used when no model is reachable.

It restates the ranking and recommends nothing, because a template cannot know
what mitigates a flood-exposed substation. The gap is the point: it is exactly
the world knowledge the model is here to supply, and the demo should show that
honestly rather than paper over it with filler advice.
"""
def scripted_plan(site: str, ranked: list[Vulnerability], rounds: int) -> HardeningPlan {
    top = ranked[0].element_name if ranked else "nothing yet";
    return HardeningPlan(
        site=site,
        rounds_analyzed=rounds,
        assessment=f"[scripted] {len(ranked)} element(s) were implicated across "
                   f"{rounds} scenario(s). Ranking is arithmetic and is shown "
                   f"below; no mitigation was generated because no model was "
                   f"reachable.",
        single_point_of_failure=top,
        vulnerabilities=ranked,
        measures=[],
        rationales=[],
        expected_gains=[],
        authored_by="ADVISOR (scripted fallback - no model reached)"
    );
}


"""Rank the campaign, then have the advisor say what to build.

Returns a plan even when the campaign is empty - an honest "nothing has been
run yet" beats an exception in the middle of a demo.
"""
def hardening_plan -> HardeningPlan {
    run = active_run();
    site = (run as Run).site if run is not None else "no site loaded";
    rounds = len([(run as Run) ->:HasRound:->]) if run is not None else 0;

    ranked = rank_vulnerabilities();
    if len(ranked) == 0 {
        return HardeningPlan(
            site=site, rounds_analyzed=rounds,
            assessment="No landed strikes on record yet. Run at least one RED "
                       "round before asking what to harden.",
            authored_by="ADVISOR (nothing to analyze)"
        );
    }

    top = ranked[:TOP_N];
    lessons = all_lessons();
    conclusions = [l.revision for l in lessons];

    plan = scripted_plan(site, top, rounds);
    try {
        d = draft_hardening(
            site, TARGET_HOURS, [vuln_line(v) for v in top], conclusions
        );
        spof: str = d.single_point_of_failure.strip();
        # Trust the arithmetic over the prose: if the model names something
        # that is not on the ranked list, fall back to the top of the ranking
        # rather than printing an element this campaign never touched.
        known = [v.element_name for v in top];
        if spof not in known { spof = top[0].element_name; }
        plan = HardeningPlan(
            site=site,
            rounds_analyzed=rounds,
            assessment=d.assessment,
            single_point_of_failure=spof,
            vulnerabilities=top,
            measures=d.measures,
            rationales=d.rationales,
            expected_gains=d.expected_gains,
            authored_by="ADVISOR (claude-sonnet-5)"
        );
    } except Exception {
        plan = scripted_plan(site, top, rounds);
    }
    return plan;
}
