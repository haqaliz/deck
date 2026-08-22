"""Sanitize the Deck widget snapshots in place for screenshots.

Called by scripts/demo-data.sh, which handles the backup and the agents. Each
snapshot keeps its real shape, timestamps and numbers; only the strings that
identify a person, a company or a machine are replaced. A file that is missing
or unparseable is skipped rather than fabricated, so a widget the user does not
have configured stays empty instead of inventing content for it.
"""

import json
import os
import pathlib

CONTAINER = pathlib.Path(os.environ["CONTAINER"])

EVENTS = [
    "Design review", "Standup", "1:1 with Sam", "Lunch", "Focus block",
    "Sprint planning", "Ship v2.0", "Coffee with Alex", "Retro", "Gym",
]
CALENDARS = ["Work", "Personal"]
TASKS = [
    "Widget gallery previews are blank on first install",
    "Add per-volume disk rows to the large face",
    "Token refresh loses the selected interface",
    "Chart axis labels overlap at 200% scale",
    "Export includes archived items",
    "Reduce agent wake-ups to one per minute",
    "Dark mode contrast on the streak row",
    "Crash when the pasteboard holds an empty string",
    "Localize the relative-day labels",
    "Cache the icon atlas between renders",
    "Handle a 429 from the runs endpoint",
    "Trim the timeline archive on rotate",
    "Document the container repair script",
    "Drop the deprecated settings key",
    "Sign the release DMG",
]
CLIPS = [
    "https://github.com/haqaliz/deck/releases/latest",
    "xcodegen generate --spec native/project.yml",
    "The quick brown fox jumps over the lazy dog",
    "#3fb950",
    "git rebase -i origin/master",
    "SELECT count(*) FROM sessions WHERE created_at > ?",
]
REPOS = ["deck", "atlas", "harbor", "lumen", "pilot", "ridge"]
COMMANDS = ["node", "postgres", "redis-server", "vite", "python3", "docker"]
PROCESSES = [
    "Xcode", "Safari", "kernel_task", "WindowServer", "Terminal", "Music",
    "Finder", "Photos", "Mail", "Docker",
]


def edit(name, fn):
    path = CONTAINER / f"{name}.json"
    if not path.exists():
        return
    try:
        data = json.loads(path.read_text())
    except (json.JSONDecodeError, UnicodeDecodeError):
        print(f"  skip {name}: unreadable")
        return
    fn(data)
    path.write_text(json.dumps(data))
    print(f"  {name}")


def cycle(values, index):
    return values[index % len(values)]


def calbox(d):
    for i, event in enumerate(d.get("events", [])):
        event["title"] = cycle(EVENTS, i)
        event["calendarTitle"] = cycle(CALENDARS, i)


def taskbox(d):
    d["scope"] = "Deck"
    d["sprint"] = "Sprint 12"
    for i, task in enumerate(d.get("tasks", [])):
        task["title"] = cycle(TASKS, i)
        task["url"] = "https://example.com/task"


def clipbox(d):
    for i, item in enumerate(d.get("items", [])):
        if item.get("kind") == "text":
            text = cycle(CLIPS, i)
            item["preview"] = text
            item["content"] = text
            item["detail"] = ""


def gitbox(d):
    for i, repo in enumerate(d.get("repos", [])):
        name = cycle(REPOS, i)
        repo["shortName"] = name
        repo["path"] = f"/Users/you/dev/{name}"


def shipbox(d):
    d["repo"] = "haqaliz/deck"
    for run in d.get("runs", []):
        run["name"] = "Deck"
        run["branch"] = "master"
        run["htmlURL"] = "https://github.com/haqaliz/deck/actions"


def devbox(d):
    for i, port in enumerate(d.get("ports", [])):
        port["command"] = cycle(COMMANDS, i)


def weather(d):
    d["location"] = "San Francisco"
    d["country"] = "United States"


def processes(d):
    for i, proc in enumerate(d.get("processes", [])):
        proc["name"] = cycle(PROCESSES, i)


print("Sanitizing snapshots:")
for name, fn in [
    ("calbox", calbox), ("taskbox", taskbox), ("clipbox", clipbox),
    ("gitbox", gitbox), ("shipbox", shipbox), ("devbox", devbox),
    ("weather", weather), ("processes", processes),
]:
    edit(name, fn)
