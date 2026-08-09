import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("OPENCODE")

            HStack {
                Text("Token")
                    .foregroundStyle(.primary)
                Spacer()
                TextField("OPENCODE_TOKEN", text: $settings.settings.token)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 150)
            }

            Text("Used for remote opencode servers. Local usage needs no token.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.7))

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
