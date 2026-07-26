"""BLACKSTART - Emergent islanding and endurance.

There is no connected-components algorithm in this file. `Energize` walks
outward from every live source and is filtered to passable conductors only, so
a de-energized conductor is not an edge it declines to take - it is an edge it
cannot see. Islands are what the walker could reach. Cut a conductor and the
partition changes with no code noticing.

Endurance is arithmetic, deliberately. No model participates in deciding how
long anything survives.
"""

import from grid.model {
    GridNode, Substation, Generator, Battery, Facility, Conductor, IslandView
}

import from grid.campus { site_target_hours }

# Diesel genset heat rate, industry rule of thumb: gallons burned per kWh.
glob GAL_PER_KWH: float = 0.071;
# Kept as a name for readability; the value comes from the active site file.
glob TARGET_HOURS: float = 96.0;
# Sentinel endurance for an island still backed by a live utility feed. On
# utility you are not on a countdown, so the number is not meaningful.
glob UTILITY_HOURS: float = 999.0;


"""Walk outward from a source across passable conductors only."""
walker Energize {
    has island_id: int = 0;

    can spread with GridNode entry {
        # Already claimed by an earlier source - stop expanding from here but
        # let the rest of this walker's queue finish. `skip`, never
        # `disengage`: disengage would abandon sibling branches.
        if here.island_id != -1 { skip; }
        if here.damaged { skip; }
        here.island_id = self.island_id;
        visit [->:Conductor:passable == True:->];
        visit [<-:Conductor:passable == True:<-];
    }
}


"""Every grid element attached to root."""
def all_elements -> list[GridNode] {
    return [root --> [?:GridNode]];
}


"""Recompute Conductor.passable from its closed/damaged state."""
def sync_conductors {
    for n in all_elements() {
        for e in [edge n ->:Conductor:->] {
            e.passable = e.closed and (not e.damaged);
        }
    }
}


"""True if this element can originate power right now."""
def is_live_source(n: GridNode) -> bool {
    if n.damaged { return False; }
    if isinstance(n, Generator) {
        g = n as Generator;
        return g.online and g.fuel_gal > 0.0;
    }
    if isinstance(n, Substation) {
        s = n as Substation;
        return s.utility_source and s.utility_live;
    }
    return False;
}


"""Assign every element an island id. Dark elements keep -1."""
def recompute_islands {
    sync_conductors();
    for n in all_elements() { n.island_id = -1; }
    next_id = 1;
    for n in all_elements() {
        if is_live_source(n) and n.island_id == -1 {
            n spawn Energize(island_id=next_id);
            next_id += 1;
        }
    }
}


"""Hours this set of elements can serve its own load, from fuel and storage."""
def endurance_of(members: list[GridNode]) -> float {
    load_kw = 0.0;
    gen_kw = 0.0;
    fuel_gal = 0.0;
    batt_kwh = 0.0;
    utility = False;

    for m in members {
        if isinstance(m, Facility) {
            f = m as Facility;
            if not f.shed { load_kw += f.kw; }
        } elif isinstance(m, Generator) {
            g = m as Generator;
            if g.online {
                gen_kw += g.kw_rating;
                fuel_gal += g.fuel_gal;
            }
        } elif isinstance(m, Battery) {
            batt_kwh += (m as Battery).kwh_stored;
        } elif isinstance(m, Substation) {
            s = m as Substation;
            if s.utility_source and s.utility_live { utility = True; }
        }
    }

    # Still on the grid - not on a countdown.
    if utility { return UTILITY_HOURS; }
    # Nothing to serve.
    if load_kw <= 0.0 { return UTILITY_HOURS; }
    # Storage only.
    if gen_kw <= 0.0 { return batt_kwh / load_kw; }
    # Generation covers the load: fuel is the only limit.
    if gen_kw >= load_kw { return fuel_gal / (GAL_PER_KWH * load_kw); }
    # Generation is short. Gensets run flat out, storage covers the deficit,
    # and whichever runs out first ends it.
    gen_hours = fuel_gal / (GAL_PER_KWH * gen_kw);
    batt_hours = batt_kwh / (load_kw - gen_kw);
    return gen_hours if gen_hours < batt_hours else batt_hours;
}


"""Group the graph into islands and score each one."""
def survey -> list[IslandView] {
    groups: dict[int, list[GridNode]] = {};
    for n in all_elements() {
        if n.island_id == -1 { continue; }
        if n.island_id not in groups { groups[n.island_id] = []; }
        groups[n.island_id].append(n);
    }

    out: list[IslandView] = [];
    for (iid, members) in groups.items() {
        names: list[str] = [];
        served = 0.0;
        tier1 = False;
        has_gen = False;
        for m in members {
            if isinstance(m, Facility) {
                f = m as Facility;
                names.append(f.name);
                if not f.shed {
                    served += f.kw;
                    if f.tier == 1 { tier1 = True; }
                }
            } elif isinstance(m, Generator) {
                if (m as Generator).online { has_gen = True; }
            }
        }
        out.append(IslandView(
            id=iid, members=names, endurance_hours=endurance_of(members),
            has_generation=has_gen, tier1_present=tier1, served_kw=served
        ));
    }
    return out;
}


"""Facilities the walker could not reach at all - no source, no path."""
def dark_facilities -> list[Facility] {
    out: list[Facility] = [];
    for f in [root --> [?:Facility]] {
        if f.island_id == -1 { out.append(f); }
    }
    return out;
}


"""The headline number: the worst endurance among islands carrying tier-1 load.

A tier-1 load the walker could not reach at all counts as zero - stranding the
ICU collapses the site number rather than denting it, which is the whole point.
"""
def site_endurance(islands: list[IslandView]) -> float {
    for f in dark_facilities() {
        if f.tier == 1 { return 0.0; }
    }
    worst = UTILITY_HOURS;
    seen = False;
    for i in islands {
        if i.tier1_present {
            seen = True;
            if i.endurance_hours < worst { worst = i.endurance_hours; }
        }
    }
    return worst if seen else UTILITY_HOURS;
}


"""True when any tier-1 load is dark or sitting under the target."""
def tier1_stranded(islands: list[IslandView]) -> bool {
    for f in dark_facilities() {
        if f.tier == 1 { return True; }
    }
    for i in islands {
        if i.tier1_present and i.endurance_hours < site_target_hours() { return True; }
    }
    return False;
}
