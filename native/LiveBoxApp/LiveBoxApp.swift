import SwiftUI

@main
struct LiveBoxApp: App {
    var body: some Scene {
        WindowGroup("LiveBox") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("LiveBox")
                .font(.title2.weight(.semibold))
            Text("The LiveBox widget is installed.\nOpen Notification Center or right-click the desktop, choose \"Edit Widgets\", and add it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(32)
        .frame(width: 340)
    }
}
