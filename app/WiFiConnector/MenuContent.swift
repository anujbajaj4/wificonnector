import AppKit
import SwiftUI

/// The menu that drops down from the menu-bar icon. With the `.menu` style,
/// SwiftUI turns these views into ordinary menu items: Text becomes a greyed-out
/// line, Button a clickable item, Toggle an item with a checkmark.
struct MenuContent: View {
    @ObservedObject var model: StatusModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.info.headline)
        if !model.info.detail.isEmpty {
            Text(model.info.detail)
        }
        if !model.lastAction.isEmpty {
            Text(model.lastAction)
        }

        Divider()

        Button("Log In Now") { model.logIn() }
            .disabled(model.busy || !model.info.credentials)
        Button("Log Out") { model.logOut() }
            .disabled(model.busy)
        Button(model.info.paused ? "Resume Auto-Login" : "Pause Auto-Login") { model.togglePause() }
            .disabled(model.busy)

        Divider()

        if !model.info.agent {
            Button("Install Background Agent") { model.installAgent() }
                .disabled(model.busy)
        } else if model.info.agentOutdated {
            Button("Update Background Agent") { model.installAgent() }
                .disabled(model.busy)
        }
        Button("Set Up…") { WelcomeWindow.shared.show(model: model) }
        Button("Settings…") { open("settings") }
            .keyboardShortcut(",")
        Button("Open Log") { model.openLog() }
        Toggle("Start at Login", isOn: Binding(
            get: { model.startsAtLogin },
            set: { model.setStartsAtLogin($0) }
        ))

        Divider()

        Button("Quit WiFiConnector") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// A menu-bar app has no Dock icon and is never the active app on its own,
    /// so it has to bring itself forward or the window opens behind others.
    private func open(_ window: String) {
        openWindow(id: window)
        NSApp.activate()
    }
}
