"""BLACKSTART - Naval Medical Center Portsmouth campus fixture.

27 elements modeled on NMCP: a hospital (ICU, ORs, NICU, ED) that is also a
DoD installation. One building, two mandates - CMS emergency preparedness and
10 U.S.C. 2925 energy resilience reporting.

Topology is deliberately redundant. Bus-North is fed BOTH by the Elizabeth
River utility substation AND by the Central Energy Plant tie. That second path
is the thing RED does not know about in round 1 and learns in round 2.

Numbers are sized so the demo lands:
  both utilities lost  -> 76.1 h  (under the 96 h target)
  shed all tier 3      -> 93.5 h  (STILL under - the graded response)
  shed Imaging (t2)    -> 108.3 h (clears, holds)
  CEP tie cut first    -> critical wing isolated on one 800 kW generator,
                          nothing left to shed, endurance breach
"""

import from grid.model {
    GridNode, Substation, Generator, Battery, Facility, Conductor, Run
}

glob TARGET_HOURS: float = 96.0;
glob GAL_PER_KWH: float = 0.071;


"""Close a normally-closed conductor between two elements."""
def wire(a: GridNode, b: GridNode, label: str) {
    a +>:Conductor(label=label):+> b;
}


"""A normally-open tie switch. Present in the graph but not passable."""
def tie(a: GridNode, b: GridNode, label: str) {
    a +>:Conductor(label=label, closed=False, passable=False, normally_open=True):+> b;
}


