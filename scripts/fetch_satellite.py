#!/usr/bin/env python3
"""Fetch satellite imagery for a site once and freeze it into the repo.

Stitches Esri World Imagery tiles covering the render window, crops to the
exact bounding box the server projects into, and writes a single JPEG. The
running app serves it as a data URI, so a demo never touches a tile server.

Imagery: Esri World Imagery (Esri, Maxar, Earthstar Geographics).

    python3 scripts/fetch_satellite.py [site-id]
"""

import io
import json
import math
import pathlib
import sys
import time
import urllib.request

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE_ID = sys.argv[1] if len(sys.argv) > 1 else "nmcp-portsmouth"
SITE = json.loads((ROOT / "data" / "sites" / f"{SITE_ID}.json").read_text())

# Read straight from the site file so imagery and projection cannot drift.
V = SITE["view"]
VIEW_S, VIEW_N = V["south"], V["north"]
VIEW_W, VIEW_E = V["west"], V["east"]
OUT_W, OUT_H = int(V.get("width_px", 1600)), int(V.get("height_px", 900))

ZOOM = 18
TILE = 256
URL = ("https://server.arcgisonline.com/ArcGIS/rest/services/"
       "World_Imagery/MapServer/tile/{z}/{y}/{x}")


def lon_to_x(lon: float, z: int) -> float:
    return (lon + 180.0) / 360.0 * (2 ** z)


def lat_to_y(lat: float, z: int) -> float:
    rad = math.radians(lat)
    return (1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2.0 * (2 ** z)


def fetch_tile(z: int, x: int, y: int) -> Image.Image:
    req = urllib.request.Request(
        URL.format(z=z, x=x, y=y),
        headers={"User-Agent": "blackstart-hackathon/0.1 (grid resilience demo)"},
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return Image.open(io.BytesIO(resp.read())).convert("RGB")
        except Exception as exc:
            if attempt == 3:
                print(f"  tile {z}/{x}/{y} failed: {exc}")
                return Image.new("RGB", (TILE, TILE), (18, 22, 30))
            time.sleep(2 * (attempt + 1))
    return Image.new("RGB", (TILE, TILE), (18, 22, 30))


def main() -> None:
    fx0, fx1 = lon_to_x(VIEW_W, ZOOM), lon_to_x(VIEW_E, ZOOM)
    fy0, fy1 = lat_to_y(VIEW_N, ZOOM), lat_to_y(VIEW_S, ZOOM)

    x0, x1 = math.floor(fx0), math.floor(fx1)
    y0, y1 = math.floor(fy0), math.floor(fy1)
    cols, rows = x1 - x0 + 1, y1 - y0 + 1
    print(f"z{ZOOM}: {cols} x {rows} = {cols * rows} tiles")

    canvas = Image.new("RGB", (cols * TILE, rows * TILE))
    done = 0
    for xi in range(cols):
        for yi in range(rows):
            canvas.paste(fetch_tile(ZOOM, x0 + xi, y0 + yi), (xi * TILE, yi * TILE))
            done += 1
            if done % 10 == 0:
                print(f"  {done}/{cols * rows}")

    # Crop to the exact view window, in fractional tile space.
    left = (fx0 - x0) * TILE
    top = (fy0 - y0) * TILE
    right = (fx1 - x0) * TILE
    bottom = (fy1 - y0) * TILE
    crop = canvas.crop((int(left), int(top), int(right), int(bottom)))
    crop = crop.resize((OUT_W, OUT_H), Image.LANCZOS)

    out = ROOT / SITE.get("satellite", f"data/sites/{SITE_ID}-satellite.jpg")
    out.parent.mkdir(parents=True, exist_ok=True)
    crop.save(out, "JPEG", quality=82, optimize=True)
    print(f"\nwrote {out} ({out.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
