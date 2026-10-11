import AppKit
import Carbon.HIToolbox

/// The global shortcut, via Carbon's `RegisterEventHotKey`.
///
/// Measured in the phase 0 probe (`docs/planning/spotlight-shell/probe.md`):
/// under hardened runtime it needs no entitlement and raises no permission
/// prompt, and a second registration of the same combination fails with
/// `eventHotKeyExistsErr` (-9878), so a conflict is detectable rather than
/// silent. An `NSEvent` global monitor would have needed Accessibility.
@MainActor
final class SpotlightHotKey {
    /// Status of the most recent `register`, for the settings tab to word.
    /// `noErr` (0) until something is registered.
    private(set) var lastStatus: OSStatus = noErr

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    fileprivate var onPress: () -> Void = {}

    /// (Re)registers the shortcut, replacing any previous one. Returns the
    /// Carbon status; `noErr` means registered.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, onPress: @escaping () -> Void) -> OSStatus {
        unregister()
        self.onPress = onPress

        if handlerRef == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, userData in
                    guard let userData else { return noErr }
                    let this = Unmanaged<SpotlightHotKey>.fromOpaque(userData).takeUnretainedValue()
                    // Carbon delivers on the main thread; hop explicitly so the
                    // @MainActor isolation is honest.
                    DispatchQueue.main.async { MainActor.assumeIsolated { this.onPress() } }
                    return noErr
                },
                1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }

        let id = EventHotKeyID(signature: OSType(0x6465636B), id: 1)  // 'deck'
        lastStatus = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), id,
            GetApplicationEventTarget(), 0, &hotKeyRef)
        if lastStatus != noErr { hotKeyRef = nil }
        return lastStatus
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
