"""BLACKSTART - Operator console.

Deliberately minimal. This is the base the UI work builds on: it proves the
full client/server round trip (walker spawn -> typed reports -> render) and
puts every number on screen. The campus map, the endurance gauge and the
lesson feed are the next pieces - see README, "Who builds what".
"""

import from .components.ElementRow { ElementRow }
import from .components.GridMap { GridMap }
import from .components.RoundFeed { RoundFeed }

sv import from endpoints {
    Dashboard, FacilityView, IslandView, Explanation, ExplainLine, Lesson,
    MapView, MapNode, MapEdge, RoundResult,
    GetDashboard, GetMap, LoadSite, RunBlue, RunRound, GetLessons, ExplainWhy
}

def:pub app -> JsxElement {
    has elements: list[FacilityView] = [],
        map_nodes: list[MapNode] = [],
        map_edges: list[MapEdge] = [],
        islands: list[IslandView] = [],
        events: list[str] = [],
        lessons: list[Lesson] = [],
        explain_lines: list[ExplainLine] = [],
        rounds: list[RoundResult] = [],
        site: str = "loading...",
        endurance: float = 0.0,
        target: float = 96.0,
        subject: str = "Galley and Food Service",
        status: str = "",
        busy: bool = False;

    can with entry {
        refresh();
    }

    async def refresh -> None;
    async def onLoadSite -> None;
    async def onRunBlue -> None;
    async def onRunRound -> None;
    async def onExplain -> None;

    return
        <div style={{
            "fontFamily": "ui-monospace, Menlo, monospace",
            "background": "#0b0e14", "color": "#e6e6e6",
            "minHeight": "100vh", "padding": "1.5rem"
        }}>
            <h1 style={{"margin": "0", "fontSize": "1.3rem", "letterSpacing": "0.1em"}}>
                BLACKSTART
            </h1>
            <p style={{"color": "#7a869a", "fontSize": "0.85rem", "marginTop": "0.2rem"}}>
                {site}
            </p>

            <div style={{
                "display": "flex", "gap": "2rem", "alignItems": "baseline",
                "border": "1px solid #2a2f3a", "padding": "0.8rem 1rem", "margin": "1rem 0"
            }}>
                <div>
                    <div style={{"fontSize": "2rem"}}>{f"{endurance:.1f}"}</div>
                    <div style={{"fontSize": "0.7rem", "color": "#7a869a"}}>HOURS ENDURANCE</div>
                </div>
                <div>
                    <div style={{"fontSize": "1.1rem"}}>{f"{target:.0f}"}</div>
                    <div style={{"fontSize": "0.7rem", "color": "#7a869a"}}>TARGET</div>
                </div>
                <div>
                    <div style={{"fontSize": "1.1rem"}}>{len(islands)}</div>
                    <div style={{"fontSize": "0.7rem", "color": "#7a869a"}}>ISLANDS</div>
                </div>
            </div>

            <div style={{"display": "flex", "gap": "0.5rem", "marginBottom": "1rem"}}>
                <button onClick={onLoadSite} disabled={busy} style={BTN}>Load site</button>
                <button onClick={onRunBlue} disabled={busy} style={BTN}>Run BLUE</button>
                <button onClick={onRunRound} disabled={busy} style={BTN}>Run RED round</button>
            </div>

            <p style={{"color": "#f0a020", "fontSize": "0.8rem"}}>{status}</p>

            <div style={{"border": "1px solid #2a2f3a", "padding": "0.5rem", "marginBottom": "1.2rem"}}>
                <GridMap nodes={map_nodes} edges={map_edges} width={1240.0} height={560.0}/>
            </div>

            <div style={{"display": "grid", "gridTemplateColumns": "1fr 1fr", "gap": "2rem"}}>
                <div>
                    <h2 style={H2}>Elements</h2>
                    {[
                        <ElementRow key={e.name} name={e.name} category={e.category}
                                    tier={e.tier} status={e.status} island={e.island_id}/>
                        for e in elements
                    ]}
                </div>

                <div>
                    <h2 style={H2}>Islands</h2>
                    {[
                        <div key={str(i.id)} style={{"fontSize": "0.8rem", "marginBottom": "0.3rem"}}>
                            {f"island {i.id} - {i.endurance_hours:.1f} h, {i.served_kw:.0f} kW"}
                        </div>
                        for i in islands
                    ]}

                    <h2 style={H2}>RED rounds</h2>
                    <RoundFeed rounds={rounds}/>

                    <h2 style={H2}>Why did it go dark?</h2>
                    <div style={{"display": "flex", "gap": "0.4rem"}}>
                        <input
                            value={subject}
                            onChange={lambda (e: ChangeEvent) { subject = e.target.value; }}
                            style={{
                                "flex": "1", "padding": "0.4rem", "background": "#131722",
                                "border": "1px solid #2a2f3a", "color": "#e6e6e6",
                                "fontFamily": "inherit"
                            }}
                        />
                        <button onClick={onExplain} disabled={busy} style={BTN}>Explain</button>
                    </div>
                    {[
                        <div key={str(idx)} style={{"fontSize": "0.76rem", "marginTop": "0.35rem"}}>
                            {f"[{line.ref}] {line.text}"}
                        </div>
                        for (idx, line) in enumerate(explain_lines)
                    ]}
                </div>
            </div>

            <h2 style={H2}>Event log</h2>
            {[
                <div key={str(idx)} style={{"fontSize": "0.75rem", "color": "#7a869a"}}>{ev}</div>
                for (idx, ev) in enumerate(events)
            ]}
        </div>;
}

glob BTN: dict = {
    "padding": "0.45rem 0.9rem", "background": "#1c2230",
    "border": "1px solid #2a2f3a", "color": "#e6e6e6",
    "cursor": "pointer", "fontFamily": "inherit", "fontSize": "0.82rem"
};

glob H2: dict = {
    "fontSize": "0.72rem", "letterSpacing": "0.14em", "color": "#7a869a",
    "marginTop": "1.2rem", "marginBottom": "0.5rem", "textTransform": "uppercase"
};
