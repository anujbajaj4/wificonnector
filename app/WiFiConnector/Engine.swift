import Foundation

/// The bash script that does the real work, bundled inside the app.
///
/// For now the app never touches the network or the Keychain itself: it runs
/// `wificonnector <command>` and reads what it prints. Each command starts in
/// a new session with no controlling terminal (POSIX_SPAWN_SETSID). That
/// matters for `set-credentials`: macOS's `security` tool asks for passwords
/// on the terminal if there is one, and only reads them from stdin (our pipe)
/// when there isn't.
enum Engine {
    struct Result {
        let status: Int32
        let output: String

        var succeeded: Bool { status == 0 }

        /// The script reports its outcome on the last line it prints.
        var lastLine: String {
            output.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        }
    }

    static var scriptPath: String? {
        Bundle.main.path(forResource: "wificonnector", ofType: nil)
    }

    /// Runs `wificonnector <arguments>`, optionally feeding `input` on stdin.
    /// Blocks until the script exits, so call it off the main thread.
    static func run(_ arguments: [String], input: String? = nil) -> Result {
        guard let script = scriptPath else {
            return Result(status: -1, output: "The wificonnector script is missing from the app bundle.")
        }
        return spawn("/bin/bash", [script] + arguments, input: input)
    }

    // From <spawn.h>; written out because Swift doesn't always import it.
    private static let spawnSetSID: Int16 = 0x0400

    private static func spawn(_ path: String, _ arguments: [String], input: String?) -> Result {
        var stdinPipe: [Int32] = [-1, -1]
        var stdoutPipe: [Int32] = [-1, -1]
        guard pipe(&stdinPipe) == 0, pipe(&stdoutPipe) == 0 else {
            return Result(status: -1, output: "Couldn't create a pipe.")
        }
        // If the script exits without reading its input, writing to the pipe
        // must fail quietly instead of killing the app with SIGPIPE.
        _ = fcntl(stdinPipe[1], F_SETNOSIGPIPE, 1)

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdinPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], 2)
        posix_spawn_file_actions_addclose(&actions, stdinPipe[1])
        posix_spawn_file_actions_addclose(&actions, stdoutPipe[0])

        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, spawnSetSID)

        let argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let spawnError = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
        close(stdinPipe[0])
        close(stdoutPipe[1])
        guard spawnError == 0 else {
            close(stdinPipe[1])
            close(stdoutPipe[0])
            return Result(status: -1, output: "Couldn't start the script: \(String(cString: strerror(spawnError)))")
        }

        if let input {
            let bytes = Array(input.utf8)
            bytes.withUnsafeBufferPointer { buffer in
                _ = write(stdinPipe[1], buffer.baseAddress, buffer.count)
            }
        }
        close(stdinPipe[1])

        let output = FileHandle(fileDescriptor: stdoutPipe[0], closeOnDealloc: true).readDataToEndOfFile()

        var waitStatus: Int32 = 0
        while waitpid(pid, &waitStatus, 0) == -1 && errno == EINTR {}
        // WIFEXITED / WEXITSTATUS, which are C macros Swift can't call.
        let exited = (waitStatus & 0x7f) == 0
        let status = exited ? (waitStatus >> 8) & 0xff : -1

        return Result(status: status, output: String(decoding: output, as: UTF8.self))
    }
}
