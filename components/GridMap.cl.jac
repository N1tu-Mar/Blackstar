"""BLACKSTART - the campus map, over satellite imagery.

The backdrop is Esri World Imagery of Naval Medical Center Portsmouth, frozen
into the repo and inlined as a data URI, so a demo never touches a tile server.
Grid elements sit on the buildings they actually represent.

Cut a conductor and the campus splits on screen. Nothing here computes the
split: `island_id` arrives already assigned by the Energize walker, and the
map only paints what the walker could reach.

Encoding, deliberately composite so identity is never colour-alone:
  fill   = island identity  (3 validated hues; islands past 3 fold to neutral)
  stroke = status           (damaged / shed) - reserved status colours
  label  = the element name, always drawn

All coordinates arrive pre-projected from the server. Client-side Jac silently
yields NaN for this kind of arithmetic, which React renders as a blank SVG
with only a console warning.
"""

sv import from ..endpoints { MapNode, MapEdge }

glob ISLAND_HUES: list[str] = ["#3987e5", "#d95926", "#199e70"];
glob NEUTRAL: str = "#9ca3af";
glob DARK_FILL: str = "#4b5563";
glob STATUS_DAMAGED: str = "#e5484d";
glob STATUS_SHED: str = "#f5a524";
glob HALO: str = "#0a0a0a";


"""Fill colour for an element, by island identity."""
def island_fill(island_id: int) -> str {
    if island_id < 1 { return DARK_FILL; }
    if island_id == 1 { return ISLAND_HUES[0]; }
    if island_id == 2 { return ISLAND_HUES[1]; }
    if island_id == 3 { return ISLAND_HUES[2]; }
    return NEUTRAL;
}


"""Marker radius - facilities scale with load, infrastructure is fixed."""
def radius_of(kind: str, kw: float) -> float {
    if kind == "facility" {
        r = 7.0 + (kw / 44.0);
        return r if r < 15.0 else 15.0;
    }
    if kind == "generator" or kind == "substation" { return 11.0; }
    return 8.5;
}


"""Screen x of a named element."""
def x_of(nodes: list[MapNode], name: str) -> float {
    for n in nodes {
        if n.name == name { return n.x; }
    }
    return 0.0;
}


"""Screen y of a named element."""
def y_of(nodes: list[MapNode], name: str) -> float {
    for n in nodes {
        if n.name == name { return n.y; }
    }
    return 0.0;
}


"""Stack a label clear of any label already placed near it."""
def label_dy(nodes: list[MapNode], idx: int, r: float) -> float {
    me = nodes[idx];
    crowd = 0;
    for j in range(idx) {
        o = nodes[j];
        dx = me.x - o.x;
        dy = me.y - o.y;
        if dx < 0.0 { dx = 0.0 - dx; }
        if dy < 0.0 { dy = 0.0 - dy; }
        if dx < 230.0 and dy < 36.0 { crowd += 1; }
    }
    step = float(crowd / 2) * 15.0;
    if (crowd % 2) == 0 { return (0.0 - r) - 9.0 - step; }
    return r + 18.0 + step;
}


def:pub GridMap(nodes: list[MapNode], edges: list[MapEdge],
                satellite: str, view_w: float, view_h: float,
                attribution: str) -> JsxElement {
    if len(nodes) == 0 {
        return <div style={{"color": "#737373", "fontSize": "0.85rem", "padding": "3rem"}}>
            No campus loaded.
        </div>;
    }

    return
        <div>
            <svg
                viewBox={f"0 0 {view_w:.0f} {view_h:.0f}"}
                style={{"width": "100%", "height": "auto", "display": "block", "background": "#0d1117"}}
            >
                <defs>
                    <filter id="bsGlow" x="-70%" y="-70%" width="240%" height="240%">
                        <feGaussianBlur stdDeviation="4" result="b"/>
                        <feMerge>
                            <feMergeNode in="b"/>
                            <feMergeNode in="SourceGraphic"/>
                        </feMerge>
                    </filter>
                </defs>

                <image href={satellite} x="0" y="0" width={view_w} height={view_h} opacity="0.62"/>
                <rect x="0" y="0" width={view_w} height={view_h} fill="#0a0f18" opacity="0.3"/>

                <g>
                    {[
                        <line
                            key={f"{e.source}->{e.target}"}
                            x1={x_of(nodes, e.source)} y1={y_of(nodes, e.source)}
                            x2={x_of(nodes, e.target)} y2={y_of(nodes, e.target)}
                            stroke={STATUS_DAMAGED if e.damaged else ("#94a3b8" if e.normally_open else ("#e2e8f0" if e.passable else "#94a3b8"))}
                            strokeWidth={3.0 if e.damaged else 2.4}
                            strokeDasharray={"10 7" if e.damaged else ("2 9" if e.normally_open else ("5 5" if not e.passable else "0"))}
                            opacity={0.95 if e.damaged else (0.85 if e.passable else 0.4)}
                        />
                        for e in edges
                    ]}
                </g>

                <g>
                    {[
                        <g key={n.name}>
                            <circle
                                cx={n.x} cy={n.y} r={radius_of(n.kind, n.kw)}
                                fill={island_fill(n.island_id)}
                                stroke={STATUS_DAMAGED if n.damaged else (STATUS_SHED if n.shed else "#ffffff")}
                                strokeWidth={3 if (n.damaged or n.shed) else 2}
                                filter={"none" if (n.island_id < 1) else "url(#bsGlow)"}
                                opacity={0.6 if (n.island_id < 1) else 1.0}
                            />
                            <text
                                x={n.x} y={n.y + label_dy(nodes, idx, radius_of(n.kind, n.kw))}
                                textAnchor="middle" fill="#ffffff" fontSize="12"
                                fontFamily="ui-sans-serif, -apple-system, system-ui, sans-serif"
                                stroke={HALO} strokeWidth="3.5" paintOrder="stroke"
                            >
                                {n.name}
                            </text>
                            <text
                                x={n.x} y={n.y + 4.0}
                                textAnchor="middle" fill="#ffffff" fontSize="10" fontWeight="700"
                            >
                                {str(n.island_id) if n.island_id > 0 else ""}
                            </text>
                        </g>
                        for (idx, n) in enumerate(nodes)
                    ]}
                </g>
            </svg>

            <div style={{
                "display": "flex", "gap": "1.1rem", "flexWrap": "wrap", "alignItems": "center",
                "fontSize": "0.75rem", "color": "#737373",
                "padding": "0.75rem 1rem", "borderTop": "1px solid #e5e5e5"
            }}>
                <span><span style={swatch(ISLAND_HUES[0])}></span>Island 1</span>
                <span><span style={swatch(ISLAND_HUES[1])}></span>Island 2</span>
                <span><span style={swatch(ISLAND_HUES[2])}></span>Island 3</span>
                <span><span style={swatch(DARK_FILL)}></span>Dark</span>
                <span><span style={swatch(STATUS_SHED)}></span>Shed by BLUE</span>
                <span><span style={swatch(STATUS_DAMAGED)}></span>Damaged</span>
                <span style={{"marginLeft": "auto", "fontSize": "0.68rem"}}>{attribution}</span>
            </div>
        </div>;
}


"""Legend swatch. Identity is carried by the adjacent label, not the colour."""
def swatch(color: str) -> dict {
    return {
        "display": "inline-block", "width": "9px", "height": "9px",
        "background": color, "marginRight": "0.4rem", "borderRadius": "50%"
    };
}
