import from endpoints { LoadSite, CutConductor, RunBlue, ExplainWhy }
import from grid.model { Dashboard }

"""Print the headline state."""
def show(tag: str, d: Dashboard) {
    print(f"{tag:38s} endurance={d.site_endurance_hours:7.1f}h  islands={len(d.islands)}");
    for e in d.elements {
        if e.status == "shed" { print(f"      SHED: {e.name}"); }
    }
}

with entry:__main__ {
    r = root spawn LoadSite(memory_enabled=True);
    show("(1) baseline", r.reports[0]);

    c1 = root spawn CutConductor(label="Elizabeth 34.5kV Feeder");
    show("(2) river feeder cut", c1.reports[0]);

    c2 = root spawn CutConductor(label="Effingham 34.5kV Feeder");
    show("(3) both utility feeds lost", c2.reports[0]);

    b = root spawn RunBlue();
    show("(4) after BLUE", b.reports[0]);

    print("\n=== WHY DID THE GALLEY GO DARK? ===");
    ex = root spawn ExplainWhy(subject="Galley and Food Service");
    for line in ex.reports[0].lines { print(f"  [{line.ref}] {line.text}"); }
}
