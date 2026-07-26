# Sites

A site is data. The simulator — islanding, endurance, BLUE, provenance, and
RED — contains no knowledge of any particular campus, so modelling a different
hospital, base or utility means writing one JSON file here.

Select one at run time:

```bash
BLACKSTART_SITE=nmcp-portsmouth jac start --dev main.jac
```

## Adding a site

1. Write `data/sites/<id>.json` (schema below).
2. Fetch its imagery: `python3 scripts/fetch_satellite.py <id>`.
   It reads the view box straight out of your JSON, so the imagery and the
   projection cannot drift apart.
3. Run it: `BLACKSTART_SITE=<id> jac start --dev main.jac`.

## Schema

```jsonc
{
  "id": "nmcp-portsmouth",
  "name": "Naval Medical Center Portsmouth",   // shown in the UI and to RED
  "target_hours": 96.0,        // the endurance the site must demonstrate
  "flood_stage_m": 4.0,        // elevation below which flooding is plausible
  "view": {                    // render window; imagery is fetched to match
    "south": 36.84155, "north": 36.84815,
    "west": -76.31558, "east": -76.30092,
    "width_px": 1600.0, "height_px": 900.0
  },
  "satellite": "data/sites/nmcp-portsmouth-satellite.jpg",

  "elements": [
    { "name": "Elizabeth River Substation",    // RED names targets by this
      "type": "Substation",                    // Substation | Generator |
                                               // Battery | Facility | GridNode
      "kind": "substation",                    // used for marker sizing
      "lat": 36.8426, "lon": -76.3045,
      "elevation_m": 2.1,                      // drives the flood gate
      "kv": 34.5, "utility_source": true },

    { "name": "Intensive Care Unit", "type": "Facility", "kind": "facility",
      "lat": 36.8471, "lon": -76.30791, "elevation_m": 7.5,
      "tier": 1,                               // 1 is never shed
      "kw": 210.0, "category": "critical care" },

    { "name": "CEP Generator 1", "type": "Generator", "kind": "generator",
      "lat": 36.84405, "lon": -76.31173, "elevation_m": 3.2,
      "kw_rating": 1500.0, "fuel_gal": 6000.0 },

    { "name": "Charette Critical Branch UPS", "type": "Battery",
      "kind": "battery", "lat": 36.84662, "lon": -76.30709,
      "elevation_m": 7.2, "kwh_stored": 900.0, "kwh_capacity": 900.0,
      "max_kw": 600.0 }
  ],

  "conductors": [
    { "from": "Elizabeth River Substation", "to": "North Campus Switchgear",
      "label": "Elizabeth 34.5kV Feeder", "normally_open": false },
    { "from": "Charette Switchboard A", "to": "Charette Switchboard B",
      "label": "Charette A-B Tie", "normally_open": true }
  ]
}
```

## What makes a site worth simulating

The engine will happily run a trivial grid, but the demo only says something
if the topology has something to discover:

- **At least one redundant path.** If every load has exactly one route to
  generation, islanding is a formality and RED has nothing to learn.
- **Generation that is not a single point of failure.** An early version of
  Portsmouth fed both plant generators through one bus; RED found the
  one-strike kill immediately and the memory A/B came back null.
- **A spread of elevations**, or the flood mechanism is either always or never
  plausible and the gate teaches nothing.
- **20–30 elements.** Below that, round one reveals the whole structure.
