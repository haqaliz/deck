// Throwaway-but-committed probe for the spotlight-shell lifecycle checks.
// Not product code, not part of any target — compile and run by hand:
//
//   swiftc -O docs/planning/spotlight-shell-checks/probe/main.swift -o /tmp/deck-probe
//   /tmp/deck-probe --selftest          # prove raw CGEvent posting works first
//   /tmp/deck-probe --url-cold
//   /tmp/deck-probe --url-running
//   /tmp/deck-probe --agents [--wait 90]
//   /tmp/deck-probe --panel-probe [--shortcut "49,2048"]
//   /tmp/deck-probe --post-hotkey
//
// It POSTS key events (never registers a hotkey — a second process registering
// Deck's combination gets status 0, and it must not fight Deck's own). The first
// thing to trust is --selftest: a helper that failed to deliver made a working
// panel look dead once already (CLAUDE.md).
import AppKit
import Foundation
import CoreGraphics
import Carbon.HIToolbox

// MARK: - constants / plumbing

let deckBundleID = "com.deck.app"          // update if the bundle id is renamed
let deckAppPath = "/Applications/Deck.app"
let container = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Containers/com.deck.app.widgets/Data/Library/Application Support/Deck")
let urlUnderTest = "https://example.com/deck-url-check"

func out(_ s: String) { FileHandle.standardOutput.write((s + "\n").data(using: .utf8)!) }
func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

var args = Array(CommandLine.arguments.dropFirst())
func argValue(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func has(_ name: String) -> Bool { args.contains(name) }

func deckPIDs() -> [pid_t] {
    NSRunningApplication.runningApplications(withBundleIdentifier: deckBundleID).map(\.processIdentifier)
}
func deckRunning() -> Bool { !deckPIDs().isEmpty }

@discardableResult
func shell(_ path: String, _ argv: [String]) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = argv
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "spawn failed: \(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

/// Raw key chord into the HID event stream (the only thing that reaches a
/// non-activating panel; `System Events keystroke` activates the target).
func postKeys(_ keyCode: CGKeyCode, flags: CGEventFlags, hold: TimeInterval = 0.02) {
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: hold)
    let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
}

