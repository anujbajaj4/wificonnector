import Foundation

/// What `wificonnector info` reports, one `key=value` per line.
struct EngineInfo: Equatable {
    var version = ""
    /// The script's last state: online, paused, rejected, not-vit, ...
    var state = ""
    var paused = false
    var user = ""
    var credentials = false
    var agent = false
    var agentVersion = ""
    /// The newest line of the background agent's log.
    var last = ""

    init() {}

    init(parsing output: String) {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let value = String(parts[1])
            switch parts[0] {
            case "version": version = value
            case "state": state = value
            case "paused": paused = value == "yes"
            case "user": user = value
            case "credentials": credentials = value == "yes"
            case "agent": agent = value == "yes"
            case "agent_version": agentVersion = value
            case "last": last = value
            default: break
            }
        }
    }

    /// The installed agent runs an older script than the one in this app.
    var agentOutdated: Bool {
        agent && !agentVersion.isEmpty && agentVersion != version
    }
}

// MARK: - What the menu shows

extension EngineInfo {
    /// SF Symbol for the menu-bar icon.
    func symbol(busy: Bool) -> String {
        if busy { return "arrow.triangle.2.circlepath" }
        if paused { return "pause.circle" }
        if !agent || !credentials { return "wifi.exclamationmark" }
        switch state {
        case "online", "": return "wifi"
        case "disconnected", "no-wifi": return "wifi.slash"
        case "foreign-portal", "not-vit": return "wifi.circle"
        default: return "wifi.exclamationmark"
        }
    }

    /// The first line of the menu.
    var headline: String {
        if !credentials { return "No credentials saved" }
        if !agent { return "Background agent not installed" }
        if paused { return "Auto-login paused" }
        switch state {
        case "online": return "Online"
        case "disconnected": return "Wi-Fi not connected"
        case "no-wifi": return "No Wi-Fi hardware found"
        case "probe-failed": return "Can't check the connection"
        case "foreign-portal": return "Not a VIT login page"
        case "not-vit": return "Not on VIT Wi-Fi"
        case "rejected", "backoff": return "Login refused: check your password"
        case "no-internet", "backoff-unverified": return "Logged in, but no internet yet"
        case "no-credentials": return "No credentials saved"
        case "login-failed": return "Login failed"
        case "paused": return "Auto-login paused"
        default: return "Waiting for the first check"
        }
    }

    /// The second line: who is logged in and the agent's latest log entry.
    var detail: String {
        var parts: [String] = []
        if !user.isEmpty { parts.append(user) }
        if let entry = LogLine(last) { parts.append("\(entry.message) (\(entry.time))") }
        return parts.joined(separator: " · ")
    }
}

/// A line of the script's log: "2026-10-25 23:54:40 Logged in; internet is up".
struct LogLine {
    let time: String
    let message: String

    init?(_ line: String) {
        guard line.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} "#, options: .regularExpression) != nil else {
            return nil
        }
        let afterDate = line.dropFirst(11)
        time = String(afterDate.prefix(5))
        message = String(afterDate.dropFirst(9))
    }

    /// The message of a log line, or the line itself if it has no timestamp.
    static func message(of line: String) -> String {
        LogLine(line)?.message ?? line
    }
}
