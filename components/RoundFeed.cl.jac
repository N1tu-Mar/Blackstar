"""BLACKSTART - RED's round history.

This is the panel you point at when a judge asks "did it actually learn?".
Each entry shows what RED believed, what it struck, what that cost the site,
and the belief it revised afterward. The revision is the thing: there is no
variable in the system that holds it, and the next round's opening move exists
because of it.
"""

sv import from ..endpoints { RoundResult }

glob RED_INK: str = "#e66767";
glob AMBER: str = "#c98500";
glob INK_MUTED: str = "#7a869a";


def:pub RoundFeed(rounds: list[RoundResult]) -> JsxElement {
    if len(rounds) == 0 {
        return <div style={{"color": INK_MUTED, "fontSize": "0.78rem"}}>
            No rounds yet. Run a RED round.
        </div>;
    }

    return
        <div>
            {[
                <div key={str(r.round_index)} style={{
                    "borderLeft": f"2px solid {RED_INK}",
                    "paddingLeft": "0.7rem", "marginBottom": "1rem"
                }}>
                    <div style={{"fontSize": "0.8rem", "color": RED_INK}}>
                        {f"round {r.round_index} - {r.scenario_name}"}
                    </div>
                    <div style={{"fontSize": "0.74rem", "color": INK_MUTED, "marginBottom": "0.3rem"}}>
                        {r.hazard}
                    </div>

                    {[
                        <div key={f"{r.round_index}-{s.target_name}"} style={{"fontSize": "0.74rem"}}>
                            {f"-> {s.mechanism} on {s.target_name}"}
                        </div>
                        for s in r.strikes
                    ]}

                    <div style={{"fontSize": "0.74rem", "marginTop": "0.3rem"}}>
                        {f"endurance {r.outcome.endurance_before:.1f} h -> {r.outcome.endurance_after:.1f} h, {r.outcome.islands_formed} islands"}
                    </div>

                    {[
                        <div key={f"{r.round_index}-rej-{idx}"} style={{"fontSize": "0.72rem", "color": AMBER}}>
                            {f"rejected: {why}"}
                        </div>
                        for (idx, why) in enumerate(r.outcome.rejected_strikes)
                    ]}

                    {[
                        <div key={f"{r.round_index}-shed-{idx}"} style={{"fontSize": "0.72rem", "color": AMBER}}>
                            {f"BLUE shed: {name}"}
                        </div>
                        for (idx, name) in enumerate(r.outcome.shed_actions)
                    ]}

                    <div style={{
                        "fontSize": "0.74rem", "marginTop": "0.4rem",
                        "color": "#c9cfda", "fontStyle": "italic"
                    }}>
                        {f"learned: {r.lesson.revision}"}
                    </div>
                </div>
                for r in rounds
            ]}
        </div>;
}
