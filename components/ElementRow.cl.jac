"""One grid element in the console list."""

def:pub ElementRow(name: str, category: str, tier: int, status: str, island: int) -> JsxElement {
    color = "#0a0a0a";
    if status == "dark" { color = "#a3a3a3"; }
    if status == "shed" { color = "#f5a524"; }
    if status == "damaged" { color = "#e5484d"; }

    return
        <div style={{
            "display": "flex", "justifyContent": "space-between",
            "fontSize": "0.85rem", "padding": "0.28rem 0",
            "breakInside": "avoid", "color": color
        }}>
            <span>{name}</span>
            <span style={{"color": "#a3a3a3", "marginLeft": "1rem"}}>
                {f"T{tier} - {status}" if tier > 0 else status}
            </span>
        </div>;
}
