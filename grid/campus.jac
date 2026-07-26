"""BLACKSTART - the site loader.

A site is data, not code. This module builds the graph from a JSON file under
`data/sites/`, so modelling a different hospital, base or campus means writing
a JSON file - not touching the simulator.

Nothing below knows anything about Portsmouth. The islanding walker, the
endurance arithmetic, BLUE and the provenance chain never did; this file was
the last place a specific site was hardcoded.

Pick a site with the BLACKSTART_SITE environment variable:

    BLACKSTART_SITE=nmcp-portsmouth jac start --dev main.jac

See `data/sites/README.md` for the schema and how to add one.
"""

import os;
import json;
import from grid.model {
    GridNode, Substation, Generator, Battery, Facility, Conductor, Run
}

glob DEFAULT_SITE: str = "nmcp-portsmouth";
glob GAL_PER_KWH: float = 0.071;
glob _site_cache: list[dict] = [];


"""Site id from the environment, or the default."""
def site_id -> str {
    return os.environ.get("BLACKSTART_SITE", DEFAULT_SITE);
}


"""Load and memoize the active site definition."""
def site_config -> dict {
    if len(_site_cache) > 0 { return _site_cache[0]; }
    path = f"data/sites/{site_id()}.json";
    with open(path) as fh {
        cfg: dict = json.load(fh);
    }
    _site_cache.append(cfg);
    return cfg;
}


"""Display name of the active site."""
def site_name -> str {
    return str(site_config().get("name", "Unnamed site"));
}


"""Hours of endurance the site is required to be able to demonstrate."""
def site_target_hours -> float {
    return float(site_config().get("target_hours", 96.0));
}


"""Elevation at or below which the flood mechanism is physically plausible."""
def site_flood_stage -> float {
    return float(site_config().get("flood_stage_m", 4.0));
}


"""The render window the server projects into: south, north, west, east, px."""
def site_view -> dict {
    return site_config().get("view", {});
}


"""Path to the site's satellite image, relative to the project root."""
def site_satellite_path -> str {
    return str(site_config().get("satellite", ""));
}


"""Instantiate one element from its JSON description."""
def make_element(spec: dict) -> GridNode {
    kind = str(spec.get("kind", "bus"));
    name = str(spec.get("name", "unnamed"));
    lat: float = spec.get("lat", 0.0);
    lon: float = spec.get("lon", 0.0);
    elev: float = spec.get("elevation_m", 5.0);
    etype = str(spec.get("type", ""));

    if etype == "Substation" {
        return root ++> Substation(
            name=name, kind=kind, lat=lat, lon=lon, elevation_m=elev,
            kv=spec.get("kv", 34.5),
            utility_source=spec.get("utility_source", False)
        );
    }
    if etype == "Generator" {
        return root ++> Generator(
            name=name, kind=kind, lat=lat, lon=lon, elevation_m=elev,
            kw_rating=spec.get("kw_rating", 0.0),
            fuel_gal=spec.get("fuel_gal", 0.0)
        );
    }
    if etype == "Battery" {
        return root ++> Battery(
            name=name, kind=kind, lat=lat, lon=lon, elevation_m=elev,
            kwh_stored=spec.get("kwh_stored", 0.0),
            kwh_capacity=spec.get("kwh_capacity", 0.0),
            max_kw=spec.get("max_kw", 0.0)
        );
    }
    if etype == "Facility" {
        return root ++> Facility(
            name=name, kind=kind, lat=lat, lon=lon, elevation_m=elev,
            tier=spec.get("tier", 3),
            kw=spec.get("kw", 0.0),
            category=str(spec.get("category", "support"))
        );
    }
    return root ++> GridNode(
        name=name, kind=kind, lat=lat, lon=lon, elevation_m=elev
    );
}


"""Find a previously built element by name."""
def find_element(built: list[GridNode], name: str) -> GridNode | None {
    for n in built {
        if n.name == name { return n; }
    }
    return None;
}


"""Build the active site's graph and attach it to root."""
def build_campus -> Run {
    cfg = site_config();
    run = root ++> Run(site=site_name(), memory_enabled=True);

    built: list[GridNode] = [];
    specs: list[dict] = cfg.get("elements", []);
    for spec in specs { built.append(make_element(spec)); }

    conductors: list[dict] = cfg.get("conductors", []);
    for c in conductors {
        a = find_element(built, str(c.get("from", "")));
        b = find_element(built, str(c.get("to", "")));
        if a is None or b is None {
            # A conductor naming an element that does not exist is a broken
            # site file, not a runtime condition. Skip it loudly rather than
            # silently building a different grid than the author described.
            print(f"BLACKSTART: conductor '{c.get('label', '?')}' names a missing element");
            continue;
        }
        label = str(c.get("label", ""));
        if c.get("normally_open", False) {
            (a as GridNode) +>:Conductor(
                label=label, closed=False, passable=False, normally_open=True
            ):+> (b as GridNode);
        } else {
            (a as GridNode) +>:Conductor(label=label):+> (b as GridNode);
        }
    }

    return run;
}


"""Tear down any existing site and rebuild a clean one."""
def reset_campus -> Run {
    for n in [root --> [?:GridNode]] { del n; }
    for r in [root --> [?:Run]] { del r; }
    return build_campus();
}
