"""BLACKSTART - real Portsmouth geography, projected server-side.

`data/basemap.json` is a frozen OpenStreetMap extract: the Elizabeth River,
the road network, and the actual building footprints of Naval Medical Center
Portsmouth. It was fetched once by `scripts/fetch_basemap.py` and committed,
so a demo never touches a tile server.

Projection happens here, not in the browser, for two reasons. The grid nodes
and the basemap must share one coordinate system or the campus floats off the
land. And client-side Jac silently produces NaN for this kind of arithmetic,
which React renders as a blank SVG with only a console warning - so the math
lives on the server where it is testable.

Equirectangular with a cos(latitude) correction. At this scale the error
against a true Mercator is well under a pixel.
"""

import json;
import math;
import base64;
import from grid.model { MapPaths }

# The render window, deliberately tighter than the fetched extent so the
# campus fills the frame rather than sitting in a corner of the river.
glob VIEW_S: float = 36.84155;
glob VIEW_N: float = 36.84815;
glob VIEW_W: float = -76.31558;
glob VIEW_E: float = -76.30092;

# 16:9, matching the window's aspect once latitude is corrected.
glob VIEW_W_PX: float = 1600.0;
glob VIEW_H_PX: float = 900.0;

glob LAT_SCALE: float = 0.8005;   # cos(36.845 degrees)

glob _cache: list[MapPaths] = [];


"""Project a longitude to viewBox x."""
def bx(lon: float) -> float {
    return ((lon - VIEW_W) / (VIEW_E - VIEW_W)) * VIEW_W_PX;
}


"""Project a latitude to viewBox y. North is up; SVG y grows downward."""
def by(lat: float) -> float {
    return ((VIEW_N - lat) / (VIEW_N - VIEW_S)) * VIEW_H_PX;
}


"""True when a ring has at least one vertex inside the render window."""
def visible(ring: list[list[float]]) -> bool {
    for p in ring {
        lon = p[0];
        lat = p[1];
        if lon >= VIEW_W and lon <= VIEW_E and lat >= VIEW_S and lat <= VIEW_N {
            return True;
        }
    }
    return False;
}


"""Turn one ring of [lon, lat] pairs into an SVG path."""
def to_path(ring: list[list[float]], close: bool) -> str {
    parts: list[str] = [];
    first = True;
    for p in ring {
        x = bx(p[0]);
        y = by(p[1]);
        cmd = "M" if first else "L";
        parts.append(f"{cmd}{x:.1f},{y:.1f}");
        first = False;
    }
    if close { parts.append("Z"); }
    return "".join(parts);
}


"""Project every feature layer once and memoize the result."""
def load_basemap -> MapPaths {
    if len(_cache) > 0 { return _cache[0]; }

    out = MapPaths(width=VIEW_W_PX, height=VIEW_H_PX);
    try {
        with open("data/basemap.json") as fh {
            raw = json.load(fh);
        }
    } except Exception {
        # A missing basemap degrades to a plain background, never a crash.
        _cache.append(out);
        return out;
    }

    out.attribution = "Imagery (c) Esri, Maxar, Earthstar Geographics - Map data (c) OpenStreetMap contributors";

    # Inline the satellite JPEG. Read once, cached with the rest of the layer.
    try {
        with open("data/satellite.jpg", "rb") as img {
            out.satellite = "data:image/jpeg;base64," + base64.b64encode(img.read()).decode("ascii");
        }
    } except Exception {
        out.satellite = "";
    }

    water: list[list[list[float]]] = raw.get("water", []);
    for ring in water {
        if visible(ring) { out.water.append(to_path(ring, True)); }
    }
    bldgs: list[list[list[float]]] = raw.get("buildings", []);
    for ring in bldgs {
        if visible(ring) { out.buildings.append(to_path(ring, True)); }
    }
    major: list[list[list[float]]] = raw.get("roads_major", []);
    for ring in major {
        if visible(ring) { out.roads_major.append(to_path(ring, False)); }
    }
    minor: list[list[list[float]]] = raw.get("roads_minor", []);
    for ring in minor {
        if visible(ring) { out.roads_minor.append(to_path(ring, False)); }
    }

    _cache.append(out);
    return out;
}
