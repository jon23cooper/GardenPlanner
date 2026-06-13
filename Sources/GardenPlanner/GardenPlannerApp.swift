import SwiftUI

@main
struct GardenPlannerApp: App {
    @State private var appData = AppData()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appData)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(appData)
        }
    }
}
