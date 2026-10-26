import AppKit
import Combine
import ServiceManagement

/// The app's state, refreshed from `wificonnector info` every few seconds.
///
/// SwiftUI watches the @Published properties and redraws the menu-bar icon and
/// the menu whenever they change. Script calls block, so they run on a
/// background queue and publish their results back on the main queue.
final class StatusModel: ObservableObject {
    @Published private(set) var info = EngineInfo()
    /// A login, logout or install is running.
    @Published private(set) var busy = false
    /// The outcome of the last action, shown in the menu until the next one.
    @Published private(set) var lastAction = ""

    private var timer: Timer?
    private var refreshing = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    var symbol: String { info.symbol(busy: busy) }

    // MARK: Reading the state

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let parsed = EngineInfo(parsing: Engine.run(["info"]).output)
            DispatchQueue.main.async {
                self.refreshing = false
                if parsed != self.info { self.info = parsed }
            }
        }
    }

    // MARK: Actions

    func logIn() { perform(["login"]) }

    func logOut() { perform(["logout"]) }

    func togglePause() { perform([info.paused ? "resume" : "pause"]) }

    func installAgent() { perform(["install"]) }

    /// The password reaches the script on stdin, never as an argument.
    func saveCredentials(user: String, password: String, completion: @escaping (Engine.Result) -> Void) {
        perform(["set-credentials", user], input: password + "\n", completion: completion)
    }

    private func perform(_ arguments: [String], input: String? = nil,
                         completion: ((Engine.Result) -> Void)? = nil) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Engine.run(arguments, input: input)
            DispatchQueue.main.async {
                self.busy = false
                self.lastAction = LogLine.message(of: result.lastLine)
                completion?(result)
                self.refresh()
            }
        }
    }

    // MARK: The app itself

    func openLog() {
        let log = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/wificonnector.log")
        NSWorkspace.shared.open(log)
    }

    var startsAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setStartsAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastAction = "Couldn't change Start at Login: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }
}
