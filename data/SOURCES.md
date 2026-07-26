# Where the data comes from

Straight answer to "is this real?": **the campus, the design rules, and the
mandates are sourced from federal documents. The wiring between the buildings is
not** — as-built single-line drawings for a military hospital are not public, and
we would not publish them if they were. Everything below separates the two.

Every URL here was fetched and the quoted text read out of the document.

---

## What is sourced

### The campus is a real place, at real size

| Fact | Value | Source |
|---|---|---|
| Buildings owned | **34** | DoD Base Structure Report FY23, sheet "Federal DoD Main Report", row 1479 |
| Square footage owned | **2,213,043** | same row |
| Acreage | **110.51 owned / 110.52 total** | same row |
| Plant replacement value | **$1,495.9M** | same row |
| Main clinical building | Charette Health Care Center, **1.02M sq ft, 353 inpatient beds, 17 operating rooms**, opened 30 Apr 1999 | DVIDS, "NMCP Celebrates Charette Building 25th Anniversary" |
| Address | 620 John Paul Jones Circle, Portsmouth VA 23708 | health.mil MHS facility page |

BSR FY23 is the newest public edition; FY24+ is CUI and needs a CAC.
`https://web.archive.org/web/20231119065716id_/https://www.acq.osd.mil/eie/Downloads/BSI/Base%20Structure%20Report%20FY23.xlsx`

### The energy plant and its designations are real

Element names in `data/sites/nmcp-portsmouth.json` are not invented. They come out
of federal contract awards on USAspending:

| Our element | Real record |
|---|---|
| Central Energy Plant Bus, CEP Generator 1/2 | **"X008 NMCP CEP20 GENERATOR PLANT REPAIRS"** — $860,246, NAVFAC Mid-Atlantic. The central energy plant is **Building 20**, designated **CEP20**. |
| a campus substation | **"NMCP BLDG 3 SUBSTATION 30 TRANSFORMER REPLACEMENT"** — $168,711 |
| medium-voltage bus | **"X001 REPAIR / REPLACE NMCP BUILD-3 ELECTRICAL BUS"** — $477,050 |
| standby generation | **"NMCP BUILDING 003 REPLACE EMERGENCY GENERATORS"** — $2,935,469 |
| generator controls | **"DESIGN AND REPAIR/RENEW BY REPLACEMENT THE EMERGENCY POWER GENERATOR CONTROLLERS AT NAVAL MEDICAL CENTER PORTSMOUTH"** — $4,734,014, USACE Huntsville, period of performance **2025-09-30 → 2026-10-24** |

That last one is worth reading twice: the emergency power generator controllers at
this hospital are **under active replacement right now**. This is not a
hypothetical facility with a hypothetical problem.

### The topology follows mandatory design criteria, not our taste

**UFC 4-510-01, "Design: Military Medical Facilities," 3 Feb 2023** is the binding
criteria document for DoD medical facilities. Our model is shaped by it:

| What we modeled | What the UFC requires |
|---|---|
| Two utility feeders from two substations | ¶11-3.3.1 — *"Provide hospitals with two primary feeders… **Connect primary feeders to different power sources** (main electric supply substations) if available, and differently route the two primary feeders such that they are **electrically and geographically separated**."* Each sized for full hospital demand + 20% growth. |
| 34.5 kV feeders | ¶11-3.1 lists 34.5 kV among installation primary distribution voltages. |
| Normally-open tie switches | ¶11-3.3.3 — *"Design all double-ended substations for **normal open tie breaker** operation, which is interlocked with the main breakers, so that all three breakers 'main-tie-main' cannot be closed simultaneously. **Upon loss of a single transformer or its feeder, the main breaker is automatically opened and the tie breaker is automatically closed**."* |
| A 96-hour endurance target | ¶11-4.12.1 — *"**Provide a four day capacity at full load for the fuel oil tank**."* Four days is 96 hours. Day tanks separately sized for ≥4 hours. |
| Generators carrying load immediately | ¶11-4.4 — *"the ability to **start and assume its full electrical loads within 10 seconds**"*, plus alarms for *"less than four hours of fuel supply."* |
| Diesel, never gas | ¶11-4.12.3 — *"**Do not use natural gas** or comparable gas fuel as an operating fuel for hospital emergency power generation."* |

