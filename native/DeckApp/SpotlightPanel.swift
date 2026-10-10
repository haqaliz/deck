import AppKit
import SwiftUI

// MARK: - Panel

/// A borderless floating panel that can take keystrokes without activating
/// Deck, so the app the user was in keeps focus. Proven over full-screen apps
/// and other Spaces in the phase 0 probe.
final class SpotlightKeyPanel: NSPanel {
    var onResignKey: () -> Void = {}
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc, whichever control has focus: the text field's own exit command only
    /// fires while it is first responder, and an empty field is not guaranteed
    /// to be.
    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    override func resignKey() {
        super.resignKey()
        // Click-away dismisses. `orderOut` resigns key too, so only react
        // while still visible.
        if isVisible { onResignKey() }
    }
}

// MARK: - Model

@MainActor
final class SpotlightViewModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { refresh() } } }
    @Published private(set) var sections: [SearchSection] = []
    /// One block per deferred source, filled in after the local sections.
    @Published private(set) var deferredStates: [SearchProviderID: RemoteSearchState<[SearchResult]>] = [:]
    @Published var selectedID: String?

    var settings = SpotlightSettings()
    var inputs = SpotlightInputs(clip: nil, devbox: nil, opencode: nil, configuredClockIDs: [])
    var onRun: (SearchResult) -> Void = { _ in }
    var onCopy: (SearchResult) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    /// Told the parsed query so deferred sources can be updated. Local results
    /// are synchronous and never wait on this.
    var onDeferredQuery: (_ query: SpotlightQuery) -> Void = { _ in }

    /// The sources currently showing something, in section order.
    var deferredProviders: [SearchProviderID] {
        SearchProviderID.deferredCases.filter { (deferredStates[$0] ?? .idle) != .idle }
    }

    /// Rows for one deferred source, ranked and capped like a local section.
    func deferredRows(_ provider: SearchProviderID) -> [SearchResult] {
        guard case .results(let rows)? = deferredStates[provider] else { return [] }
        let limit = SpotlightQuery.parse(query).scope == nil
            ? SpotlightEngine.perSectionLimit : SpotlightEngine.scopedLimit
        return Array(SpotlightRanking.sorted(rows).prefix(limit))
    }

    /// Local rows first, then each deferred source: the order they are drawn
    /// in, so the arrow keys move through what is on screen.
    var flat: [SearchResult] {
        sections.flatMap(\.results) + deferredProviders.flatMap { deferredRows($0) }
    }
    var hasQuery: Bool { !SpotlightQuery.parse(query).isEmpty }

    func reset() {
        query = ""
        sections = []
        deferredStates = [:]
        selectedID = nil
    }

    func refresh() {
        sections = SpotlightEngine.run(
            rawQuery: query, settings: settings, inputs: inputs,
            now: Date(), reference: .current)
        selectedID = flat.first?.id

        // Local results above are synchronous and never wait on this.
        onDeferredQuery(SpotlightQuery.parse(query))
    }

    func setState(_ provider: SearchProviderID, _ state: RemoteSearchState<[SearchResult]>) {
        deferredStates[provider] = state
        // Keep the user's selection if it is still on screen; otherwise land on
        // the first row.
        if !flat.contains(where: { $0.id == selectedID }) { selectedID = flat.first?.id }
    }

    /// Cmd-Return: copy the selected result's text, or a link's address.
    func copySelected() {
        guard let result = flat.first(where: { $0.id == selectedID }) else { return }
        onCopy(result)
    }

    func move(_ delta: Int) {
        let rows = flat
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedID } ?? 0
        selectedID = rows[min(max(current + delta, 0), rows.count - 1)].id
    }

    func runSelected() {
        guard let result = flat.first(where: { $0.id == selectedID }) else { return }
        onRun(result)
    }
}

// MARK: - View

