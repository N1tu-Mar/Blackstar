"""Handler bodies for the BLACKSTART console."""

impl app.refresh -> None {
    result = root spawn GetDashboard();
    if result.reports {
        d = result.reports[0];
        elements = d.elements;
        islands = d.islands;
        events = d.recent_events;
        site = d.site;
        endurance = d.site_endurance_hours;
        target = d.target_hours;
    }
    mres = root spawn GetMap();
    if mres.reports {
        map_nodes = mres.reports[0].nodes;
        map_edges = mres.reports[0].edges;
    }
    # The satellite backdrop is ~550 KB of base64. Fetch it once, not per tick.
    if satellite == "" {
        bres = root spawn GetBasemap();
        if bres.reports {
            bp = bres.reports[0];
            satellite = bp.satellite;
            view_w = bp.width;
            view_h = bp.height;
            attribution = bp.attribution;
        }
    }
    sres = root spawn ListSites();
    sites = sres.reports;
    # Track the server's active site rather than whatever the <select> happens
    # to show first, or the picker lies about what is loaded.
    active_id = "";
    for s in sres.reports {
        if s.active { active_id = s.id; }
    }
    if active_id != "" { site_id = active_id; }
    lres = root spawn GetLessons();
    lessons = lres.reports;
}


impl app.onPickSite(e: ChangeEvent) -> None {
    chosen = e.target.value;
    site_id = chosen;
    busy = True;
    status = "Loading site...";
    _ = root spawn LoadSite(memory_enabled=True, site_id=chosen);
    explain_lines = [];
    rounds = [];
    # The satellite backdrop belongs to the old site; force a refetch.
    satellite = "";
    await refresh();
    status = "";
    busy = False;
}

impl app.onLoadSite -> None {
    busy = True;
    status = "Resetting...";
    _ = root spawn LoadSite(memory_enabled=True);
    explain_lines = [];
    rounds = [];
    await refresh();
    status = "";
    busy = False;
}

impl app.onCutRiver -> None {
    busy = True;
    status = "Opening one incoming power line...";
    _ = root spawn CutConductor(label="Elizabeth 34.5kV Feeder");
    await refresh();
    status = "Still lit. A second path is carrying the site.";
    busy = False;
}

impl app.onCutBoth -> None {
    busy = True;
    status = "Cutting all incoming grid power...";
    _ = root spawn CutConductor(label="Elizabeth 34.5kV Feeder");
    _ = root spawn CutConductor(label="Effingham 34.5kV Feeder");
    await refresh();
    status = "Grid power gone. The site is running on its own generators.";
    busy = False;
}

impl app.onRunBlue -> None {
    busy = True;
    status = "Shedding non-critical loads...";
    _ = root spawn RunBlue();
    await refresh();
    status = "";
    busy = False;
}

impl app.onRunRound -> None {
    busy = True;
    status = "Planning a disaster. This takes a moment.";
    rres = root spawn RunRound();
    if rres.reports {
        rounds = rounds + [rres.reports[0]];
    }
    await refresh();
    status = "";
    busy = False;
}

impl app.onExplain -> None {
    busy = True;
    result = root spawn ExplainWhy(subject=subject);
    if result.reports {
        explain_lines = result.reports[0].lines;
    }
    busy = False;
}
