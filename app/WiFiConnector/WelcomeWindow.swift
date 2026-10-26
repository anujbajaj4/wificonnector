import AppKit
import SwiftUI

/// The welcome window, made with AppKit rather than as a SwiftUI Window
/// scene. SwiftUI didn't open the scene at launch in this menu-bar app, even
/// with .defaultLaunchBehavior(.presented) or openWindow from the menu-bar
/// icon; an NSWindow opens exactly when asked.
final class WelcomeWindow {
    static let shared = WelcomeWindow()

    private var window: NSWindow?

    func show(model: StatusModel) {
        // A closed window is replaced, so Set Up… starts again at the form
        // rather than at the last finish screen.
        if window?.isVisible != true {
            let view = WelcomeView(model: model) { [weak self] in self?.window?.close() }
            let hosting = NSHostingController(rootView: view)
            // The window follows the view's size as it switches between the
            // form and the finish screen.
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to WiFiConnector"
            window.styleMask = [.titled, .closable]
            // This object owns the window; AppKit mustn't free it on close.
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // Since macOS 14 an app can't make itself active while you're using
        // another one, such as Terminal running the installer, so activate()
        // alone can leave the window behind it. orderFrontRegardless puts it
        // on top either way.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

/// Opens the welcome window once launch has finished, if nothing will log in
/// automatically yet.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = StatusModel.shared
        if model.needsSetup {
            WelcomeWindow.shared.show(model: model)
        }
    }
}