struct SpotlightPanelView: View {
    @ObservedObject var model: SpotlightViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Deck", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .light, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .focused($focused)
                .onSubmit { model.runSelected() }
                .onExitCommand { model.onDismiss() }
                .onKeyPress(keys: [.return]) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    model.copySelected()
                    return .handled
                }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }

            if !model.sections.isEmpty || !model.deferredProviders.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.sections, id: \.provider) { section in
                                Text(section.provider.sectionTitle.uppercased())
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .tracking(1)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                                ForEach(section.results) { result in
                                    row(result)
                                        .id(result.id)
                                        .onTapGesture { model.onRun(result) }
                                }
                            }
                            ForEach(model.deferredProviders, id: \.self) { deferredBlock($0) }
                        }
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: model.selectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            } else if model.hasQuery {
                Divider()
                Text("No results")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        }
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { focused = true }
    }

    /// A deferred section. It owns its own status line, so a slow or failed
    /// source never blanks the local results above it or another source.
    @ViewBuilder private func deferredBlock(_ provider: SearchProviderID) -> some View {
        let state = model.deferredStates[provider] ?? .idle
        Text(provider.sectionTitle.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 4)
        if let line = state.line(noun: provider.noun) {
            Text(line)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
        }
        ForEach(model.deferredRows(provider)) { result in
            row(result)
                .id(result.id)
                .onTapGesture { model.onRun(result) }
        }
    }

    private func row(_ result: SearchResult) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 14, design: .rounded))
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(
            result.id == model.selectedID ? Color.accentColor.opacity(0.22) : Color.clear
        )
    }
}

// MARK: - Controller

/// Owns the panel. Reads settings and snapshots itself, when the panel opens —
/// it shares no state with `ContentView`, which only exists while the settings
/// window does.
@MainActor
final class SpotlightController {
    private let model = SpotlightViewModel()
    private let deferred = AsyncSearchCoordinator()
    private let panel: SpotlightKeyPanel
    private let host: NSHostingView<SpotlightPanelView>

    init() {
        host = NSHostingView(rootView: SpotlightPanelView(model: model))
        panel = SpotlightKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.onResignKey = { [weak self] in self?.hide() }
        panel.onCancel = { [weak self] in self?.hide() }

        model.onDismiss = { [weak self] in self?.hide() }
        model.onRun = { [weak self] result in self?.perform(result) }
        model.onCopy = { [weak self] result in
            self?.copyToPasteboard(result.action.copyText)
            self?.hide()
        }
        deferred.register(WorkItemSearchSource())
        deferred.register(PullRequestSearchSource())
        deferred.register(CommitSearchSource())
        deferred.register(EventSearchSource())
        deferred.register(MarketSearchSource())
        deferred.onState = { [weak model] provider, state in model?.setState(provider, state) }
        model.onDeferredQuery = { [weak self, weak model] query in
            guard let self, let model else { return }
            self.deferred.update(query: query, settings: model.settings)
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let deck = DeckSettings.load()
        model.settings = deck.spotlight
        model.inputs = SpotlightInputs(
            // The clipboard is read only when the user has switched it on.
            clip: deck.spotlight.clipEnabled ? ClipBoxSnapshotStore.load() : nil,
            devbox: DevBoxSnapshotStore.load(),
            opencode: OpenCodeSnapshotStore.load(),
            configuredClockIDs: deck.clockbox.cityIDs,
            shipbox: ShipBoxSnapshotStore.load())
        model.reset()
        deferred.beginSession()

        position()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        // Anything still in flight is for a panel nobody is looking at.
        deferred.cancelAll()
        model.reset()
    }

    /// Centered horizontally on the screen the pointer is on, in the upper
    /// third, and re-fitted to its content whenever the results change.
    private func position() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - frame.height * 0.28 - size.height))
    }

    /// Keeps the top edge fixed while the content grows or shrinks downward.
    func refit() {
        guard panel.isVisible else { return }
        let top = panel.frame.maxY
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
    }

    private var refitObserver: Any?
    func startObservingSize() {
        refitObserver = model.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the value lands; fit after it has.
            DispatchQueue.main.async { self?.refit() }
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func perform(_ result: SearchResult) {
        switch result.action {
        case .copy(let text):
            copyToPasteboard(text)
        case .open(let url):
            NSWorkspace.shared.open(url)
        }
        hide()
    }
}
