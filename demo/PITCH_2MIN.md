# The two-minute pitch

## Before you walk up

1. Server running, browser on the console, **Portsmouth** selected.
2. Click **Reset**.
3. Click **Simulate a disaster** once and let it finish. *This is the important
   one.* Round 1 is often undramatic, and it takes ~40 s. Burning it offstage
   means your live click is **round 2** — the round where memory pays off and the
   site dies.
4. Click **Reset** again. The lesson survives the reset; the damage does not.
5. Second tab open on `demo/VERIFIED_RUN.md` in case the network dies.

Total spoken words below: ~300. That is 2 minutes at a normal pace with the
clicking. Do not rush the numbers — they are the whole argument.

---

## 0:00 — Problem (20s, nothing clicked yet)

> "A hospital loses power. It has generators, but not enough for everything, so
> something has to be switched off.
>
> Who decides? A priority list an engineer wrote when the building opened. It has
> never been revised.
>
> And afterwards, when someone asks why the third floor went dark at 2 AM —
> nobody can answer. Three weeks of SCADA logs and an educated guess."

## 0:20 — Solution, live (35s)

**Click: Cut one power line**

> "This is Naval Medical Center Portsmouth. Real campus, real satellite imagery,
> 27 elements. I've cut one utility feeder — nothing goes dark, the second one
> carries it."

**Click: Cut all grid power**

> "Both feeders gone. Watch: the map fractures into three separately powered
> sections, and endurance drops to **76.1 hours** against a 96-hour requirement.
> Nothing has been shed yet and the hospital is already non-compliant.
>
> We never wrote a splitting algorithm. In Jac a walker can't cross a dead cable,
> so the islanding just happens."

**Click: Protect critical care**

> "The controller sheds five loads — galley, outpatient, admin, parking, then
> imaging — 770 kilowatts of 2,590. Endurance clears at **108.3 hours** and it
> never touched an ICU. That's a sorted list and a while loop, deliberately.
> Nobody accredits a language model to de-energize an operating room."

**Type `Galley and Food Service`, click Explain**

> "And you can ask why. Every line cites the node it came from, back to the
> breaker that started it."

## 0:55 — Click "Simulate a disaster", then talk while it runs (35s)

**Click it now.** It takes ~40 s. Fill the time:

> "That's the defense. Here's where the AI is — one place: deciding what breaks
> next.
>
> Real failures come in chains. Flood hits the low substation, the road floods,
> the fuel truck can't get through, and the generator that was fine runs dry. Our
> graph knows cables and kilowatts. It does not know that floods go downhill or
> that trucks need roads. That's world knowledge, and it's in no electrical
> dataset.
>
> Two model calls a round: plan the attack, then write down what it learned. Both
> are functions with a signature and no body — there is no prompt anywhere in
> this repo.
>
> And it's grounded. The flood check runs against the river gauge a mile and a
> half from the hospital, read this morning. Last run it **refused** the model's
> own plan — told it the second substation sits at 8.4 metres, above today's
> 2.4-metre surge stage."

## 1:30 — The payoff (20s)

Round 2 lands. Point at the round feed.

> "There it is. Round one it tried to flood both substations and got refused.
> It wrote down that one of them is elevated and to use a different mechanism
> next time. **Round two it came back with wind instead of flood, on the same
> target.**
>
> That move is not in our code. It read what happened last round.
>
> Site goes to zero. Three islands, the ICU stranded on 41 hours, the emergency
> department with no path to power at all."

## 1:50 — Market and close (15s)

> "Every hospital and every military base is legally required to report how long
> it survives without power and what it would shut off. Today that's a human in
> the logs for three weeks.
>
> Gridware tells you the pole broke. Squid helps you plan what to build. Neither
> tells a hospital which wing to keep alive at 2 AM, or explains it afterward.
>
> Same code runs a shipyard — tier one becomes dry dock pumps. New site is one
> JSON file."

---

## If you get 30 more seconds

**Click: What we never tested** — "The wargame only finds what the adversary
thought to try. We swept all 119 plausible strikes: four switchboards each strand
critical care on a *single* hit. None of them were ever attacked."

**Click: File the legal report** — "And this is the artifact. The §2925 filing,
generated from the decision record, every line citing an archive node."

---

## Questions you will get

**"Why do you need an LLM? A loop picks a cable."**
> "For picking a cable we don't — a loop is better, and we built that loop to
> prove it. It searches all 119 strikes with the full diagram and unlimited
> retries. What it can't do is say *why*. It emits `flood:X, fuel:Y` and nothing
> else. You can't brief that to a commander or file it."

**"Isn't the defense just a priority list?"**
> "Yes, and it should be. That part is solved. What isn't solved is knowing what
> to plan for, and being able to explain what happened."

**"Does the memory actually help?"**
> "Measured it three rounds, twice. Remembering, it stranded critical care a full
> round earlier and held the site 44 hours lower."

**"Is this real data?"**
> "Campus size and the energy plant designation are from the DoD Base Structure
> Report and federal contract awards — the plant is Building 20, 'CEP20'. The
> topology follows UFC 4-510-01, which mandates the two separated feeders and the
> normally-open ties. River stage is live NOAA. The conductor list and the
> ratings are engineering estimates, because as-built drawings for a military
> hospital aren't public — that's all written down in `data/SOURCES.md`."

---

## Numbers, all reproducible

| | |
|---|---|
| Both feeders lost | 76.1 h vs a 96 h requirement |
| After curtailment | 108.3 h, 770 kW of 2,590 kW shed |
| Live round 2 | 999 h → 0.0 h, 3 islands, tier 1 stranded |
| ICU island | 41.4 h |
| Memory A/B | held 100.6 h vs 144.6 h; first kill round 2 vs round 3 |
| Single-strike kills found | 4 switchboards, none ever attacked |
| Jac share of codebase | 87% |
