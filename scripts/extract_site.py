#!/usr/bin/env python3
"""One-shot: lift the hardcoded NMCP campus out of grid/campus.jac into JSON.

Kept in the repo so the extraction is reproducible and reviewable, not a
mystery diff. After this, sites are data and `grid/site.jac` is the loader.

    python3 scripts/extract_site.py
"""

import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "grid" / "campus.jac"
OUT = ROOT / "data" / "sites" / "nmcp-portsmouth.json"

KIND_BY_CTOR = {
    "Substation": "substation",
    "Generator": "generator",
    "Battery": "battery",
    "Facility": "facility",
    "GridNode": "bus",
}

NUM = r"-?\d+(?:\.\d+)?"


def grab(block: str, key: str, cast=float):
    m = re.search(rf"\b{key}\s*=\s*({NUM})", block)
    return cast(m.group(1)) if m else None


def grab_str(block: str, key: str):
    m = re.search(rf'\b{key}\s*=\s*"([^"]*)"', block)
    return m.group(1) if m else None


def main() -> None:
    src = SRC.read_text()

    elements, var_to_name = [], {}
    pattern = re.compile(
        r"(\w+)\s*=\s*root\s*\+\+>\s*(Substation|Generator|Battery|Facility|GridNode)\((.*?)\);",
        re.S,
    )
    for var, ctor, body in pattern.findall(src):
        name = grab_str(body, "name")
        if not name:
            continue
        var_to_name[var] = name
        el = {
            "name": name,
            "kind": grab_str(body, "kind") or KIND_BY_CTOR[ctor],
            "type": ctor,
            "lat": grab(body, "lat"),
            "lon": grab(body, "lon"),
            "elevation_m": grab(body, "elevation_m"),
        }
        for key, cast in (
            ("tier", int), ("kw", float), ("kv", float),
            ("kw_rating", float), ("fuel_gal", float),
            ("kwh_stored", float), ("kwh_capacity", float), ("max_kw", float),
        ):
            v = grab(body, key, cast)
            if v is not None:
                el[key] = v
        cat = grab_str(body, "category")
        if cat:
            el["category"] = cat
        if "utility_source=True" in body.replace(" ", ""):
            el["utility_source"] = True
        elements.append(el)

    conductors = []
    for fn, a, b, label in re.findall(
        r"\b(wire|tie)\(\s*(\w+)\s*,\s*(\w+)\s*,\s*\"([^\"]+)\"\s*\);", src
    ):
        conductors.append({
            "from": var_to_name.get(a, a),
            "to": var_to_name.get(b, b),
            "label": label,
            "normally_open": fn == "tie",
        })

    site = {
        "id": "nmcp-portsmouth",
        "name": "Naval Medical Center Portsmouth",
        "blurb": "A hospital and a DoD installation. CMS emergency preparedness "
                 "and 10 U.S.C. 2925 both apply to the same building.",
        "target_hours": 96.0,
        "flood_stage_m": 4.0,
        # Render window the server projects into. Satellite imagery for a site
        # must be fetched against exactly this box.
        "view": {"south": 36.84155, "north": 36.84815,
                 "west": -76.31558, "east": -76.30092,
                 "width_px": 1600.0, "height_px": 900.0},
        "satellite": "data/sites/nmcp-portsmouth-satellite.jpg",
        "elements": elements,
        "conductors": conductors,
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(site, indent=2))
    print(f"wrote {OUT}")
    print(f"  {len(elements)} elements, {len(conductors)} conductors")
    missing = [e["name"] for e in elements if e["lat"] is None or e["lon"] is None]
    if missing:
        print(f"  WARNING missing coordinates: {missing}")


if __name__ == "__main__":
    main()
