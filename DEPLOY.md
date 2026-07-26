# Deploying BLACKSTART on JacHammer

BLACKSTART deploys as **one application**. JacHammer runs the project the way
`jac start main.jac` runs it here: the walker API and the operator console come
off the same origin, from the same process, holding the same graph.

That is the whole reason this is simple. Nothing is split, nothing has a
compiled-in API address, and there is no CORS surface — the console fetches
`/walker/GetDashboard` on its own host. The graph, the provenance archive and a
RED round that holds a request open for minutes all live in one place, which is
what this app needs and what a static frontend host cannot give it.

Verified from a clean checkout with an empty `.jac/data`: the console renders at
`/`, `ListSites` and `GetBasemap` answer same-origin, and the 566 KB satellite
basemap arrives intact.

---

## What the repo already provides

| JacHammer needs | Where it is |
|---|---|
| Entry point | `[project] entry-point = "main.jac"` in `jac.toml` |
| Console served at `/` | `[serve] base_route_app = "app"` |
| Python plugins | `[dependencies]` — `byllm`, `jac-client`. **Load-bearing:** without these listed, a fresh `jac install` on the builder produces an environment that cannot import `grid/red.jac` |
| Client deps | `[dependencies.npm]` — react, vite |
| Campus data | `data/sites/*.json` + satellite imagery, committed |

Nothing else to add. No Dockerfile, no manifests, no build config.

---

## Environment variables

Set these in **project settings → environment variables**, not in a file. They
are sourced into the app's own process for both the preview and any deploy.

| Variable | Needed for |
|---|---|
| `ANTHROPIC_API_KEY` | **Required for RED.** `RunRound` makes two `by llm()` calls and dies with a bare `AuthenticationError` without it. The map, BLUE, the report and ORACLE all work without it |
| `BLACKSTART_SITE` | Optional. Pins the starting campus (`nmcp-portsmouth`, `wrnmmc-bethesda`). The picker in the console switches sites anyway |

Changing a variable after deploying means redeploying — a running deploy does
not pick up the new value on its own.

Do not commit `.env`. It is gitignored, and it should stay that way.

---

## Deploying

1. **Push first.** The GitHub import reads the repo, so anything uncommitted is
   invisible to it — including the `[dependencies]` entries the build needs.
2. **New project → import from GitHub**, pointing at
   `N1tu-Mar/Blackstar`.
3. **Add `ANTHROPIC_API_KEY`** in project settings.
4. **Run Preview.** Confirm the campus map draws and a conductor cut changes
   endurance before going further. A blank map means the app booted but the
   basemap did not load; a dead preview means it did not boot.
5. **Deploy tab → Sandbox → Deploy Sandbox.** Roughly two minutes to a link.

### Sandbox or permanent

| | Sandbox | Permanent |
|---|---|---|
| Lifetime | **Expires after 7 days** | Stays up |
| Free plan | 1, free on every plan | **0 — needs Builder or Pro** |
| Builder / Pro | 5 / 15 | 1 / 3 |

Both get a working JacHammer subdomain, auto-generated from the app name unless
you pick one (lowercase, digits, hyphens). Custom domains are permanent-only.

For a hackathon submission a sandbox deploy is the right call — it is free, it
takes two minutes, and seven days outlasts the judging. Just know the link dies
on day seven, so if this becomes something people are meant to keep opening, it
needs a permanent deploy on a paid plan.

A **preview** is not a deploy: preview sessions are cleaned up after about 30
minutes idle. Do not put a preview link in a submission.

---

## Before you call it deployed

- [ ] The deployed URL loads on a phone, not just the laptop
- [ ] The campus map draws — that is the satellite basemap coming back from the
      API, so a blank map means the walker call failed
- [ ] Cut a conductor, run BLUE, watch endurance move
- [ ] `RunRound` completes — the one path that needs `ANTHROPIC_API_KEY`
- [ ] `Explain` walks a verdict back to its root cause
- [ ] The URL is in the written submission

---

## When it does not work

**Preview boots, then `RunRound` fails with an auth error.** `ANTHROPIC_API_KEY`
is missing or was added after the deploy. Set it, redeploy.

**Import fails on missing modules / `byllm` not found.** The `[dependencies]`
block did not make it into the pushed commit. Check `jac.toml` on GitHub.

**Map blank, everything else fine.** `data/sites/*-satellite.jpg` is missing
from the repo. The API logs `BLACKSTART: no satellite image at ...`.

**Link stopped working after a week.** That is a sandbox deploy expiring on
schedule. Redeploy, or promote it to permanent.
