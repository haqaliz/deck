import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var newPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("CHART")

            toggleRow("Show chart", isOn: $settings.settings.showChart)

            colorsRow

            sectionTitle("REPOS")

            toggleRow("Show repos", isOn: $settings.settings.showRepos)

            stepperRow("Repo count", value: $settings.settings.repoCount, range: 1...10)

            stepperRow("Scan depth", value: $settings.settings.scanDepth, range: 1...10)

            pathField

            pathList

            sectionTitle("REFRESH")

            refreshRow

            if !NativeWidgetDetector.isRegistered() {
                sectionTitle("STARTUP")

                toggleRow("Open at startup", isOn: launchAtLoginBinding)

                Text("Creates a LaunchAgent; takes effect on next login.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: 12, design: .rounded))
    }

    // MARK: - Rows

    private var colorsRow: some View {
        HStack(spacing: 12) {
            Text("BAR")
                .foregroundStyle(.primary)
            ColorPicker("", selection: colorBinding(\.barColor), supportsOpacity: false)
                .labelsHidden()
                .controlSize(.small)
            Text("TODAY")
                .foregroundStyle(.primary)
            ColorPicker("", selection: colorBinding(\.todayColor), supportsOpacity: false)
                .labelsHidden()
                .controlSize(.small)
            Spacer()
        }
    }

    private var pathField: some View {
        HStack(spacing: 8) {
            TextField("Path to repo or folder", text: $newPath)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .onSubmit(addPath)
            Button("Add", action: addPath)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.primary.opacity(0.12))
                )
                .disabled(newPath.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.vertical, 2)
    }

    private var pathList: some View {
        let paths = settings.settings.repoPaths
        return Group {
            if paths.isEmpty {
                Text("Scans ~/dev by default")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                        HStack(spacing: 8) {
                            Text(path)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                settings.settings.repoPaths.removeAll { $0 == path }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private var refreshRow: some View {
        HStack {
            Text("Refresh")
                .foregroundStyle(.primary)
            Spacer()
            Picker("", selection: $settings.settings.refreshSeconds) {
                Text("10s").tag(10)
                Text("30s").tag(30)
                Text("60s").tag(60)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)
            .controlSize(.small)
        }
    }

    // MARK: - Helpers

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.settings.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        )
    }

    private func addPath() {
        let path = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !settings.settings.repoPaths.contains(path) else { return }
        settings.settings.repoPaths.append(path)
        newPath = ""
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(1)
            .padding(.top, 6)
    }

    /// Label on the left, switch pinned to the right edge.
    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    /// Label on the left, stepper pinned to the right edge.
    private func stepperRow(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.small)
            Text("\(value.wrappedValue)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 20, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func colorBinding(_ keyPath: WritableKeyPath<GitBoxSettings, CodableColor>) -> Binding<Color> {
        Binding(
            get: { settings.settings[keyPath: keyPath].color },
            set: { settings.settings[keyPath: keyPath] = CodableColor($0) }
        )
    }
}
