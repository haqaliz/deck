# DevBox — PRD

## Ask

DevBox shows what's running on the machine in a deck widget: **open TCP
listening ports** (process + port) and **Docker containers** (name, image,
status, CPU/mem). Slug: `devbox`.

Source: `deck-next` handoff → `docs/planning/_card/issue.md` (ROADMAP.md:45).

## User-visible spec

### Front face (widget, snapshot-rendered)

No chart — a list card (ports/containers are snapshots, not history).

1. **Small** — two metric rows (GitBox small pattern):
   - `PORTS` — count of listening TCP ports (deduped).
   - `CONTAINERS` — count of running Docker containers.
2. **Medium** — header rows + **PORTS** section: list of `process · port`
   rows (top N, sorted by port ascending), dot color = settings.
3. **Large** — header rows + **PORTS** list + **CONTAINERS** section: rows of
   container name (line-limited), image short name, `CPU% / MEM%`, status dot
   (green running / red restarting-exited / gray paused).
4. **Docker degrade states** (section-level, not card-level):
   - daemon unreachable or CLI missing → `Docker unavailable` line;
   - daemon up, zero containers → `No containers` line;
   - normal → the container rows. The PORTS section always renders.
5. **Empty ports** — zero listening sockets (never happens in practice on
   macOS, but defined): PORTS section shows one `No listening ports` line
   (GitBox empty-repos line pattern) instead of vanishing.
6. **Empty/stale card state** — no snapshot or `writtenAt` older than 300s →
   the GitBox unavailable card (`DevBox`, "No port data", "Check Deck agent.").

### Back face (settings — Deck app tab, not in widget)

- **PORTS** section: Show ports toggle (default on); port count stepper 1–10
  (default 5); port color picker.
- **CONTAINERS** section: Show containers toggle (default on); container count
  stepper 1–10 (default 5); container color picker (list accent).
- No refresh control — the 60s agent cadence is a shell invariant (CLAUDE.md).

## Data source

All three commands are subprocesses — **sandbox-blocked in the widget**, so
sampling runs only in the unsandboxed host/agent (the `ProcessSnapshot` /
`HostGitBoxSampler` pattern):

1. **Ports**: `lsof -nP -F -iTCP -sTCP:LISTEN`. Field-mode output parses
   robustly (`p<pid>`, `c<command>`, `n<host>:<port>` tokens; whitespace in
   names is irrelevant). Dedupe by `(command, name)` (IPv4+IPv6 rows collapse),
   sort by numeric port ascending. `HostDevBoxSampler` exits quietly (empty
   list) on any failure.
2. **Containers (identity)**: `docker ps --format '{{.Names}}|{{.Image}}|{{.Status}}'`.
3. **Containers (usage)**: `docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}'`
   — one line per running container; a stats row missing for a name → `nil`
   cpu/mem, rendered as `—`.
4. **Docker availability** derived from command exit/output: exit 0 + non-empty
   lines → normal; exit 0 + empty → `noContainers`; non-zero/CLI missing →
   `unavailable`. Verified on this machine: 0 containers → empty output,
   exit 0 (parses cleanly).
5. **ps/stats join rule**: `docker ps` is the identity source; a container
   present in ps but missing from stats (start/stop race between the two
   calls) → `nil` cpu/mem, rendered `—`. A stats-only name (stopped before
   ps read it) → dropped, never synthesized.
6. **Parsing defensiveness**: `{{.CPUPerc}}`/`{{.MemPerc}}` print like
   `0.05%`/`2.31%` — strip the `%` and parse with `Double(...)`; any garbage
   or missing segment → `nil` (rendered `—`), never a crash. `{{.Names}}`
   may be comma-joined (swarm) — take the first name.
5. **Snapshot**: `DevBoxSnapshot` (Codable, Equatable) — `writtenAt`, `ports`,
   `containers`, `dockerState`. Store at `containerDirectory/devbox.json`.
   Written by `DeckAgent` (60s) and mirrored by the Deck app refresh timer,
   exactly like `GitBoxSnapshotStore` wiring (`DeckAgent/main.swift:29`).

## Shell fit

- Copy `DeckWidgets/GitBoxWidget.swift` → `DeckWidgets/DevBoxWidget.swift`;
  register in `DeckWidgets/DeckWidgets.swift`.
- `DevBoxSettings` in `Shared/DeckSettings.swift`; new `.devbox` case + tab
  view in `DeckApp/DeckApp.swift` (sidebar enum + `GitBoxSettingsView` copy).
- `Shared/DevBoxSnapshot.swift` (snapshot + store + `HostDevBoxSampler` with
  pure parsers `LsofParser` / `DockerParser`); wire into `DeckAgent/main.swift`
  and the Deck app timer.
- **No panel invariant is touched** (widget renders a snapshot only; no
  window/panel changes at all — WidgetKit, like GitBox).
- **No new settings control types** (toggles, steppers, color pickers all
  exist in the shell).
- **TDD**: pure parsers developed in a scratch SwiftPM package
  (`Sources/DevBoxCore` + `Tests/DevBoxCoreTests`, `swift test`) — the
  BatBox/GitBox precedent (ROADMAP M4 "XCTest target" stays a separate item);
  parsers are then ported into `native/Shared/DevBoxSnapshot.swift` and the
  scratch package removed before merge.

## Non-goals

- No UDP/ESTABLISHED sockets, no PID drill-down, no system-daemon filtering
  (v1), no port history/chart.
- No Docker actions (start/stop), no stopped containers, no image sizes, no
  compose stacks, no daemon stats beyond per-container CPU/mem.
- No changes to the agent cadence, settings persistence, or container path.

## Decisions (resolved in interview)

- Ports: TCP LISTEN only; dedup by command+name; sorted by port ascending.
- System processes (rapportd, ControlCenter…) shown unfiltered in v1 — top-N
  cap limits noise; a hide toggle is a fuzzy heuristic, deferred.
- Containers: `docker ps` (name/image/status) + `docker stats` (CPU/mem%).
- No chart; list card only.
- Tests via scratch SwiftPM package, ported into `Shared/` pre-merge.
