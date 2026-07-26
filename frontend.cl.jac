"""BLACKSTART - operator console.

Deliberately plain. The map carries the story; the chrome stays out of its way.
One column, generous spacing, one accent colour, and numbers large enough to
read from the back of a room.
"""

import from .components.ElementRow { ElementRow }
import from .components.GridMap { GridMap }
import from .components.RoundFeed { RoundFeed }

sv import from endpoints {
    Dashboard, FacilityView, IslandView, Explanation, ExplainLine, Lesson,
    MapView, MapNode, MapEdge, RoundResult,
    GetDashboard, GetMap, GetBasemap, LoadSite, CutConductor,
    RunBlue, RunRound, GetLessons, ExplainWhy
}

def:pub app -> JsxElement {
    has elements: list[FacilityView] = [],
        map_nodes: list[MapNode] = [],
        map_edges: list[MapEdge] = [],
        satellite: str = "",
        view_w: float = 1600.0,
        view_h: float = 900.0,
        attribution: str = "",
        islands: list[IslandView] = [],
        events: list[str] = [],
        lessons: list[Lesson] = [],
        explain_lines: list[ExplainLine] = [],
        rounds: list[RoundResult] = [],
        site: str = "",
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
    async def onCutRiver -> None;
    async def onCutBoth -> None;
    async def onRunBlue -> None;
    async def onRunRound -> None;
    async def onExplain -> None;

    under = endurance < target;

    return
        <div style={{
            "fontFamily": "ui-sans-serif, -apple-system, BlinkMacSystemFont, system-ui, sans-serif",
            "background": "#ffffff", "color": "#0a0a0a",
            "minHeight": "100vh", "padding": "3rem 1.5rem 5rem"
        }}>
            <div style={{"maxWidth": "1100px", "margin": "0 auto"}}>

                <h1 style={{
                    "margin": "0", "fontSize": "1.5rem", "fontWeight": "600",
                    "letterSpacing": "-0.02em"
                }}>
                    Blackstart
                </h1>
                <p style={{"color": "#737373", "fontSize": "0.95rem", "margin": "0.4rem 0 2.5rem"}}>
                    {site if site else "Loading..."}
                </p>

                <div style={{"display": "flex", "gap": "3.5rem", "marginBottom": "2rem"}}>
                    <div>
                        <div style={{
                            "fontSize": "3.25rem", "fontWeight": "600", "lineHeight": "1",
                            "letterSpacing": "-0.03em",
                            "color": "#e5484d" if under else "#0a0a0a"
                        }}>
                            {f"{endurance:.1f}" if endurance < 900.0 else "Grid"}
                        </div>
                        <div style={{"fontSize": "0.8rem", "color": "#737373", "marginTop": "0.5rem"}}>
                            Hours of power remaining
                        </div>
                    </div>
                    <div>
                        <div style={{"fontSize": "1.5rem", "fontWeight": "500", "lineHeight": "1"}}>
                            {f"{target:.0f}"}
                        </div>
                        <div style={{"fontSize": "0.8rem", "color": "#737373", "marginTop": "0.5rem"}}>
                            Hours required by law
                        </div>
                    </div>
                    <div>
                        <div style={{"fontSize": "1.5rem", "fontWeight": "500", "lineHeight": "1"}}>
                            {len(islands)}
                        </div>
                        <div style={{"fontSize": "0.8rem", "color": "#737373", "marginTop": "0.5rem"}}>
                            Separate islands
                        </div>
                    </div>
                </div>

                <div style={{"display": "flex", "gap": "0.5rem", "flexWrap": "wrap", "marginBottom": "0.75rem"}}>
                    <button onClick={onLoadSite} disabled={busy} style={BTN}>Reset</button>
                    <button onClick={onCutRiver} disabled={busy} style={BTN}>Cut river feeder</button>
                    <button onClick={onCutBoth} disabled={busy} style={BTN}>Cut both feeders</button>
                    <button onClick={onRunBlue} disabled={busy} style={BTN}>Run BLUE</button>
                    <button onClick={onRunRound} disabled={busy} style={BTN_PRIMARY}>Run RED round</button>
                </div>

                <p style={{"color": "#737373", "fontSize": "0.85rem", "minHeight": "1.4rem", "margin": "0 0 1.25rem"}}>
                    {status}
                </p>

                <div style={{
                    "border": "1px solid #e5e5e5", "borderRadius": "12px",
                    "overflow": "hidden", "marginBottom": "1rem"
                }}>
                    <GridMap nodes={map_nodes} edges={map_edges}
                             satellite={satellite} view_w={view_w} view_h={view_h}
                             attribution={attribution}/>
                </div>

                <div style={{"display": "grid", "gridTemplateColumns": "1fr 1fr", "gap": "3rem"}}>
                    <div>
                        <h2 style={H2}>Why did it go dark?</h2>
                        <div style={{"display": "flex", "gap": "0.5rem", "marginBottom": "0.75rem"}}>
                            <input
                                value={subject}
                                onChange={lambda (e: ChangeEvent) { subject = e.target.value; }}
                                style={{
                                    "flex": "1", "padding": "0.55rem 0.75rem",
                                    "border": "1px solid #e5e5e5", "borderRadius": "8px",
                                    "fontFamily": "inherit", "fontSize": "0.9rem", "color": "#0a0a0a"
                                }}
                            />
                            <button onClick={onExplain} disabled={busy} style={BTN}>Explain</button>
                        </div>
                        {[
                            <div key={str(idx)} style={{
                                "fontSize": "0.85rem", "lineHeight": "1.5",
                                "padding": "0.45rem 0", "borderBottom": "1px solid #f5f5f5"
                            }}>
                                <span style={{"color": "#a3a3a3", "marginRight": "0.5rem"}}>{line.ref}</span>
                                {line.text}
                            </div>
                            for (idx, line) in enumerate(explain_lines)
                        ]}

                        <h2 style={H2}>Islands</h2>
                        {[
                            <div key={str(i.id)} style={{"fontSize": "0.85rem", "padding": "0.3rem 0"}}>
                                {f"Island {i.id} - {i.endurance_hours:.1f} h, {i.served_kw:.0f} kW"}
                            </div>
                            for i in islands
                        ]}
                    </div>

                    <div>
                        <h2 style={H2}>RED rounds</h2>
                        <RoundFeed rounds={rounds}/>
                    </div>
                </div>

                <h2 style={H2}>Elements</h2>
                <div style={{"columns": "2", "columnGap": "3rem"}}>
                    {[
                        <ElementRow key={e.name} name={e.name} category={e.category}
                                    tier={e.tier} status={e.status} island={e.island_id}/>
                        for e in elements
                    ]}
                </div>

                <h2 style={H2}>Event log</h2>
                {[
                    <div key={str(idx)} style={{
                        "fontSize": "0.8rem", "color": "#737373", "padding": "0.2rem 0"
                    }}>{ev}</div>
                    for (idx, ev) in enumerate(events)
                ]}
            </div>
        </div>;
}

glob BTN: dict = {
    "padding": "0.5rem 0.9rem", "background": "#ffffff",
    "border": "1px solid #e5e5e5", "borderRadius": "8px", "color": "#0a0a0a",
    "cursor": "pointer", "fontFamily": "inherit", "fontSize": "0.875rem",
    "fontWeight": "500"
};

glob BTN_PRIMARY: dict = {
    "padding": "0.5rem 0.9rem", "background": "#0a0a0a",
    "border": "1px solid #0a0a0a", "borderRadius": "8px", "color": "#ffffff",
    "cursor": "pointer", "fontFamily": "inherit", "fontSize": "0.875rem",
    "fontWeight": "500"
};

glob H2: dict = {
    "fontSize": "0.8rem", "fontWeight": "600", "color": "#737373",
    "marginTop": "2.5rem", "marginBottom": "0.9rem", "letterSpacing": "0.01em"
};
