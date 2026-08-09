import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("CHART")

            toggleRow("Show chart", isOn: $settings.settings.showChart)

            Divider().overlay(.secondary.opacity(0.15))

            sectionTitle("REPOS")

            toggleRow("Show repos", isOn: $settings.settings.showRepos)

            Divider().overlay(.secondary.opacity(0.15))

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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.settings.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(1)
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
    }
}
