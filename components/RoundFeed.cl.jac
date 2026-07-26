"""BLACKSTART - RED's round history.

This is the panel you point at when a judge asks "did it actually learn?".
Each entry shows what RED believed, what it struck, what that cost the site,
and the belief it revised afterward. The revision is the thing: there is no
variable in the system that holds it, and the next round's opening move exists
because of it.
"""

sv import from ..endpoints { RoundResult }

glob RED_INK: str = "#e5484d";
glob AMBER: str = "#b45309";
glob INK_MUTED: str = "#737373";


def:pub RoundFeed(rounds: list[RoundResult]) -> JsxElement {
    if len(rounds) == 0 {
        return <div style={{"color": INK_MUTED, "fontSize": "0.85rem"}}>
            Nothing simulated yet.
        </div>;
    }

    return
        <div>
            {[
                <div key={str(r.round_index)} style={{
                    "borderLeft": "2px solid #e5e5e5",
                    "paddingLeft": "0.9rem", "marginBottom": "1.5rem"
                }}>
                    <div style={{"fontSize": "0.9rem", "fontWeight": "600", "color": RED_INK}}>
                        {f"{r.round_index}. {r.scenario_name}"}
                    </div>
                    <div style={{"fontSize": "0.82rem", "color": INK_MUTED, "marginBottom": "0.5rem"}}>
                        {r.hazard}
                    </div>

                    {[
                        <div key={f"{r.round_index}-{s.target_name}"} style={{"fontSize": "0.82rem", "padding": "0.1rem 0"}}>
                            {f"-> {s.mechanism} on {s.target_name}"}
                        </div>
                        for s in r.strikes
                    ]}

                    <div style={{"fontSize": "0.82rem", "marginTop": "0.5rem", "color": "#737373"}}>
                        {f"{r.outcome.endurance_before:.1f} h -> {r.outcome.endurance_after:.1f} h, split into {r.outcome.islands_formed} sections"}
                    </div>

                    {[
                        <div key={f"{r.round_index}-rej-{idx}"} style={{"fontSize": "0.8rem", "color": AMBER}}>
                            {f"rejected: {why}"}
                        </div>
                        for (idx, why) in enumerate(r.outcome.rejected_strikes)
                    ]}

                    {[
                        <div key={f"{r.round_index}-shed-{idx}"} style={{"fontSize": "0.8rem", "color": AMBER}}>
                            {f"Shed: {name}"}
                        </div>
                        for (idx, name) in enumerate(r.outcome.shed_actions)
                    ]}

                    <div style={{
                        "fontSize": "0.85rem", "marginTop": "0.6rem", "lineHeight": "1.5",
                        "color": "#0a0a0a"
                    }}>
                        {f"learned: {r.lesson.revision}"}
                    </div>
                </div>
                for r in rounds
            ]}
        </div>;
}
