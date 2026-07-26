# Demo assets

`blackstart-demo.mp4` — 66 s, recorded from the running app by
`scripts/record_demo.sh`. Nothing is mocked: the script clicks the app's own
buttons and every number on screen came out of the simulator during the take,
including a live disaster round with two model calls, and a switch to a
second site (Walter Reed, Bethesda) at the end.

Re-record with the server running:

```bash
jac start --dev main.jac       # separate shell, ANTHROPIC_API_KEY set
bash scripts/record_demo.sh
```

The recorder drives the UI rather than POSTing to the API on purpose. A direct
POST leaves the page showing stale numbers, because the client caches reader
responses for 60 s — an early take had captions describing steps that never
ran.
