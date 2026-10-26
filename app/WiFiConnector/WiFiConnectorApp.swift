import AppKit
import SwiftUI

/// A menu-bar app: an icon in the top bar with a menu, a welcome window that
/// opens until setup is done, and a Settings window opened from the menu.
/// There's no Dock icon or main window because the Info.plist sets
/// LSUIElement (see the target's build settings).
@main
struct WiFiConnectorApp: App {
    @StateObject private var model = StatusModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Welcome to WiFiConnector", id: "welcome") {
            WelcomeView(model: model)
        }
        .windowResizability(.contentSize)
        // Opened at launch by MenuBarLabel when setup is needed. Restoring
        // an old copy's windows would get in the way, so it never restores.
        .defaultLaunchBehavior(model.needsSetup ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        Window("WiFiConnector Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        // Only open when asked from the menu, not at launch.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// The menu-bar icon. It's drawn as soon as the app starts, so it's where a
/// first run opens the welcome window: a Window's own launch behavior
/// doesn't reliably open it in a menu-bar app.
private struct MenuBarLabel: View {
    @ObservedObject var model: StatusModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.symbol)
            .onAppear {
                guard model.needsSetup else { return }
                // After launch finishes, or the window can open behind others.
                DispatchQueue.main.async {
                    openWindow(id: "welcome")
                    NSApp.activate()
                }
            }
    }
}
