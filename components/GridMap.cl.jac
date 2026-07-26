"""BLACKSTART - the campus map.

Cut a conductor and this splits on screen. Nothing here computes the split:
`island_id` arrives already assigned by the Energize walker, and the map only
paints what the walker could reach.

Encoding, deliberately composite so identity is never colour-alone:
  fill   = island identity  (3 validated hues; islands past 3 fold to neutral)
  stroke = status           (damaged / shed) - reserved status colours
  label  = the element name, always drawn

The three island hues are the categorical slots that pass the all-pairs CVD
and normal-vision floors against this dark surface. No fourth hue passes,
which is why islands 4+ fold to neutral and lean on the numeric island badge.

Implementation note: this file uses explicit loops rather than dicts,
`min`/`max`, or `.get()`. Those do not survive the Jac-to-JavaScript
compilation intact and silently yield NaN coordinates, which React renders as
an empty SVG with only a console warning.
"""

import from grid.model { MapNode, MapEdge }

glob ISLAND_HUES: list[str] = ["#3987e5", "#d95926", "#199e70"];
glob NEUTRAL: str = "#6b7280";
glob DARK_FILL: str = "#2a2f3a";
glob STATUS_DAMAGED: str = "#e66767";
glob STATUS_SHED: str = "#c98500";
glob SURFACE: str = "#0b0e14";
glob INK_MUTED: str = "#7a869a";
glob PAD_X: float = 130.0;
glob PAD_Y: float = 34.0;


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
        r = 7.0 + (kw / 45.0);
        return r if r < 15.0 else 15.0;
    }
    if kind == "generator" or kind == "substation" { return 10.0; }
    return 8.0;
}


"""Project a longitude to an x coordinate."""
def px(lon: float, lo: float, span: float, width: float) -> float {
    return PAD_X + ((lon - lo) / span) * (width - 2.0 * PAD_X);
}


"""Project a latitude to a y coordinate. North is up, SVG y grows downward."""
def py(lat: float, hi: float, span: float, height: float) -> float {
    return PAD_Y + ((hi - lat) / span) * (height - 2.0 * PAD_Y);
}


"""Stagger label offset so dense clusters do not overprint each other."""
def label_dy(idx: int, r: float) -> float {
    return (0.0 - r) - 6.0 if (idx % 2) == 0 else r + 12.0;
}


"""Longitude of a named element, or 0.0 when absent."""
def lon_of(nodes: list[MapNode], name: str) -> float {
    for n in nodes {
        if n.name == name { return n.lon; }
    }
    return 0.0;
}


"""Latitude of a named element, or 0.0 when absent."""
def lat_of(nodes: list[MapNode], name: str) -> float {
    for n in nodes {
        if n.name == name { return n.lat; }
    }
    return 0.0;
}


def:pub GridMap(nodes: list[MapNode], edges: list[MapEdge], width: float, height: float) -> JsxElement {
    if len(nodes) == 0 {
        return <div style={{"color": INK_MUTED, "fontSize": "0.8rem"}}>no campus loaded</div>;
    }

    lat_lo = nodes[0].lat;
    lat_hi = nodes[0].lat;
    lon_lo = nodes[0].lon;
    lon_hi = nodes[0].lon;
    for n in nodes {
        if n.lat < lat_lo { lat_lo = n.lat; }
        if n.lat > lat_hi { lat_hi = n.lat; }
        if n.lon < lon_lo { lon_lo = n.lon; }
        if n.lon > lon_hi { lon_hi = n.lon; }
    }
    lat_span = lat_hi - lat_lo;
    lon_span = lon_hi - lon_lo;
    if lat_span <= 0.0 { lat_span = 1.0; }
    if lon_span <= 0.0 { lon_span = 1.0; }

    return
        <div>
            <svg viewBox={f"0 0 {width:.0f} {height:.0f}"} style={{"width": "100%", "height": "auto", "display": "block"}}>
                {[
                    <line
                        key={f"{e.source}->{e.target}"}
                        x1={px(lon_of(nodes, e.source), lon_lo, lon_span, width)}
                        y1={py(lat_of(nodes, e.source), lat_hi, lat_span, height)}
                        x2={px(lon_of(nodes, e.target), lon_lo, lon_span, width)}
                        y2={py(lat_of(nodes, e.target), lat_hi, lat_span, height)}
                        stroke={STATUS_DAMAGED if e.damaged else ("#39404f" if e.normally_open else ("#5b6472" if e.passable else "#39404f"))}
                        strokeWidth={2}
                        strokeDasharray={"7 5" if e.damaged else ("2 7" if e.normally_open else ("4 4" if not e.passable else "0"))}
                        opacity={0.95 if (e.passable or e.damaged) else 0.4}
                    />
                    for e in edges
                ]}

                {[
                    <g key={n.name}>
                        <circle
                            cx={px(n.lon, lon_lo, lon_span, width)}
                            cy={py(n.lat, lat_hi, lat_span, height)}
                            r={radius_of(n.kind, n.kw)}
                            fill={island_fill(n.island_id)}
                            stroke={STATUS_DAMAGED if n.damaged else (STATUS_SHED if n.shed else SURFACE)}
                            strokeWidth={3 if (n.damaged or n.shed) else 2}
                        />
                        <text
                            x={px(n.lon, lon_lo, lon_span, width)}
                            y={py(n.lat, lat_hi, lat_span, height) + label_dy(idx, radius_of(n.kind, n.kw))}
                            textAnchor="middle"
                            fill="#c9cfda"
                            fontSize="9"
                            fontFamily="ui-monospace, Menlo, monospace"
                        >
                            {n.name}
                        </text>
                        <text
                            x={px(n.lon, lon_lo, lon_span, width)}
                            y={py(n.lat, lat_hi, lat_span, height) + 3.5}
                            textAnchor="middle"
                            fill="#ffffff"
                            fontSize="9"
                            fontWeight="700"
                        >
                            {str(n.island_id) if n.island_id > 0 else ""}
                        </text>
                    </g>
                    for (idx, n) in enumerate(nodes)
                ]}
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