"""Construct the NMCP campus graph and attach it to root."""
def build_campus -> Run {
    run = (root ++> Run(site="Naval Medical Center Portsmouth", memory_enabled=True))[0];

    # ---------------------------------------------------------- utility feeds
    # Elizabeth is the river-side feed at 2.1 m elevation - the flood-exposed
    # one. Effingham sits on higher ground at 8.4 m.
    sub_eliz = root ++> Substation(
        name="Elizabeth River Substation", kind="substation",
        lat=36.8432, lon=-76.3055, elevation_m=2.1,
        kv=34.5, utility_source=True
    );
    sub_effi = root ++> Substation(
        name="Effingham Street Substation", kind="substation",
        lat=36.8465, lon=-76.3110, elevation_m=8.4,
        kv=34.5, utility_source=True
    );

    # ------------------------------------------------------ generation / storage
    gen1 = root ++> Generator(
        name="CEP Generator 1", kind="generator",
        lat=36.8441, lon=-76.3108, elevation_m=3.2,
        kw_rating=1500.0, fuel_gal=6000.0
    );
    gen2 = root ++> Generator(
        name="CEP Generator 2", kind="generator",
        lat=36.8439, lon=-76.3106, elevation_m=3.2,
        kw_rating=1500.0, fuel_gal=6000.0
    );
    gen3 = root ++> Generator(
        name="Charette Standby Generator", kind="generator",
        lat=36.8455, lon=-76.3072, elevation_m=7.1,
        kw_rating=800.0, fuel_gal=2000.0
    );
    ups_char = root ++> Battery(
        name="Charette Critical Branch UPS", kind="battery",
        lat=36.8457, lon=-76.3074, elevation_m=7.2,
        kwh_stored=900.0, kwh_capacity=900.0, max_kw=600.0
    );
    ups_data = root ++> Battery(
        name="Data Center UPS", kind="battery",
        lat=36.8453, lon=-76.3068, elevation_m=7.4,
        kwh_stored=400.0, kwh_capacity=400.0, max_kw=250.0
    );

    # ------------------------------------------------------------- switchgear
    bus_cep = root ++> GridNode(
        name="Central Energy Plant Bus", kind="bus",
        lat=36.8443, lon=-76.3103, elevation_m=3.2
    );
    bus_north = root ++> GridNode(
        name="North Campus Switchgear", kind="bus",
        lat=36.8458, lon=-76.3085, elevation_m=6.5
    );
    bus_south = root ++> GridNode(
        name="South Campus Switchgear", kind="bus",
        lat=36.8435, lon=-76.3092, elevation_m=4.2
    );
    bus_ca = root ++> GridNode(
        name="Charette Switchboard A", kind="bus",
        lat=36.8456, lon=-76.3078, elevation_m=7.0
    );
    bus_cb = root ++> GridNode(
        name="Charette Switchboard B", kind="bus",
        lat=36.8451, lon=-76.3075, elevation_m=6.8
    );

    # ---------------------------------------------------------- tier 1 loads
    icu = root ++> Facility(
        name="Intensive Care Unit", kind="facility", category="critical care",
        lat=36.8460, lon=-76.3080, elevation_m=7.5, tier=1, kw=210.0
    );
    surgical = root ++> Facility(
        name="Surgical Suite", kind="facility", category="operating rooms",
        lat=36.8462, lon=-76.3076, elevation_m=7.6, tier=1, kw=340.0
    );
    nicu = root ++> Facility(
        name="Neonatal ICU", kind="facility", category="critical care",
        lat=36.8459, lon=-76.3073, elevation_m=7.5, tier=1, kw=130.0
    );
    ed = root ++> Facility(
        name="Emergency Department", kind="facility", category="emergency",
        lat=36.8449, lon=-76.3070, elevation_m=6.6, tier=1, kw=260.0
    );
    datactr = root ++> Facility(
        name="Network Core and Telemetry", kind="facility", category="communications",
        lat=36.8452, lon=-76.3066, elevation_m=7.4, tier=1, kw=180.0
    );
    firepump = root ++> Facility(
        name="Fire Pump House", kind="facility", category="life safety",
        lat=36.8437, lon=-76.3098, elevation_m=3.9, tier=1, kw=95.0
    );

    # ---------------------------------------------------------- tier 2 loads
    tower5 = root ++> Facility(
        name="Inpatient Tower Floor 5", kind="facility", category="inpatient ward",
        lat=36.8464, lon=-76.3082, elevation_m=7.8, tier=2, kw=220.0
    );
    imaging = root ++> Facility(
        name="Radiology and MRI", kind="facility", category="imaging",
        lat=36.8447, lon=-76.3073, elevation_m=6.4, tier=2, kw=290.0
    );
    pharmacy = root ++> Facility(
        name="Inpatient Pharmacy", kind="facility", category="pharmacy",
        lat=36.8450, lon=-76.3079, elevation_m=6.7, tier=2, kw=85.0
    );
    lab = root ++> Facility(
        name="Clinical Laboratory", kind="facility", category="laboratory",
        lat=36.8446, lon=-76.3078, elevation_m=6.5, tier=2, kw=140.0
    );
    sterile = root ++> Facility(
        name="Sterile Processing", kind="facility", category="sterile processing",
        lat=36.8444, lon=-76.3070, elevation_m=6.2, tier=2, kw=160.0
    );

    # ---------------------------------------------------------- tier 3 loads
    admin = root ++> Facility(
        name="Building One Administration", kind="facility", category="administration",
        lat=36.8430, lon=-76.3088, elevation_m=3.4, tier=3, kw=110.0
    );
    galley = root ++> Facility(
        name="Galley and Food Service", kind="facility", category="food service",
        lat=36.8433, lon=-76.3084, elevation_m=3.8, tier=3, kw=175.0
    );
    garage = root ++> Facility(
        name="Parking Structure and Site Lighting", kind="facility", category="site services",
        lat=36.8427, lon=-76.3095, elevation_m=2.8, tier=3, kw=65.0
    );
    annex = root ++> Facility(
        name="Outpatient Clinic Annex", kind="facility", category="outpatient",
        lat=36.8438, lon=-76.3086, elevation_m=4.1, tier=3, kw=130.0
    );

    # ------------------------------------------------------------- conductors
    # Utility in.
    wire(sub_eliz, bus_north, "Elizabeth 34.5kV Feeder");
    wire(sub_effi, bus_south, "Effingham 34.5kV Feeder");

    # Generation onto the plant bus.
    wire(gen1, bus_cep, "Gen 1 Breaker");
    wire(gen2, bus_cep, "Gen 2 Breaker");

    # THE REDUNDANT PATH. This is what RED has to discover: the plant bus can
    # backfeed North even after the Elizabeth feeder is gone.
    wire(bus_cep, bus_north, "CEP North Tie");
    wire(bus_cep, bus_south, "CEP South Tie");

    # Sectionalized plant bus. Each machine also has a direct breaker onto a
    # campus bus, so losing the plant bus itself does not orphan 3000 kW of
    # generation. Without these the plant bus is a one-strike kill, and the
    # memory A/B saturates in round 1 with no headroom left to measure.
    wire(gen1, bus_north, "Gen 1 North Direct");
    wire(gen2, bus_south, "Gen 2 South Direct");

    # Campus distribution.
    wire(bus_north, bus_ca, "North to Charette A");
    wire(bus_north, bus_cb, "North to Charette B");
    wire(gen3, bus_ca, "Charette Standby Breaker");
    wire(ups_char, bus_ca, "Critical Branch UPS Tie");
    wire(ups_data, datactr, "Data Center UPS Tie");

    # Charette A - the critical wing.
    wire(bus_ca, icu, "Feeder A1");
    wire(bus_ca, surgical, "Feeder A2");
    wire(bus_ca, nicu, "Feeder A3");
    wire(bus_ca, tower5, "Feeder A4");

    # Charette B.
    wire(bus_cb, ed, "Feeder B1");
    wire(bus_cb, imaging, "Feeder B2");
    wire(bus_cb, pharmacy, "Feeder B3");
    wire(bus_cb, lab, "Feeder B4");
    wire(bus_cb, sterile, "Feeder B5");
    wire(bus_cb, datactr, "Feeder B6");

    # South campus.
    wire(bus_south, admin, "Feeder S1");
    wire(bus_south, galley, "Feeder S2");
    wire(bus_south, garage, "Feeder S3");
    wire(bus_south, annex, "Feeder S4");
    wire(bus_south, firepump, "Feeder S5");

    # Normally-open ties. BLUE-2 reconfiguration may close these; nothing else
    # touches them.
    tie(bus_ca, bus_cb, "Charette A-B Tie");
    tie(bus_north, bus_south, "North-South Campus Tie");

    return run;
}


"""Tear down any existing campus and rebuild a clean one."""
def reset_campus -> Run {
    for n in [root --> [?:GridNode]] { del n; }
    for r in [root --> [?:Run]] { del r; }
    return build_campus();
}
