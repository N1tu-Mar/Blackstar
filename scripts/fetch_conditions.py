#!/usr/bin/env python3
"""Freeze real observed conditions for a site into JSON.

    python3 scripts/fetch_conditions.py            # nmcp-portsmouth
    python3 scripts/fetch_conditions.py wrnmmc-bethesda

Writes data/live/<site>-conditions.json. The running app reads that file and
never calls a network service, for the same reason the satellite basemap is
frozen: a demo that depends on venue wifi is a demo that fails on stage.

Two public sources, neither needs a key:

  NWS NWPS      river stage and the gauge's own published flood categories, in
                ft MLLW. Portsmouth uses EZMV2, Elizabeth River at the Midtown
                Tunnel (USGS 0204288831), about 1.5 mi from the hospital.
  NWS           api.weather.gov point forecast: wind, and the forecast text.

Units are a trap here. NWPS reports ft MLLW; NOAA CO-OPS `floodlevels.json`
reports *station datum*, and at Sewells Point the two differ by 4.38 ft -- more
than the entire minor-to-major flood range. Everything below stays in ft MLLW
and converts once, at the end.

Why this matters to the simulation: RED's flood mechanism is gated on element
elevation against a surge stage, and until now that stage was a constant in the
site file. With this, the gate is set from water level that was actually
measured, so "the adversary planned against this morning's conditions" is a
statement about data rather than a figure of speech.

Re-run it the morning of a demo. Do NOT run it during one.
"""

import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
UA = {"User-Agent": "BLACKSTART/0.1 (hackathon project; grid resilience simulation)"}

# `nwps` is the NWS gauge id. It is preferred over the NOAA CO-OPS tide station
# because NWPS publishes stage AND flood categories natively in ft MLLW, and
# because EZMV2 sits on the Elizabeth River about 1.5 mi from the hospital rather
# than across the harbour at Sewells Point.
#
# `record_crest_ft_mllw` is the highest storm tide ever measured at the harbour
# reference gauge (Sewells Point, 8638610): 8.02 ft on 1933-08-23, the
# Chesapeake-Potomac hurricane. Isabel 2003 reached 7.89 ft. That is the ceiling
# a modeled worst-credible surge is allowed to claim.
SITES = {
    "nmcp-portsmouth": {
        "nwps": "EZMV2",              # Elizabeth River at the Midtown Tunnel
        "gauge_name": "Elizabeth River at the Midtown Tunnel",
        "lat": 36.8468, "lon": -76.3125,
        "river": "Elizabeth River",
        "record_crest_ft_mllw": 8.02,
        "record_crest_event": "Chesapeake-Potomac hurricane, 23 Aug 1933",
    },
    "wrnmmc-bethesda": {
        "nwps": "WASD2",              # Potomac River at Washington DC
        "gauge_name": "Potomac River at Washington, DC",
        "lat": 38.9987, "lon": -77.0947,
        "river": "Rock Creek / Potomac",
        "record_crest_ft_mllw": 11.3,
        "record_crest_event": "Hurricane Isabel, 19 Sep 2003",
    },
}

FT_PER_M = 3.28084


def get(url: str, timeout: int = 20):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def gauge_state(nwps_id: str) -> dict:
    """Observed stage, NWS forecast peak, and published flood categories.

    All stages are ft MLLW, which is what NWPS reports for these gauges. Do not
    mix these with CO-OPS "station datum" values -- at Sewells Point the two
    differ by 4.38 ft, which is larger than the entire minor-to-major range.
    """
    d = get(f"https://api.water.noaa.gov/nwps/v1/gauges/{nwps_id}")
    cats = (d.get("flood") or {}).get("categories") or {}
    status = d.get("status") or {}
    obs = (status.get("observed") or {})
    fc = (status.get("forecast") or {})

    def cat(name):
        c = cats.get(name) or {}
        return c.get("stage")

    return {
        "gauge_nwps": nwps_id,
        "gauge_label": d.get("name"),
        "usgs_id": d.get("usgsId"),
        "stage_units": "ft MLLW",
        "observed_ft_mllw": obs.get("primary"),
        "observed_at": obs.get("validTime"),
        "observed_category": obs.get("floodCategory"),
        "forecast_peak_ft_mllw": fc.get("primary"),
        "forecast_at": fc.get("validTime"),
        "flood_action_ft": cat("action"),
        "flood_minor_ft": cat("minor"),
        "flood_moderate_ft": cat("moderate"),
        "flood_major_ft": cat("major"),
    }


