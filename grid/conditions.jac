"""BLACKSTART - real observed conditions, frozen to disk.

`scripts/fetch_conditions.py` writes data/live/<site>-conditions.json from two
public federal APIs: NOAA CO-OPS water level at the site's reference tide gauge,
and the NWS point forecast. This reads that file. Nothing here touches the
network -- the same rule the satellite basemap follows, because a demo that
depends on venue wifi is a demo that fails on stage.

What it changes in the simulation: RED's flood mechanism is gated on element
elevation against a surge stage. That stage was a constant in the site file.
It is now derived from water level that was actually measured at the gauge, so
the adversary is planning against real conditions rather than an assumption.

The site file's own flood_stage_m stays the floor. A calm morning must not be
able to make the campus look invulnerable.
"""

import json;
import os;
import from grid.campus { site_id, site_flood_stage }

# Parsed once per process. The file is small and never changes while running.
glob _cond_cache: list = [];


"""The frozen conditions for the active site, or an empty dict if none."""
def conditions -> dict {
    if len(_cond_cache) > 0 { return _cond_cache[0]; }
    path = f"data/live/{site_id()}-conditions.json";
    # Absent file is normal: a site may never have had conditions fetched, and
    # the simulator must still run. Callers fall back to the site file's stage.
    if not os.path.exists(path) {
        blank: dict = {};
        _cond_cache.append(blank);
        return blank;
    }
    with open(path) as fh {
        data: dict = json.load(fh);
    }
    _cond_cache.append(data);
    return data;
}


"""True when observed conditions were loaded for this site."""
def have_conditions -> bool {
    c = conditions();
    return len(c) > 0 and c.get("observed_ft_mllw") is not None;
}


"""Surge stage the flood gate compares element elevations against.

Measured beats assumed. When conditions are on file the stage is the
worst-credible storm tide for this gauge -- the record crest, bounded below by
the gauge's own published major-flood category -- and it *replaces* the site
file's figure rather than being floored by it.

That direction matters. nmcp-portsmouth.json carries flood_stage_m = 4.0, which
is 13.1 ft: higher than any storm tide ever measured on the Elizabeth River. The
record is 8.02 ft (2.44 m), set by the 1933 Chesapeake-Potomac hurricane, with
Isabel reaching 7.89 ft in 2003. A 4.0 m stage would let the adversary flood
equipment that no hurricane on record could reach, which makes the plausibility
gate decorative. Taking the max would have preserved exactly that bug.
"""
def effective_flood_stage -> float {
    c = conditions();
    live = c.get("surge_stage_m");
    if live is None { return site_flood_stage(); }
    return float(live);
}


"""One line of real conditions, for the adversary's view and the event log."""
def conditions_line -> str {
    c = conditions();
    if not have_conditions() {
        return "";
    }
    parts: list[str] = [];
    obs = c.get("observed_ft_mllw");
    at = c.get("observed_at");
    if obs is not None {
        parts.append(f"river stage {float(obs):.2f} ft MLLW at {c.get('gauge_name', 'the gauge')} ({at})");
    }
    fc = c.get("forecast_peak_ft_mllw");
    if fc is not None {
        parts.append(f"NWS forecast peak {float(fc):.1f} ft");
    }
    sf = c.get("short");
    wind = c.get("wind");
    if sf is not None { parts.append(str(sf).lower()); }
    if wind is not None { parts.append(f"wind {wind}"); }
    parts.append(f"worst-credible surge stage {effective_flood_stage():.2f} m ({c.get('record_crest_event', 'record crest')})");
    return "observed conditions: " + ", ".join(parts);
}