/// Deck's on-screen windows, from outside the process. The harness cannot read
/// `NSApp.windows`, so it uses the window server.
func deckWindows() -> [(layer: Int, bounds: CGRect, name: String)] {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    let pids = Set(deckPIDs())
    return info.compactMap { d in
        guard let pid = (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              pids.contains(pid) else { return nil }
        let layer = (d[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let name = (d[kCGWindowName as String] as? String) ?? ""
        var rect = CGRect.zero
        if let bd = d[kCGWindowBounds as String] as? NSDictionary {
            rect = CGRect(dictionaryRepresentation: bd as CFDictionary) ?? .zero
        }
        return (layer, rect, name)
    }
}

/// Deck's diagnostic log line for URL delivery (Phase 1 of the plan). Headless
/// `log show` needs `--info --debug` or this app logs nothing.
func recentURLLog(seconds: Int = 30) -> [String] {
    let pred = #"subsystem == "com.deck.app" AND category == "url""#
    let r = shell("/usr/bin/log", ["show", "--last", "\(seconds)s", "--info", "--debug",
                                   "--predicate", pred, "--style", "compact"])
    return r.output.split(separator: "\n").map(String.init).filter { $0.contains("open:") }
}

func nsec(_ url: URL) -> String {
    // `URLResourceValues.contentModificationDate` is cached for the life of the
    // process, so polling the same URL returns a stale mtime and the check reads
    // frozen files that are actually advancing. Read the attributes directly.
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let d = attrs[.modificationDate] as? Date else { return "never" }
    return ISO8601DateFormatter().string(from: d)
}

// MARK: - modes

func runSelftest() {
    // A known-good receiver: a *normal* key window with a focused field. The
    // positive control only has to prove that a posted CGEvent reaches a first
    // responder at all; whether a non-activating panel can also be key is what
    // --panel-probe is for. (The first helper in the shell's own probe activated
    // itself and made a working panel look dead, so prove the mechanism first.)
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 80),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let field = NSTextField(frame: NSRect(x: 10, y: 20, width: 380, height: 40))
    field.isEditable = true
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    window.contentView?.addSubview(field)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(field)
    app.activate(ignoringOtherApps: true)

    out("AXIsProcessTrusted: \(AXIsProcessTrusted())")
    out("window visible: \(window.isVisible), key: \(window.isKeyWindow)")

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        out("posting 'a' now; key before post: \(window.isKeyWindow)")
        // kVK_ANSI_A == 0; no flags.
        postKeys(0, flags: [])
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        let got = field.stringValue
        let passed = got.lowercased().contains("a")
        out("selftest: field=\(got.isEmpty ? "<empty>" : got) -> \(passed ? "PASS (raw CGEvent reached the key field)" : "FAIL (events not delivered — check AX trust / activation)")")
        exit(passed ? 0 : 1)
    }
    app.run()
}

func postHotkey(shortcut: CGKeyCode, flags: CGEventFlags) {
    out("posting hotkey keyCode=\(shortcut) flags=\(flags.rawValue)")
    postKeys(shortcut, flags: flags)
}

func runURLCold() {
    if deckRunning() {
        err("--url-cold: Deck is already running; quit it first (pgrep -lf 'MacOS/Deck$').")
        exit(2)
    }
    out("cold: Deck not running. launching via open -a with a URL…")
    let before = recentURLLog(seconds: 20).count
    shell("/usr/bin/open", ["-a", deckAppPath, urlUnderTest])

    // Watch it appear, then leave. Deck quits almost immediately after
    // forwarding, so sample fast; the log line (not the process sample) is the
    // real proof the callback fired.
    var appeared = false
    var exited = false
    var maxWindows = 0
    for _ in 0..<160 { // ~8s at 50ms
        Thread.sleep(forTimeInterval: 0.05)
        if deckRunning() {
            appeared = true
            maxWindows = max(maxWindows, deckWindows().count)
        } else if appeared {
            exited = true
            break
        }
    }
    let goneNow = !deckRunning()
    let logs = recentURLLog(seconds: 30)
    let forwarded = logs.count > before && logs.contains { $0.contains("forwarding=1") }
    out("cold: appeared=\(appeared) exited=\(exited) goneNow=\(goneNow) maxOnScreenWindows=\(maxWindows) webLog=\(forwarded)")
    for l in logs.suffix(3) { out("  log: \(l)") }
    let pass = forwarded && goneNow && maxWindows == 0
    out("cold: \(pass ? "PASS" : "FAIL") (expect forwarded, exited, 0 windows)")
    exit(pass ? 0 : 1)
}

func runURLRunning() {
    if !deckRunning() {
        out("running: Deck not up; launching normally…")
        shell("/usr/bin/open", ["-a", deckAppPath])
        for _ in 0..<20 { Thread.sleep(forTimeInterval: 0.3); if deckRunning() { break } }
    }
    guard deckRunning() else { err("running: could not start Deck"); exit(2) }
    let before = recentURLLog(seconds: 20).count
    let winBefore = deckWindows().count
    out("running: Deck up, on-screen windows=\(winBefore). opening URL…")
    shell("/usr/bin/open", ["-a", deckAppPath, urlUnderTest])
    Thread.sleep(forTimeInterval: 2.5)
    let stillUp = deckRunning()
    let winAfter = deckWindows().count
    let logs = recentURLLog(seconds: 30)
    let fired = logs.count > before && logs.contains { $0.contains("forwarding=1") }
    out("running: stillUp=\(stillUp) windowsBefore=\(winBefore) windowsAfter=\(winAfter) webLog=\(fired)")
    for l in logs.suffix(3) { out("  log: \(l)") }
    let pass = stillUp && winAfter == winBefore && fired
    out("running: \(pass ? "PASS" : "FAIL") (expect forwarded, process persists, no new window)")
    exit(pass ? 0 : 1)
}

func runAgents(wait: Int) {
    let processes = container.appendingPathComponent("processes.json")
    let heartbeat = container.appendingPathComponent("agent-heartbeat.json")
    out("agents: container=\(container.path)")
    let beforeP = nsec(processes)
    let beforeH = nsec(heartbeat)
    out("agents: baseline processes.json=\(beforeP)  agent-heartbeat.json=\(beforeH)")
    if !deckRunning() {
        out("agents: starting Deck…")
        shell("/usr/bin/open", ["-a", deckAppPath])
        for _ in 0..<20 { Thread.sleep(forTimeInterval: 0.3); if deckRunning() { break } }
    }
    // Relaunch: kill then start again (a graceful quit is vetoed when tray-only
    // is on, so SIGTERM is the only way to force a real relaunch). A launch must
    // NOT boot the agents out.
    out("agents: kill + relaunch Deck…")
    shell("/usr/bin/pkill", ["-f", "MacOS/Deck$"])
    Thread.sleep(forTimeInterval: 2)
    shell("/usr/bin/open", ["-a", deckAppPath])
    out("agents: sampling for \(wait)s (fast agent writes processes.json every ~15s)…")
    var advancedP = false
    var advancedH = false
    var elapsed = 0
    while elapsed < wait {
        Thread.sleep(forTimeInterval: 15)
        elapsed += 15
        let p = nsec(processes), h = nsec(heartbeat)
        if p != beforeP { advancedP = true }
        if h != beforeH { advancedH = true }
        out("  t+\(elapsed)s: processes=\(p)\(p != beforeP ? "  <= advanced" : "")  heartbeat=\(h)\(h != beforeH ? "  <= advanced" : "")")
        if advancedP && advancedH { break }
    }
    out("agents: processes.json advanced=\(advancedP)  agent-heartbeat.json advanced=\(advancedH)")
    out("agents: \(advancedP ? "PASS" : "FAIL") (processes.json must advance across a launch)")
    exit(advancedP ? 0 : 1)
}

func runPanelProbe(shortcut: CGKeyCode, flags: CGEventFlags) {
    guard deckRunning() else { err("panel-probe: Deck must be running"); exit(2) }
    let before = Set(deckWindows().map { "\($0.layer):\(Int($0.bounds.width))x\(Int($0.bounds.height))" })
    out("panel-probe: Deck windows before=\(before.sorted())")
    out("panel-probe: frontmost before=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")
    postHotkey(shortcut: shortcut, flags: flags)
    Thread.sleep(forTimeInterval: 1.2)
    let after = Set(deckWindows().map { "\($0.layer):\(Int($0.bounds.width))x\(Int($0.bounds.height))" })
    let added = after.subtracting(before)
    out("panel-probe: Deck windows after=\(after.sorted())")
    out("panel-probe: added=\(added.sorted())")
    out("panel-probe: frontmost after=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")
    // Dismiss with Esc so the panel is not left open.
    postKeys(CGKeyCode(kVK_Escape), flags: [])
    Thread.sleep(forTimeInterval: 0.6)
    let gone = Set(deckWindows().map { "\($0.layer):\(Int($0.bounds.width))x\(Int($0.bounds.height))" })
    let panelAppeared = !added.isEmpty
    let panelGone = added.subtracting(gone).count == added.count
    out("panel-probe: appeared=\(panelAppeared) dismissedAfterEsc=\(panelGone)")
    out("panel-probe: \(panelAppeared ? "PASS (a Deck window appeared on the shortcut)" : "FAIL (no new window — check the shortcut value and AX trust)")")
    exit(panelAppeared ? 0 : 1)
}

// MARK: - dispatch

let defaultShortcut: CGKeyCode = CGKeyCode(kVK_Space) // 49
func parseShortcut() -> (CGKeyCode, CGEventFlags) {
    guard let s = argValue("--shortcut") else { return (defaultShortcut, .maskAlternate) }
    let parts = s.split(separator: ",").compactMap { Int($0) }
    let code = CGKeyCode(parts.first ?? Int(defaultShortcut))
    var flags: CGEventFlags = []
    let mods = parts.count > 1 ? parts[1] : 2048 // Carbon optionKey
    if mods & 256 != 0 { flags.insert(.maskCommand) }
    if mods & 512 != 0 { flags.insert(.maskShift) }
    if mods & 2048 != 0 { flags.insert(.maskAlternate) }
    if mods & 4096 != 0 { flags.insert(.maskControl) }
    return (code, flags)
}

if has("--selftest") {
    runSelftest()
} else if has("--url-cold") {
    runURLCold()
} else if has("--url-running") {
    runURLRunning()
} else if has("--agents") {
    runAgents(wait: Int(argValue("--wait") ?? "90") ?? 90)
} else if has("--panel-probe") {
    runPanelProbe(shortcut: parseShortcut().0, flags: parseShortcut().1)
} else if has("--post-hotkey") {
    NSApplication.shared.setActivationPolicy(.accessory)
    postHotkey(shortcut: parseShortcut().0, flags: parseShortcut().1)
    exit(0)
} else {
    out("""
    deck-probe — spotlight-shell lifecycle checks
      --selftest                 prove raw CGEvent posting reaches a key field (run first)
      --url-cold                 cold URL launch: forward, exit, no window
      --url-running              running Deck: forward, stay, no new window
      --agents [--wait N]        quit+relaunch; agent witness mtimes must advance
      --panel-probe [--shortcut "code,mods"]   post the shortcut; a Deck window must appear
      --post-hotkey [--shortcut "code,mods"]   just post it
    """)
    exit(0)
}
