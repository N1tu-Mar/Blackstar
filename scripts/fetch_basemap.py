#!/usr/bin/env python3
"""Fetch real Portsmouth / Norfolk geography once and freeze it into the repo.

BLACKSTART must not touch the network during a demo, so this runs offline
ahead of time and writes data/basemap.json. The client renders that file as
SVG - no tile server, no API key, no demo-day dependency.

Source: OpenStreetMap via Overpass. Data (c) OpenStreetMap contributors, ODbL.

    python3 scripts/fetch_basemap.py
"""

import json
import pathlib
import time
from typing import Optional
import urllib.parse
import urllib.request

# Naval Medical Center Portsmouth sits at ~36.8447 N, -76.3080 W, on the
# west bank of the Elizabeth River. This window shows the river bend that
# makes the storm-surge story legible.
SOUTH, WEST, NORTH, EAST = 36.826, -76.330, 36.864, -76.280
BBOX = f"{SOUTH},{WEST},{NORTH},{EAST}"
ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.osm.ch/api/interpreter",
]
# Buildings over the full window time out; NMCP's own campus is what matters.
CAMPUS = "36.8415,-76.3125,36.8480,-76.3040"

QUERIES = {
    # The river and any inland water.
    "water": f"""
        (way({BBOX})[natural=water];
         way({BBOX})[waterway=riverbank];
         relation({BBOX})[natural=water];);
        out geom;
    """,
    # Road network, major to residential, so the campus reads as a place.
    "roads_major": f"""
        way({BBOX})[highway~"^(motorway|trunk|primary|secondary)$"];
        out geom;
    """,
    "roads_minor": f"""
        way({BBOX})[highway~"^(tertiary|residential|unclassified)$"];
        out geom;
    """,
    # Building footprints for the campus itself, so NMCP's real shape shows.
    "buildings": f"""
        way({CAMPUS})[building];
        out geom;
    """,
}


def fetch(query: str) -> dict:
    """Query Overpass, rotating mirrors and backing off on 429/504."""
    body = urllib.parse.urlencode({"data": f"[out:json][timeout:120];{query}"})
    last = None
    for attempt in range(6):
        endpoint = ENDPOINTS[attempt % len(ENDPOINTS)]
        req = urllib.request.Request(
            endpoint,
            data=body.encode(),
            headers={"User-Agent": "blackstart-hackathon/0.1 (grid resilience demo)"},
        )
        try:
            with urllib.request.urlopen(req, timeout=200) as resp:
                return json.loads(resp.read().decode())
        except Exception as exc:  # 429/504 are routine on public mirrors
            last = exc
            wait = 5 * (attempt + 1)
            print(f"  {endpoint.split('/')[2]} failed ({exc}); retrying in {wait}s")
            time.sleep(wait)
    raise RuntimeError(f"all Overpass mirrors failed: {last}")


def rings(payload: dict, keep_closed: Optional[bool] = None) -> list:
    """Extract way geometries as [[lon, lat], ...], rounded to ~1 m."""
    out = []
    for el in payload.get("elements", []):
        geom = el.get("geometry")
        if not geom or len(geom) < 2:
            continue
        pts = [[round(p["lon"], 5), round(p["lat"], 5)] for p in geom]
        closed = pts[0] == pts[-1]
        if keep_closed is not None and closed != keep_closed:
            continue
        out.append(pts)
    return out


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent
    out_path = root / "data" / "basemap.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    basemap = {
        "attribution": "(c) OpenStreetMap contributors, ODbL",
        "bbox": {"south": SOUTH, "west": WEST, "north": NORTH, "east": EAST},
    }

    for name, q in QUERIES.items():
        print(f"fetching {name} ...", flush=True)
        payload = fetch(q)
        # Water and buildings are areas; roads are open polylines.
        want_closed = True if name in ("water", "buildings") else None
        feats = rings(payload, keep_closed=want_closed)
        basemap[name] = feats
        print(f"  {name}: {len(feats)} features")

    out_path.write_text(json.dumps(basemap, separators=(",", ":")))
    kb = out_path.stat().st_size / 1024
    print(f"\nwrote {out_path} ({kb:.0f} KB)")


if __name__ == "__main__":
    main()
