# deferred-parser-tests — understanding note

Slug confirmed: `deferred-parser-tests` (descriptive; branch carries the type).

## What this work really is

Finish the M4 tests milestone by covering the four slices recorded as deferred
in ROADMAP.md:57-62 and shared-parser-tests/prd.md:81-89. All four are pure
parser/formatter logic with no shell, settings, agent-cadence, or UI change.
Precedent: shared-parser-tests (commit c09137b) — `DeckSharedTests` target
compiles `Shared/` + `SharedTests/` (native/project.yml:93-110), pure logic
extracted into Shared files, verified by
`xcodegen generate && xcodebuild test -scheme DeckSharedTests`.

## Slice map (code is authoritative)

1. **DevBox parsers** — `native/Shared/DevBoxSnapshot.swift`: `LsofParser.parse`
   (field-mode `lsof -nP -F` output; dedups by `command|name`; sorts by port),
   `DockerParser.parseContainers` (joins `docker ps` identity rows with `docker
   stats` usage rows by name; stats-only names dropped; ps rows missing from
   stats keep nil percents), `DockerParser.parsePercent` ("0.05%" → 0.05,
   garbage → nil), `Formatters.portLabel` / `Formatters.percentString`.
   **Already internal — zero code moves, tests only.**

2. **RemoteOpenCodeLoader aggregation** — `native/Shared/RemoteOpenCodeLoader.swift`.
   Two `private static aggregate(...)` overloads over `private` types
   (`RemoteSession`, `RemoteMessage`). Logic: session window 14d, message
   window 13d, `role == "assistant"` filter, active-session membership check,
   modelKey composition (`provider/model`, `local/unknown` fallbacks), UTC day
   bucketing, today windows, `round4`, top-3 models by cost, `costDaily`
   row order (day asc, cost desc within day). Consumer: `DeckAgent/main.swift`.
   **Extraction needed:** make the aggregators + their input types internal
   (e.g. `enum RemoteOpenCodeAggregator`) so tests can drive them with fixed
   fixtures; behavior byte-identical. Precedent: OpenBoxCore extraction.

3. **ProcessSnapshot ps parsing** — `native/Shared/ProcessSnapshot.swift`.
   Parsing is inline in `HostProcessSampler.top(limit:)` over `ps -Aceo
   comm=,%cpu=,%mem=` output; sort desc by cpu, prefix(limit).
   **Extraction needed:** pure `PsParser.parse(_ raw: String) -> [TopProcess]`
   in Shared; sampler calls it.
   **Latent bug to decide on:** `comm=` is a full path and may contain spaces;
   the current `split(whereSeparator: == " ")` + `parts[0]` reads paths with
   spaces wrong (cpu/mem columns shift). %cpu/%mem are always the last two
   whitespace tokens, so a right-anchored parse is the correct one.

4. **BatteryMetrics formatters** — `native/DeckWidgets/Loaders/BatteryMetrics.swift`
   (widget target — not compilable into the test bundle). `BatteryFormatters`
   (`formatPercent`, `formatTime` — "6h 34m"/"45m"/"—", `formatState` —
   AC Power/Full/Charging/Discharging) plus private pure helpers
   `percent(current:max:)` (clamped 0...100) and `timeMinutes(seconds:)`
   (>0 guard, rounded).
   **Move needed.** Two precedents: NetBoxCore moved the whole loader to
   Shared; LiveBoxDiskCore moved only the pure core and left the loader in
   DeckWidgets feeding it. BatteryMetrics imports `IOKit.ps` — moving the whole
   loader would put IOKit into the app/agent/test links; pure-core extraction
   (`Shared/BatteryCore.swift`) is the lower-risk precedent.

## Out of scope (brief + ROADMAP)

- SystemMetrics per-core math (`perCoreUsagePercents`,
  `native/DeckWidgets/Loaders/SystemMetrics.swift:77`) — needs the math moved
  to Shared, which touches the LiveBox widget file; recorded follow-on.
- Any widget/settings/agent behavior change (shared-parser-tests/prd.md:93).
- SwiftUI/WidgetKit timeline tests (never done; build + gallery re-add verify UI).

## Ambiguities / open questions

1. ps path-with-spaces: preserve current (buggy) parse or fix to right-anchored
   parse in the same slice? (Recommend: fix — it is the semantics `ps` actually
   produces; tests should pin the correct behavior.)
2. BatteryMetrics: whole-loader move (NetBoxCore precedent) vs pure-core
   extraction (LiveBoxDiskCore precedent)? (Recommend: pure core.)
3. RemoteOpenCodeLoader: confirm extraction shape — internal aggregator enum +
   internal fixtures types, `load()` unchanged.
4. Add snapshot decode round-trips (DevBoxSnapshot, ProcessSnapshot) while in
   the file? Cheap; only if it doesn't overlap DecodeTests.
5. `DockerParser.parseContainers` returns `.noContainers` for empty ps output
   while `HostDevBoxSampler.snapshot()` computes the state separately — test
   both surfaces as currently written.

## No panel/shell invariants touched

Card, flip, settings window, agent cadence, refresh floor — all unchanged.
