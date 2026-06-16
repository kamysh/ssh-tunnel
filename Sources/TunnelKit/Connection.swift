import Foundation

/// One host's live connection — the unit of control.
///
/// Host-as-unit: connecting opens a single ControlMaster process that applies the
/// host's *entire* configured forward set (no `ClearAllForwardings` — we want the
/// config forwards). Disconnecting tears that process down, so all of the host's
/// forwards drop together. The app keeps no per-forward enable/disable state,
/// which is what lets ssh config stay the complete source of truth.
public final class HostConnection {
    public let alias: String
    public let ssh: String
    public let controlPath: String      // matches the config's ControlPath (per-alias via %n)
    public let askpassPath: String?
    public let configFile: String?

    public init(
        alias: String,
        ssh: String = "/usr/bin/ssh",
        controlPath: String = "~/.ssh/cm-%n",
        askpassPath: String? = nil,
        configFile: String? = nil
    ) {
        self.alias = alias
        self.ssh = ssh
        self.controlPath = controlPath
        self.askpassPath = askpassPath
        self.configFile = configFile
    }

    private var baseOptions: [String] {
        var opts: [String] = []
        if let configFile { opts += ["-F", configFile] }
        opts += ["-o", "ControlPath=\(controlPath)"]
        return opts
    }

    /// Routes interactive prompts to the GUI askpass helper. SSH_ASKPASS_REQUIRE=force
    /// (OpenSSH 8.4+) makes ssh use it even with no TTY — the menu-bar-app case.
    private var askpassEnv: [String: String] {
        guard let askpassPath else { return [:] }
        return [
            "SSH_ASKPASS": askpassPath,
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY": ProcessInfo.processInfo.environment["DISPLAY"] ?? ":0",
        ]
    }

    public func isConnected() -> Bool {
        (try? ProcessRunner.run(ssh, baseOptions + ["-O", "check", alias]))?.ok ?? false
    }

    /// Bring the host up. Auth happens here, once. `ExitOnForwardFailure=yes` makes
    /// a busy local port fail the whole connect (host-as-unit is all-or-nothing)
    /// rather than coming up half-forwarded.
    @discardableResult
    public func connect(persist: String = "10m") throws -> CommandResult {
        let args = baseOptions + [
            "-M", "-N", "-f",
            "-o", "ControlMaster=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ControlPersist=\(persist)",
            "-o", "ServerAliveInterval=15",
            alias,
        ]
        return try ProcessRunner.run(ssh, args, extraEnv: askpassEnv)
    }

    /// Take the host down — drops all of its forwards with it.
    @discardableResult
    public func disconnect() throws -> CommandResult {
        try ProcessRunner.run(ssh, baseOptions + ["-O", "exit", alias])
    }
}
