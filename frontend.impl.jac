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
    lres = root spawn GetLessons();
    lessons = lres.reports;
}

impl app.onLoadSite -> None {
    busy = True;
    status = "Rebuilding the campus...";
    _ = root spawn LoadSite(memory_enabled=True);
    explain_lines = [];
    rounds = [];
    await refresh();
    status = "";
    busy = False;
}

impl app.onCutRiver -> None {
    busy = True;
    status = "Opening the Elizabeth River feeder...";
    _ = root spawn CutConductor(label="Elizabeth 34.5kV Feeder");
    await refresh();
    status = "River feeder open. Still lit - a second path is carrying the campus.";
    busy = False;
}

impl app.onCutBoth -> None {
    busy = True;
    status = "Opening both utility feeders...";
    _ = root spawn CutConductor(label="Elizabeth 34.5kV Feeder");
    _ = root spawn CutConductor(label="Effingham 34.5kV Feeder");
    await refresh();
    status = "Both utility feeds gone. The campus is on its own generation.";
    busy = False;
}

impl app.onRunBlue -> None {
    busy = True;
    status = "Running the controller...";
    _ = root spawn RunBlue();
    await refresh();
    status = "";
    busy = False;
}

impl app.onRunRound -> None {
    busy = True;
    status = "RED is planning. This takes a moment - two model calls.";
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
