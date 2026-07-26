#!/usr/bin/env python3
"""Author the Walter Reed (WRNMMC) site file.

A second site, to demonstrate that the simulator is not Portsmouth-shaped.
Bethesda is inland, so the hazard is creek and stormwater flooding rather than
storm surge, and the flood stage is set in local elevation terms - which is
exactly the sort of thing that has to be per-site rather than a constant.

Topology follows the same principles documented in data/sites/README.md: a
redundant path the adversary has to discover, generation that is not a single
point of failure, a real spread of elevations, and two normally-open ties.

    python3 scripts/make_wrnmmc.py
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "sites" / "wrnmmc-bethesda.json"

# Walter Reed National Military Medical Center, Bethesda MD.
E = []


def el(name, etype, kind, lat, lon, elev, **kw):
    d = {"name": name, "type": etype, "kind": kind,
         "lat": round(lat, 5), "lon": round(lon, 5), "elevation_m": elev}
    d.update(kw)
    E.append(d)


# --- utility feeds. Rockville Pike sits high; Stoney Creek side sits low. ---
el("Rockville Pike Substation", "Substation", "substation",
   38.99760, -77.08790, 104.0, kv=34.5, utility_source=True)
el("Stoney Creek Substation", "Substation", "substation",
   38.99340, -77.09880, 88.5, kv=34.5, utility_source=True)

# --- generation. Two plant machines plus a tower standby. ---
el("CUP Generator 1", "Generator", "generator",
   38.99450, -77.09640, 90.5, kw_rating=1800.0, fuel_gal=6500.0)
el("CUP Generator 2", "Generator", "generator",
   38.99425, -77.09600, 90.5, kw_rating=1800.0, fuel_gal=6500.0)
el("America Building Standby", "Generator", "generator",
   38.99880, -77.09220, 107.0, kw_rating=1000.0, fuel_gal=3000.0)
el("Critical Branch UPS", "Battery", "battery",
   38.99905, -77.09265, 107.5, kwh_stored=1100.0, kwh_capacity=1100.0, max_kw=700.0)
el("Network Core UPS", "Battery", "battery",
   38.99820, -77.09090, 106.0, kwh_stored=450.0, kwh_capacity=450.0, max_kw=280.0)

# --- switchgear ---
el("Central Utility Plant Bus", "GridNode", "bus", 38.99480, -77.09580, 90.5)
el("North Campus Switchgear", "GridNode", "bus", 38.99870, -77.09330, 105.0)
el("South Campus Switchgear", "GridNode", "bus", 38.99400, -77.09480, 89.0)
el("America Switchboard A", "GridNode", "bus", 38.99845, -77.09195, 106.5)
el("America Switchboard B", "GridNode", "bus", 38.99775, -77.09145, 105.5)

# --- tier 1 ---
el("Intensive Care Unit", "Facility", "facility", 38.99930, -77.09300, 108.0,
   tier=1, kw=260.0, category="critical care")
el("Operating Suites", "Facility", "facility", 38.99965, -77.09225, 108.5,
   tier=1, kw=400.0, category="operating rooms")
el("Neonatal ICU", "Facility", "facility", 38.99900, -77.09150, 107.5,
   tier=1, kw=150.0, category="critical care")
el("Emergency Department", "Facility", "facility", 38.99740, -77.09070, 104.0,
   tier=1, kw=300.0, category="emergency")
el("Network Core and Telemetry", "Facility", "facility", 38.99795, -77.09030, 105.5,
   tier=1, kw=200.0, category="communications")
el("Fire Pump House", "Facility", "facility", 38.99365, -77.09560, 88.0,
   tier=1, kw=110.0, category="life safety")

# --- tier 2 ---
el("Inpatient Tower Floor 7", "Facility", "facility", 39.00010, -77.09310, 109.0,
   tier=2, kw=260.0, category="inpatient ward")
el("Radiology and MRI", "Facility", "facility", 38.99700, -77.09180, 103.0,
   tier=2, kw=350.0, category="imaging")
el("Inpatient Pharmacy", "Facility", "facility", 38.99760, -77.09240, 104.5,
   tier=2, kw=100.0, category="pharmacy")
el("Clinical Laboratory", "Facility", "facility", 38.99665, -77.09265, 102.5,
   tier=2, kw=160.0, category="laboratory")
el("Sterile Processing", "Facility", "facility", 38.99625, -77.09105, 101.5,
   tier=2, kw=180.0, category="sterile processing")

# --- tier 3 ---
el("Building 1 Administration", "Facility", "facility", 38.99290, -77.09400, 87.0,
   tier=3, kw=130.0, category="administration")
el("Dining Facility", "Facility", "facility", 38.99330, -77.09330, 87.5,
   tier=3, kw=200.0, category="food service")
el("Parking Garage and Site Lighting", "Facility", "facility", 38.99255, -77.09520, 86.0,
   tier=3, kw=80.0, category="site services")
el("Outpatient Clinic Wing", "Facility", "facility", 38.99510, -77.09300, 92.0,
   tier=3, kw=160.0, category="outpatient")

C = []


def wire(a, b, label, no=False):
    C.append({"from": a, "to": b, "label": label, "normally_open": no})


wire("Rockville Pike Substation", "North Campus Switchgear", "Rockville Pike 34.5kV Feeder")
wire("Stoney Creek Substation", "South Campus Switchgear", "Stoney Creek 34.5kV Feeder")

wire("CUP Generator 1", "Central Utility Plant Bus", "Gen 1 Breaker")
wire("CUP Generator 2", "Central Utility Plant Bus", "Gen 2 Breaker")

# The redundant path RED has to find, plus sectionalized machine breakers so
# the plant bus is not a one-strike kill.
wire("Central Utility Plant Bus", "North Campus Switchgear", "CUP North Tie")
wire("Central Utility Plant Bus", "South Campus Switchgear", "CUP South Tie")
wire("CUP Generator 1", "North Campus Switchgear", "Gen 1 North Direct")
wire("CUP Generator 2", "South Campus Switchgear", "Gen 2 South Direct")

wire("North Campus Switchgear", "America Switchboard A", "North to America A")
wire("North Campus Switchgear", "America Switchboard B", "North to America B")
wire("America Building Standby", "America Switchboard A", "Standby Breaker")
wire("Critical Branch UPS", "America Switchboard A", "Critical Branch UPS Tie")
wire("Network Core UPS", "Network Core and Telemetry", "Core UPS Tie")

for load, feeder in [("Intensive Care Unit", "A1"), ("Operating Suites", "A2"),
                     ("Neonatal ICU", "A3"), ("Inpatient Tower Floor 7", "A4")]:
    wire("America Switchboard A", load, f"Feeder {feeder}")

for load, feeder in [("Emergency Department", "B1"), ("Radiology and MRI", "B2"),
                     ("Inpatient Pharmacy", "B3"), ("Clinical Laboratory", "B4"),
                     ("Sterile Processing", "B5"), ("Network Core and Telemetry", "B6")]:
    wire("America Switchboard B", load, f"Feeder {feeder}")

for load, feeder in [("Building 1 Administration", "S1"), ("Dining Facility", "S2"),
                     ("Parking Garage and Site Lighting", "S3"),
                     ("Outpatient Clinic Wing", "S4"), ("Fire Pump House", "S5")]:
    wire("South Campus Switchgear", load, f"Feeder {feeder}")

wire("America Switchboard A", "America Switchboard B", "America A-B Tie", no=True)
wire("North Campus Switchgear", "South Campus Switchgear", "North-South Campus Tie", no=True)

site = {
    "id": "wrnmmc-bethesda",
    "name": "Walter Reed National Military Medical Center",
    "blurb": "Bethesda, Maryland. Inland, so the hazard is creek and stormwater "
             "flooding rather than storm surge.",
    "target_hours": 96.0,
    # Local terms: the low-lying south campus sits near Stoney Creek.
    "flood_stage_m": 91.0,
    "view": {"south": 38.99180, "north": 39.00120,
             "west": -77.10078, "east": -77.08322,
             "width_px": 1600.0, "height_px": 900.0},
    "satellite": "data/sites/wrnmmc-bethesda-satellite.jpg",
    "elements": E,
    "conductors": C,
}

OUT.write_text(json.dumps(site, indent=2))
load_kw = sum(e.get("kw", 0.0) for e in E)
fuel = sum(e.get("fuel_gal", 0.0) for e in E)
print(f"wrote {OUT}")
print(f"  {len(E)} elements, {len(C)} conductors")
print(f"  total load {load_kw:.0f} kW, fuel {fuel:.0f} gal")
print(f"  endurance on generators at full load: {fuel / (0.071 * load_kw):.1f} h")
