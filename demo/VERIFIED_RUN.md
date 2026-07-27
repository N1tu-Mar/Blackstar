# A verified live run

`jac run scripts/redloop.jac`, two rounds, four model calls against
`claude-sonnet-5`. Nothing below is edited except for length — no strike, number,
or lesson was chosen by a human.

Read it for one thing: **round 2's opening move is the instruction round 1's
lesson wrote.** There is no variable in this system that holds that.

---

## Round 1 — "Tidewater Surge"

RED named the scenario itself and committed a forecast of **48 hours** before
anything ran.

Two strikes, both `flood`:

| # | Target | Mechanism | Immediate damage |
|---|---|---|---|
| 1 | Elizabeth River Substation | flood | `none` |
| 2 | Effingham Street Substation | flood | `severe` |

The first landed. **The second was refused by the plausibility gate:**

> `flood on Effingham Street Substation: Effingham Street Substation sits at 8.4 m,`
> `above the 2.4 m surge stage measured today`

That 2.4 m is not a constant. It is the worst-credible storm tide for the
Elizabeth River — the 1933 Chesapeake–Potomac crest, 8.02 ft MLLW — read from
`data/live/nmcp-portsmouth-conditions.json`, which was fetched from the NWS gauge
1.5 miles from the hospital. **Real river data refused the model's plan.**

Outcome: `999.0 h → 999.0 h`, one island, nothing shed. A complete no-op, and the
forecast was off by 951 hours.

Then REFLECT, unprompted:

> "the two incoming utility feeds are **NOT symmetrically exposed** to storm surge
> — Effingham Street Substation is elevated (8.4 m) and effectively immune to the
> surge stages this hazard produces, making it a de facto flood-proof backup feed
> … **Next time, take out Effingham Street Substation first via a non-flood
> mechanism** … since it is the actual single point of resilience, not a
> co-vulnerable twin."

Confidence 0.85.

## Round 2 — "Tidewater Blackout"

RED did exactly what it told itself to do. Note the mechanism on strike 1 — it
changed from `flood` to `wind`, which is the specific correction the lesson asked
for.

| # | Target | Mechanism | Immediate damage |
|---|---|---|---|
| 1 | Effingham Street Substation | **wind** | `none` |
| 2 | Central Energy Plant Bus | equipment_failure | `severe` |
| 3 | North Campus Switchgear | cyber_switching | `partial` |

Strike budget escalated 2 → 3 as the adversary learned. Strike 1 is labelled
`none` — a setup strike that does no damage on its own and strips the redundancy
the rest of the chain needs.

Outcome:

```
endurance 999.0 h -> 0.0 h    islands = 3    tier1_stranded = True    breach = True
dark: Emergency Department, Network Core and Telemetry, Radiology and MRI,
      Inpatient Pharmacy, Clinical Laboratory, Sterile Processing
BLUE shed: Inpatient Tower Floor 5
```

Three islands formed, and the split is the interesting part: ICU, Surgical Suite
and Neonatal ICU survived together on the Charette generator at **41.4 h**, while
the Emergency Department and Network Core were stranded with no path to
generation at all. Fire Pump House ended up on a different island entirely, at
147 h, alongside the galley and the parking deck.

That is a real breach, and it falls out of arithmetic. Nobody scripted it.

RED forecast 18 hours and the site reached 0.0 — a 18-hour error, down from 951.

Its second lesson is a correction to its own theory of the plant:

> "The facility is **not** a single fault-tolerant network with CEP Bus as the sole
> shared standby SPOF — it's actually a set of 3 semi-independent islands whose
> interconnection is fragile enough that a 3-strike combo fractures the whole site
> rather than degrading it gracefully … Next time, take out the North Campus
> Switchgear transfer/cyber logic **FIRST**."

Confidence dropped to 0.6, which is the right direction after being surprised.

## "Why did that load go dark?"

Six cited lines, walked backward from the decision to the events that caused it:

```
[d30f0] t=2  shed Inpatient Tower Floor 5 - rule: tier 2 load, island endurance 9.0 h below 96 h target
[f673f] island 3 endurance 9.0 h against a 96 h target
[e50c3] t=1  flood: Elizabeth River Substation - damaged by flood
[e91df] t=2  wind: Effingham Street Substation - damaged by wind
[eef74] t=2  equipment_failure: Central Energy Plant Bus - damaged by equipment_failure
[e1ef7] t=2  cyber_switching: North Campus Switchgear - unauthorized switching opened 5 breakers
```

Every bracketed id is a node in the run graph. This is the three weeks of SCADA
archaeology, answered from the archive.

---

## What this run establishes

1. **Memory changes behaviour, provably.** Round 2's mechanism switch from `flood`
   to `wind` on the same target is the literal content of round 1's lesson. The
   move is not in the code.
2. **The live data is load-bearing, not decoration.** It rejected a strike, and
   that rejection is what produced the lesson that produced round 2.
3. **The plausibility gate is real.** RED does not get to flood a hilltop.
4. **Calibration works.** 951 h error → 18 h error across one round, from a view
   with the conductors and island membership stripped out.
5. **Setup strikes are named.** `immediate_damage: none` on the move that mattered.
6. **BLUE stayed dumb and honest.** One tier-2 shed, then `breach = True` rather
   than touch tier 1.

Reproduce with `set -a && . ./.env && set +a` then
`jac run scripts/redloop.jac`. Roughly 90 seconds and four model calls.
