// THROWAWAY probe for spotlight-shell Phase 0. Not product code.
// Registers hotkeys with Carbon, shows a non-activating floating panel with a
// text field, and a status item. Prints every measurement to stdout.
//
//   probe            -> registers Option-Space (49) and a control key, runs
//   probe --selftest -> additionally posts the hotkey itself after 1s and
//                       reports whether the handler fired, then exits
import AppKit
import Carbon.HIToolbox

setvbuf(stdout, nil, _IOLBF, 0)

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.button?.title = "probe"
print("statusItem created:", item.button != nil)

let panel = KeyPanel(
    contentRect: NSRect(x: 0, y: 0, width: 600, height: 60),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered, defer: false)
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.hidesOnDeactivate = false
let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 580, height: 40))
panel.contentView?.addSubview(field)

func toggle() {
    if panel.isVisible {
        panel.orderOut(nil)
    } else {
        if let s = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: s.frame.midX - 300, y: s.frame.midY + 100))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }
    print("toggle -> visible:", panel.isVisible,
          "isKey:", panel.isKeyWindow,
          "appActive:", NSApp.isActive,
          "frontmost:", NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")
}

var fired = 0
var handlerRef: EventHandlerRef?
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
    var id = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    fired += 1
    print("hotkey fired id:", id.id)
    DispatchQueue.main.async { toggle() }
    return noErr
}, 1, &spec, nil, &handlerRef)

func register(_ code: Int, _ mods: Int, _ n: UInt32) -> OSStatus {
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x70726F62), id: n)
    return RegisterEventHotKey(UInt32(code), UInt32(mods), id, GetApplicationEventTarget(), 0, &ref)
}

// Option-Space
print("register Option-Space status:", register(kVK_Space, optionKey, 1))
// Duplicate of the same combo from the same process: the positive control
// that a failed registration is detectable (expect eventHotKeyExistsErr -9878).
print("register Option-Space AGAIN status (expect -9878):", register(kVK_Space, optionKey, 2))
// Command-Space is Spotlight's; system-owned, to see how that reports.
print("register Command-Space status:", register(kVK_Space, cmdKey, 3))

if CommandLine.arguments.contains("--selftest") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        // Post the real key chord into the session event stream.
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Space), keyDown: true)
        down?.flags = .maskAlternate
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Space), keyDown: false)
        up?.flags = .maskAlternate
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        print("posted Option-Space; AXIsProcessTrusted:", AXIsProcessTrusted())
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        print("selftest: handler fired", fired, "time(s)")
        exit(fired > 0 ? 0 : 1)
    }
}

app.run()
