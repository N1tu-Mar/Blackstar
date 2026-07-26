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
import from grid.campus { site_view, site_satellite_path }

# The render window comes from the active site file, so a different campus
# needs no code change here.
glob _cache: list[MapPaths] = [];


"""Drop the memoized layer so the next read reflects a new site."""
def clear_basemap_cache {
    _cache.clear();
}


"""One edge of the active site's render window."""
def vw(key: str, fallback: float) -> float {
    v: float = site_view().get(key, fallback);
    return v;
}


"""Project a longitude to viewBox x."""
def bx(lon: float) -> float {
    return ((lon - vw("west", -76.31558)) / (vw("east", -76.30092) - vw("west", -76.31558))) * vw("width_px", 1600.0);
}


"""Project a latitude to viewBox y. North is up; SVG y grows downward."""
def by(lat: float) -> float {
    return ((vw("north", 36.84815) - lat) / (vw("north", 36.84815) - vw("south", 36.84155))) * vw("height_px", 900.0);
}


"""True when a ring has at least one vertex inside the render window."""
def visible(ring: list[list[float]]) -> bool {
    for p in ring {
        lon = p[0];
        lat = p[1];
        if lon >= vw("west", -76.31558) and lon <= vw("east", -76.30092) and lat >= vw("south", 36.84155) and lat <= vw("north", 36.84815) {
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

    out = MapPaths(width=vw("width_px", 1600.0), height=vw("height_px", 900.0));
    out.attribution = "Imagery (c) Esri, Maxar, Earthstar Geographics";

    # The satellite image is the whole basemap. Load it first and on its own:
    # an earlier version read an optional OSM vector file before this and
    # returned early when that file was absent, which silently produced a
    # backdrop-less map with no error anywhere.
    try {
        with open(site_satellite_path(), "rb") as img {
            out.satellite = "data:image/jpeg;base64," + base64.b64encode(img.read()).decode("ascii");
        }
    } except Exception {
        print(f"BLACKSTART: no satellite image at '{site_satellite_path()}' - run scripts/fetch_satellite.py");
        out.satellite = "";
    }

    _cache.append(out);
    return out;
}
