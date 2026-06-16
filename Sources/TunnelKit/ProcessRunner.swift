import Foundation

public struct CommandResult {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var ok: Bool { status == 0 }
}

public enum ProcessRunner {
    /// Run `launchPath args`, merging `extraEnv` over the current environment.
    ///
    /// Output is captured via temp files, NOT pipes. This matters: `ssh -f`
    /// forks a long-lived background master that inherits our stdout/stderr
    /// write ends. With a Pipe, `readDataToEndOfFile()` would block until that
    /// background process exits (minutes later via ControlPersist) — a deadlock.
    /// A file never blocks on read, so we get the foreground (auth-phase) output
    /// and return as soon as the foreground ssh exits.
    ///
    /// stdin is /dev/null so ssh can never try to read a passphrase from our
    /// stdin — it is forced down the SSH_ASKPASS path instead.
    @discardableResult
    public static func run(
        _ launchPath: String,
        _ args: [String],
        extraEnv: [String: String] = [:]
    ) throws -> CommandResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnv { env[k] = v }
        proc.environment = env

        let tmp = FileManager.default.temporaryDirectory
        let outURL = tmp.appendingPathComponent("tnl-out-\(UUID().uuidString)")
        let errURL = tmp.appendingPathComponent("tnl-err-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)

        proc.standardOutput = outHandle
        proc.standardError = errHandle
        proc.standardInput = FileHandle.nullDevice

        try proc.run()
        proc.waitUntilExit()

        try? outHandle.close()
        try? errHandle.close()
        let outData = (try? Data(contentsOf: outURL)) ?? Data()
        let errData = (try? Data(contentsOf: errURL)) ?? Data()
        try? FileManager.default.removeItem(at: outURL)
        try? FileManager.default.removeItem(at: errURL)

        return CommandResult(
            status: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
