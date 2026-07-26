"""BLACKSTART - the campus map, over real Portsmouth geography.

The basemap is a frozen OpenStreetMap extract of the Elizabeth River, the road
network, and NMCP's actual building footprints. It ships in the repo, so a
demo never touches a tile server.

Cut a conductor and the campus splits on screen. Nothing here computes the
split: `island_id` arrives already assigned by the Energize walker, and the
map only paints what the walker could reach.

Encoding, deliberately composite so identity is never colour-alone:
  fill   = island identity  (3 validated hues; islands past 3 fold to neutral)
  stroke = status           (damaged / shed) - reserved status colours
  label  = the element name, always drawn

The three island hues are the categorical slots that pass the all-pairs CVD
and normal-vision floors against this surface. No fourth hue passes, which is
why islands 4+ fold to neutral and lean on the numeric island badge.

All coordinates arrive pre-projected from the server. Client-side Jac silently
yields NaN for this kind of arithmetic, which React renders as a blank SVG
with only a console warning.
"""

sv import from ..endpoints { MapNode, MapEdge }

glob ISLAND_HUES: list[str] = ["#3987e5", "#d95926", "#199e70"];
glob NEUTRAL: str = "#6b7280";
glob DARK_FILL: str = "#39404f";
glob STATUS_DAMAGED: str = "#e66767";
glob STATUS_SHED: str = "#c98500";
glob INK: str = "#c9cfda";
glob INK_MUTED: str = "#7a869a";


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
        r = 7.0 + (kw / 42.0);
        return r if r < 16.0 else 16.0;
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
                water: list[str], buildings: list[str],
                roads_major: list[str], roads_minor: list[str],
                view_w: float, view_h: float, attribution: str) -> JsxElement {
    if len(nodes) == 0 {
        return <div style={{"color": INK_MUTED, "fontSize": "0.8rem", "padding": "2rem"}}>
            no campus loaded
        </div>;
    }

    return
        <div style={{"position": "relative"}}>
            <svg
                viewBox={f"0 0 {view_w:.0f} {view_h:.0f}"}
                style={{"width": "100%", "height": "auto", "display": "block", "background": "#070a10"}}
            >
                <defs>
                    <filter id="bsGlow" x="-70%" y="-70%" width="240%" height="240%">
                        <feGaussianBlur stdDeviation="5" result="b"/>
                        <feMerge>
                            <feMergeNode in="b"/>
                            <feMergeNode in="SourceGraphic"/>
                        </feMerge>
                    </filter>
                    <filter id="bsFault" x="-70%" y="-70%" width="240%" height="240%">
                        <feGaussianBlur stdDeviation="3.5" result="b"/>
                        <feMerge>
                            <feMergeNode in="b"/>
                            <feMergeNode in="SourceGraphic"/>
                        </feMerge>
                    </filter>
                </defs>
                <g>
                    {[
                        <path key={f"w{idx}"} d={d} fill="#0c1a2b" stroke="#153050" strokeWidth={1}/>
                        for (idx, d) in enumerate(water)
                    ]}
                </g>
                <g>
                    {[
                        <path key={f"r{idx}"} d={d} fill="none" stroke="#161c26" strokeWidth={1.3}/>
                        for (idx, d) in enumerate(roads_minor)
                    ]}
                </g>
                <g>
                    {[
                        <path key={f"R{idx}"} d={d} fill="none" stroke="#20293a" strokeWidth={2.4}/>
                        for (idx, d) in enumerate(roads_major)
                    ]}
                </g>
                <g>
                    {[
                        <path key={f"b{idx}"} d={d} fill="#121821" stroke="#1c2431" strokeWidth={0.8}/>
                        for (idx, d) in enumerate(buildings)
                    ]}
                </g>
                <g>
                    {[
                        <line
                            key={f"{e.source}->{e.target}"}
                            x1={x_of(nodes, e.source)} y1={y_of(nodes, e.source)}
                            x2={x_of(nodes, e.target)} y2={y_of(nodes, e.target)}
                            stroke={STATUS_DAMAGED if e.damaged else ("#3b4557" if e.normally_open else ("#7d8aa0" if e.passable else "#3b4557"))}
                            strokeWidth={2.6 if e.damaged else 2.2}
                            strokeDasharray={"9 6" if e.damaged else ("2 8" if e.normally_open else ("5 5" if not e.passable else "0"))}
                            opacity={0.95 if (e.passable or e.damaged) else 0.4}
                            filter={"url(#bsFault)" if e.damaged else "none"}
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
                                stroke={STATUS_DAMAGED if n.damaged else (STATUS_SHED if n.shed else "#070a10")}
                                strokeWidth={3 if (n.damaged or n.shed) else 2}
                                filter={"none" if (n.island_id < 1) else "url(#bsGlow)"}
                                opacity={0.55 if (n.island_id < 1) else 1.0}
                            />
                            <text
                                x={n.x} y={n.y + label_dy(nodes, idx, radius_of(n.kind, n.kw))}
                                textAnchor="middle" fill={INK} fontSize="11"
                                fontFamily="ui-monospace, Menlo, monospace"
                                stroke="#070a10" strokeWidth="3" paintOrder="stroke"
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
                "display": "flex", "gap": "1rem", "flexWrap": "wrap",
                "fontSize": "0.7rem", "color": INK_MUTED, "marginTop": "0.5rem"
            }}>
                <span><span style={swatch(ISLAND_HUES[0])}></span>island 1</span>
                <span><span style={swatch(ISLAND_HUES[1])}></span>island 2</span>
                <span><span style={swatch(ISLAND_HUES[2])}></span>island 3</span>
                <span><span style={swatch(NEUTRAL)}></span>island 4+</span>
                <span><span style={swatch(DARK_FILL)}></span>dark, no source</span>
                <span><span style={swatch(STATUS_SHED)}></span>shed by BLUE</span>
                <span><span style={swatch(STATUS_DAMAGED)}></span>damaged</span>
                <span style={{"marginLeft": "auto"}}>{attribution}</span>
            </div>
        </div>;
}


"""Legend swatch. Identity is carried by the adjacent label, not the colour."""
def swatch(color: str) -> dict {
    return {
        "display": "inline-block", "width": "9px", "height": "9px",
        "background": color, "marginRight": "0.3rem", "borderRadius": "2px"
    };
}
