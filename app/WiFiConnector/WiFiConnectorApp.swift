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
            Image(systemName: model.symbol)
        }
        .menuBarExtraStyle(.menu)

        Window("Welcome to WiFiConnector", id: "welcome") {
            WelcomeView(model: model)
        }
        .windowResizability(.contentSize)
        // StatusModel reads the state before this is decided, so a fresh
        // install opens the window and a set-up one stays in the menu bar.
        .defaultLaunchBehavior(model.needsSetup ? .presented : .suppressed)

        Window("WiFiConnector Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        // Only open when asked from the menu, not at launch.
        .defaultLaunchBehavior(.suppressed)
    }
}
