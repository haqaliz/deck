# Self-critique — `agent-heartbeat` PRD

Pressure-tested 2026-08-30 against the code, the plists and the traps in
CLAUDE.md. Two 🔴, four 🟡. Both reds are false-positive paths — which is the
only failure mode that matters for a feature whose whole product is being
believed.

---

## 🔴 C1 — Writing the heartbeat at the *end* of the tick invents a false positive

**PRD §5** says the heartbeat is written "at the end of the full-refresh path"
and witnesses that the agent "ran to completion".

That is the wrong end of the function. The full path awaits ~10 sources, most of
them **serially**, each with a 10s `URLSession` timeout — MarketBox alone is four
providers in a row, PRBox is two, and CLAUDE.md records the general rule ("every
other loader awaits serially and gets away with it only because it has fewer
sources"). A first opencode remote resync pages one request *per session*.
launchd will not start a second instance while one is running, so a genuinely
alive agent having a slow tick can leave the heartbeat untouched well past the
240s limit and be reported dead.

**The fix costs nothing and is strictly better: write it at the *start* of the
full path, before any work.** It still catches every fault this feature exists
for:

| Fault | Start-write catches it? |
|---|---|
| Job never bootstrapped (`Could not find service`) | ✅ no code runs at all |
| `EX_CONFIG` / spawn failed (the 13,741-run case) | ✅ no code runs at all |
| Agent hangs mid-tick forever | ✅ launchd starts no new tick, so the stamp stops advancing |
| Slow-but-healthy tick | ✅ **no longer a false positive** |

So the end-write's only advantage over the start-write is imaginary. Change §5's
claim to what it actually witnesses: **the 60s agent was launched and started
work** — not that it finished.

---

## 🔴 C2 — Every upgrading user is told their widget data has stopped

The new witness is absent on the release that introduces it, and the grace clock
does not restart for an upgrade.

Trace it: a v1.36 install has `agentsRegisteredAt` days old and both agents
`.enabled`. `AgentRegistrationClock.stamp` writes only when `didRegister` or
when `stored == nil` — neither holds, so the clock stays old. The user installs
this release and opens Deck. The data witness is `.never`, the registration is
older than 240s, and the ladder returns `.down`: **"Widget data has stopped
refreshing"**, on a machine where nothing is wrong.

This is the same bug class the last cycle legislated against, one file over —
CLAUDE.md: *"a grace-period stamp guarded on `== nil` silently defeats the rename
case … the notice firing falsely on the exact release it exists to protect."* It
self-clears once the agent's next tick lands (≤60s, and `evaluateLiveness()` runs
on a 60s timer at `DeckApp.swift:219`), so it is a transient lie rather than a
permanent one — but it lands at the exact moment a user opens Deck to see what
changed, and it is the first thing this feature ever says to them.

**Fix — a third trigger on `AgentRegistrationClock`:** restamp when the
**heartbeat is absent while the process witness is healthy**. A live fast agent
with no heartbeat at all means either this feature just shipped or the 60s agent
alone has never run once; both deserve one grace window rather than an instant
accusation, and after 240s the accusation is made correctly. Conditioning on the
*process* witness being healthy is what keeps this from weakening the existing
check — it can never silence a real both-agents-down fault, because that case has
no healthy witness. Pure, and a two-line addition to a policy that is already
table-tested.

---

## 🟡 C3 — `240` hard-codes a cadence that lives in a plist

D2's constant is 4 × 60s, but the 60s is `StartInterval` in
`DeckApp/LaunchAgents/com.deck.agent.plist` — a file Swift never reads. Someone
retuning the agent to 300s leaves a threshold that fires on every healthy tick,
and nothing fails.

**Fix:** name the cadence (`AgentLivenessPolicy.dataAgentInterval = 60`), derive
the threshold from it, and pin it against the plist with the `#filePath`
source-tree idiom `DeckBundleTests` already uses for `project.yml`. Drift then
fails the suite, which is the standard this repo already holds its ids to.

---

## 🟡 C4 — "the more recent of the two" is undefined when neither is a date

PRD §4 says a both-down notice reports the more recent evidence. With three
evidence shapes there are pairs where "more recent" means nothing:
`.never` + `.unreadable`, or `.never` + `.never`.

**Fix:** state the total order — a timestamp beats both non-dates;
`.unreadable` beats `.never` (something wrote it, so "no refresh has been
recorded" would be the false claim D3 exists to remove); `.never` + `.never` is
"No refresh has been recorded."

---

## 🟡 C5 — The single-writer test is a string match, and §7 oversells it

§7 calls the invariant "pinned by a test". It is pinned by a **substring search
for `AgentHeartbeatStore.save` in one file**. A wrapper function, a renamed
store, or a write from a target the test does not read (the widget extension —
sandboxed and writing nothing today, but not covered) all slip past it.

**Fix:** keep the test — it catches the realistic regression, which is somebody
adding a heartbeat write to a host refresh path by copy-paste — and scan *both*
non-agent targets rather than only `DeckApp.swift`. Then say plainly in the
comment what it does not cover, rather than letting a future reader trust it as
proof.

---

## 🟡 C6 — Restart agents hides both notices for a window, and now one may return alone

`registerAgents()` restarts the grace clock, so pressing **Restart agents**
silences the notice for one grace window — documented as intended. With scoped
wording that gets a new wrinkle: press it, and the notice can come back **naming
a different scope** than before (both → data-only, if the fast agent recovers and
the 60s one does not). That is honest and arguably the point, but it will read as
the notice changing its mind.

**Fix:** none needed in code. Worth one line in the plan's verification so the
behaviour is recognised as designed when it shows up in the live check.

---

## What holds up

- **The file-not-a-settings-field decision (§5).** Verified in
  `ContainerMigration.swift:66` — only `settings.json` is copied. A field would
  have carried a stale stamp across the rename; the file cannot.
- **Unconditional writing regardless of fetch outcomes.** Correct, and the
  separation from `FetchStatusStore` is the right seam.
- **The two global guards staying structural.** Keeping `intent` and
  `state != .enabled` ahead of any witness read is what stops a Login Items veto
  from raising a second, wrongly-diagnosed notice.
- **`eraseDeckData` needs no change** — it sweeps the container directory
  (`DeckApp.swift:707-713`).
- **`evaluateLiveness()` already runs on a 60s timer** while the window is open
  (`DeckApp.swift:219`), so a scoped notice appears and clears under the user's
  eyes without a relaunch. No change needed; the PRD simply never checked.