`https://www.wbdg.org/dod/ufc/ufc-4-510-01`

So the tie switches in our graph are not a game mechanic. They are a mandated
feature of the real design, and the UFC says they are supposed to close
automatically on loss of a feeder — which is precisely the reconfiguration
decision the simulator makes visible.

### "Black start" is doctrine, not branding

The DoD runs **Black Start Exercises** to find energy vulnerabilities, and
**NSA Hampton Roads — the installation complex Portsmouth sits in — ran one in
FY2023.**

> "Ten (10) BSEs in FY 2023: … NSA Panama City, **NSA Hampton Roads**, Naval
> Station Everett, and NSA Mid-South."
> — *Annual Energy Performance, Resilience, and Readiness Report FY 2023*, Table 2,
> "BSEs for Determining Energy Vulnerabilities"

Same report, on the standard being measured against:

> "progress toward achieving a **minimum level of 99.9 percent energy system
> reliability for critical missions by 2030**. The average system reliability… is
> **approximately 99.6 percent for the entire DoD**." (p. 20)

`https://www.acq.osd.mil/eie/ero/ier/docs/aeprr/FY23-AEPRR-Report.pdf`

### The problem is measured, not asserted

**GAO-17-27, "Defense Infrastructure: Actions Needed to Strengthen Utility
Resilience Planning," Nov 2016** — a survey of 364 DoD installation respondents:

> "143 reported a total of **4,393 utility disruptions** caused by equipment
> failure for fiscal years 2009 through 2015." (p. 11) — of which **1,838 were on
> electric utility systems** (p. 12), with **"over $29 million in financial
> impacts"** (p. 18).

`https://www.gao.gov/assets/gao-17-27.pdf`

### The mandates

- **10 U.S.C. §2925** — energy resilience reporting for installations.
- **42 CFR 482.15** — CMS emergency preparedness: a plan, documented, tested, reviewed.
- Imagery: **Esri World Imagery** (Esri, Maxar, Earthstar Geographics), frozen
  locally by `scripts/fetch_satellite.py` so the demo never calls a tile server.
- Geography: element coordinates sit inside the real NMCP bounding box
  (36.8415–36.8482 N, −76.3156 → −76.3009 W).

---

## What is NOT sourced, and must not be claimed

Say these plainly if a judge asks. They are the honest boundary of the model.

1. **The conductor list is ours.** Which switchboard feeds which ward, and which
   cable runs where, is an engineering estimate consistent with UFC 4-510-01 — not
   NMCP's as-built drawings. Those are not public. A per-building inventory
   (number → name → sq ft) does not exist publicly either; the BSR gives only the
   aggregate count of 34.
2. **Electrical ratings are estimates.** Generator kW, fuel gallons, per-facility
   kW, battery kWh. No public document gives NMCP's installed chiller tonnage,
   boiler capacity, generator MW, or switchgear ratings. We looked.
3. **Elevations are estimates,** not sampled from a DEM. This matters because
   RED's flood plausibility gate compares element elevation against a surge stage,
   so that gate is currently checking a modeled number. Wiring it to USGS 3DEP and
   a NOAA tide datum is the highest-value data upgrade left.
4. **Tier assignment is a judgement, deliberately.** Deciding the ICU is tier 1 and
   the galley is tier 3 is a call a facility's own engineers make. The tool
   computes the consequences of that list; it does not author it.
5. **No live feed.** Endurance is computed from graph state, not from a real
   telemetry or weather stream. Nothing here reads a sensor.

## What we could not verify

Listed so nobody re-treads it: `portsmouth.tricare.mil`, `med.navy.mil`,
`dodig.mil` and `atlantic.navfac.navy.mil` all return 403 to automated fetches;
Navy FMB MILCON budget books are CAPTCHA-gated; BSR FY24+ is CUI. There is no
NMCP energy project in any DHA MILCON or ERCIP book FY2019–FY2027 except **FY2021
ERCIP P-1803**, an air-handler retrofit at $611K.
