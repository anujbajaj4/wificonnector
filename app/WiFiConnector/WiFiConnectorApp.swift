import SwiftUI

/// A menu-bar app: an icon in the top bar with a menu, and a Settings window
/// opened from it. There's no Dock icon or main window because the Info.plist
/// sets LSUIElement (see the target's build settings).
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

        Window("WiFiConnector Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        // Only open when asked from the menu, not at launch.
        .defaultLaunchBehavior(.suppressed)
    }
}
