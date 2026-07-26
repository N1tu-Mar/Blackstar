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
    lres = root spawn GetLessons();
    lessons = lres.reports;
}

impl app.onLoadSite -> None {
    busy = True;
    status = "rebuilding campus...";
    _ = root spawn LoadSite(memory_enabled=True);
    explain_lines = [];
    await refresh();
    status = "";
    busy = False;
}

impl app.onRunBlue -> None {
    busy = True;
    status = "running the controller...";
    _ = root spawn RunBlue();
    await refresh();
    status = "";
    busy = False;
}

impl app.onRunRound -> None {
    busy = True;
    status = "RED is planning, this takes a moment...";
    _ = root spawn RunRound();
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
