import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("OPENCODE")

            HStack {
                Text("Server URL")
                    .foregroundStyle(.primary)
                Spacer()
                TextField("http://host:4096", text: serverURLBinding)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 150)
            }

            HStack {
                Text("Server password")
                    .foregroundStyle(.primary)
                Spacer()
                TextField("OPENCODE_SERVER_PASSWORD", text: $settings.settings.token)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 150)
            }

            toggleRow("Show chart", isOn: $settings.settings.showChart)
            toggleRow("Show models", isOn: $settings.settings.showModels)

            HStack {
                Text("Refresh")
                    .foregroundStyle(.primary)
                Spacer()
                Picker("", selection: $settings.settings.refreshInterval) {
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }

            Divider().overlay(.secondary.opacity(0.15))

            sectionTitle("STARTUP")

            toggleRow("Open at startup", isOn: launchAtLoginBinding)

            Divider().overlay(.secondary.opacity(0.15))

            sectionTitle("COLORS")

            metricRow(title: "Input", color: colorBinding(\.inputColor))
            metricRow(title: "Output", color: colorBinding(\.outputColor))
            metricRow(title: "Cost", color: colorBinding(\.costColor))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: 12, design: .rounded))
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.settings.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        )
    }

    private var serverURLBinding: Binding<String> {
        Binding(
            get: { settings.settings.serverURL ?? "" },
            set: { settings.settings.serverURL = $0.isEmpty ? nil : $0 }
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(1)
    }

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

    private func metricRow(title: String, color: Binding<Color>) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<OpenBoxSettings, CodableColor>) -> Binding<Color> {
        Binding(
            get: { settings.settings[keyPath: keyPath].color },
            set: { settings.settings[keyPath: keyPath] = CodableColor($0) }
        )
    }
}
