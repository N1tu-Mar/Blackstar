"""One grid element in the console list."""

def:pub ElementRow(name: str, category: str, tier: int, status: str, island: int) -> JsxElement {
    color = "#e6e6e6";
    if status == "dark" { color = "#5c6370"; }
    if status == "shed" { color = "#f0a020"; }
    if status == "damaged" { color = "#e05252"; }

    return
        <div style={{
            "display": "flex", "justifyContent": "space-between",
            "fontSize": "0.78rem", "padding": "0.15rem 0", "color": color
        }}>
            <span>{name}</span>
            <span style={{"color": "#5c6370"}}>
                {f"t{tier} - {status} - i{island}"}
            </span>
        </div>;
}
