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
    GridNode, Substation, Generator, Battery, Facility, Conductor, Run, SiteSummary
}

glob DEFAULT_SITE: str = "nmcp-portsmouth";
glob GAL_PER_KWH: float = 0.071;
glob SITE_DIR: str = "data/sites";
glob _site_cache: list[dict] = [];
# Set from the UI. Falls back to the environment, then the default.
glob _active: list[str] = [];


"""Active site id: UI selection, else environment, else the default."""
def site_id -> str {
    if len(_active) > 0 { return _active[0]; }
    return os.environ.get("BLACKSTART_SITE", DEFAULT_SITE);
}


"""Switch sites at run time. Returns False if the id has no site file."""
def set_active_site(sid: str) -> bool {
    if not os.path.exists(f"{SITE_DIR}/{sid}.json") { return False; }
    _active.clear();
    _active.append(sid);
    _site_cache.clear();
    return True;
}


"""Every site the server can load, newest selection first."""
def list_sites -> list[SiteSummary] {
    out: list[SiteSummary] = [];
    current = site_id();
    names: list[str] = sorted(os.listdir(SITE_DIR));
    for fname in names {
        if not fname.endswith(".json") { continue; }
        sid = fname[0:len(fname) - 5];
        try {
            with open(f"{SITE_DIR}/{fname}") as fh {
                cfg: dict = json.load(fh);
            }
        } except Exception { continue; }
        elems: list[dict] = cfg.get("elements", []);
        out.append(SiteSummary(
            id=sid,
            name=str(cfg.get("name", sid)),
            blurb=str(cfg.get("blurb", "")),
            elements=len(elems),
            active=(sid == current)
        ));
    }
    return out;
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


"""Unwrap a `++>` connect expression to the single node it created.

`++>` evaluates to a *list* of the nodes it attached on some jac builds and to
the node itself on others. Hardcoding either shape breaks the app on the other
toolchain: with a bare `[0]` the official 0.34.x binary dies with "'Run' object
is not subscriptable" on the first LoadSite, and without it the builds that do
return a list hand every caller a list and the next `.name` access dies with
"'list' object has no attribute 'name'". Every spawn site goes through here so
the campus loads on both.
"""
def spawned_one(spawned: object) -> object {
    return spawned[0] if isinstance(spawned, list) else spawned;
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
        return spawned_one(root ++> Substation(
            name=name, kind=kind, lat=lat, lon=lon, elevation_m=elev,
            kv=spec.get("kv", 34.5),
            utility_source=spec.get("utility_source", False)
        )) as GridNode;
    }
    if etype == "Generator" {
        return spawned_one(root ++> Generator(
            name=name, kind=kind, lat=lat, lon=lon, elevation_m=elev,
            kw_rating=spec.get("kw_rating", 0.0),
            fuel_gal=spec.get("fuel_gal", 0.0)
        )) as GridNode;
    }
    if etype == "Battery" {
        return spawned_one(root ++> Battery(
            name=name, kind=kind, lat=lat, lon=lon, elevation_m=elev,
            kwh_stored=spec.get("kwh_stored", 0.0),
            kwh_capacity=spec.get("kwh_capacity", 0.0),
            max_kw=spec.get("max_kw", 0.0)
        )) as GridNode;
    }
    if etype == "Facility" {
        return spawned_one(root ++> Facility(
            name=name, kind=kind, lat=lat, lon=lon, elevation_m=elev,
            tier=spec.get("tier", 3),
            kw=spec.get("kw", 0.0),
            category=str(spec.get("category", "support"))
        )) as GridNode;
    }
    return spawned_one(root ++> GridNode(
        name=name, kind=kind, lat=lat, lon=lon, elevation_m=elev
    )) as GridNode;
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
    # `++>` evaluates to a *list* of connected nodes on some jac builds and to the
    # node itself on others, so unwrap defensively. Hardcoding either shape breaks
    # the app on the other toolchain: with a bare [0] the official 0.34.x binary
    # dies here with "'Run' object is not subscriptable", and without it builds
    # that do return a list hand every caller a list and LoadSite dies on
    # `run.memory_enabled`.
    run = spawned_one(root ++> Run(site=site_name(), memory_enabled=True)) as Run;

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