def forecast(lat: float, lon: float) -> dict:
    """NWS point forecast: the current period, plus wind."""
    pt = get(f"https://api.weather.gov/points/{lat},{lon}")
    fc = get(pt["properties"]["forecast"])
    p = fc["properties"]["periods"][0]
    return {
        "period": p.get("name"),
        "detail": p.get("detailedForecast"),
        "short": p.get("shortForecast"),
        "wind": p.get("windSpeed"),
        "wind_direction": p.get("windDirection"),
        "temp_f": p.get("temperature"),
        "office": pt["properties"].get("gridId"),
    }


def main() -> None:
    site = sys.argv[1] if len(sys.argv) > 1 else "nmcp-portsmouth"
    if site not in SITES:
        print(f"unknown site '{site}'. known: {', '.join(SITES)}")
        raise SystemExit(2)
    cfg = SITES[site]

    out = {
        "site": site,
        "gauge_name": cfg["gauge_name"],
        "river": cfg["river"],
        "sources": [
            "NWS NWPS api.water.noaa.gov (stage + flood categories, ft MLLW)",
            "NWS api.weather.gov (point forecast)",
        ],
        "errors": [],
    }

    for label, fn in (
        ("gauge", lambda: gauge_state(cfg["nwps"])),
        ("forecast", lambda: forecast(cfg["lat"], cfg["lon"])),
    ):
        try:
            out.update(fn())
        except (urllib.error.URLError, KeyError, IndexError, ValueError) as exc:
            # A partial file is fine and the loader tolerates it. Silently
            # writing a plausible default would be worse than saying so.
            out["errors"].append(f"{label}: {type(exc).__name__}: {exc}")
            print(f"  ! {label} failed: {exc}")

    # Surge stage the flood gate compares element elevations against.
    #
    # NOT observed level plus invented headroom -- an earlier version did that and
    # produced 13 ft, which is higher than any storm tide ever measured here. The
    # stage a *modeled worst-credible hurricane* reaches is bounded by what has
    # actually happened, so it is the record crest, floored at the gauge's own
    # published major-flood category.
    crest = cfg.get("record_crest_ft_mllw")
    major = out.get("flood_major_ft")
    ft = max([v for v in (crest, major) if v is not None], default=None)
    if ft is not None:
        out["surge_stage_ft_mllw"] = round(float(ft), 2)
        out["surge_stage_m"] = round(float(ft) / FT_PER_M, 2)
        out["surge_basis"] = (
            f"worst-credible storm tide {ft} ft MLLW "
            f"({cfg.get('record_crest_event', 'record crest')}; gauge major-flood "
            f"category {major} ft), converted to metres"
        )
    out["record_crest_ft_mllw"] = crest
    out["record_crest_event"] = cfg.get("record_crest_event")

    dest = ROOT / "data" / "live" / f"{site}-conditions.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {dest.relative_to(ROOT)}")
    for k in ("gauge_label", "observed_ft_mllw", "observed_at", "observed_category",
              "forecast_peak_ft_mllw", "flood_minor_ft", "flood_major_ft",
              "surge_stage_ft_mllw", "surge_stage_m", "wind", "short"):
        if out.get(k) is not None:
            print(f"  {k:18s} {out[k]}")


if __name__ == "__main__":
    main()
