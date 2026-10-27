import AppKit
import SwiftUI

/// A menu-bar app: an icon in the top bar with a menu, a welcome window that
/// opens until setup is done, and a Settings window opened from the menu
/// (both in AppWindow). There's no Dock icon or main window because the
/// Info.plist sets LSUIElement (see the target's build settings).
@main
struct WiFiConnectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = StatusModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.symbol)
        }
        .menuBarExtraStyle(.menu)
    }
}
