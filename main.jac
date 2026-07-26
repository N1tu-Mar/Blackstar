"""BLACKSTART - Entry point.

Wires the server-side grid API to the client-side console.
"""

import from endpoints {
    GetDashboard, GetMap, GetBasemap, GetLessons, ExplainWhy,
    LoadSite, CutConductor, RunBlue, RunRound
}

cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
