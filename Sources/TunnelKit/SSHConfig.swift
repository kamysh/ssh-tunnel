import Foundation

/// A single forwarding declared for a host. Read-only here: in the host-as-unit
/// model the app never brings forwards up individually — it reads them via
/// `ssh -G` purely to display them and to probe their local ports for health.
public struct Forward: Identifiable, Hashable {
    public let flag: String        // "-L" | "-R" | "-D"
    public let kind: String        // "local" | "remote" | "dynamic"
    public let listen: String      // normalized, e.g. "5901" or "127.0.0.1:6432"
    public let connect: String?    // e.g. "localhost:5900"; nil for dynamic

    public init(flag: String, listen: String, connect: String?) {
        self.flag = flag
        self.kind = flag == "-L" ? "local" : flag == "-R" ? "remote" : "dynamic"
        self.listen = listen
        self.connect = connect
    }

    public var value: String { connect.map { "\(listen):\($0)" } ?? listen }
    public var display: String { "\(flag) \(value)" }
    public var id: String { display }

    /// Local listening port to probe. Only `-L`/`-D` listen locally.
    public var localPort: Int? {
        guard flag != "-R" else { return nil }
        return Int(listen.split(separator: ":").last.map(String.init) ?? listen)
    }
}

public struct HostConfig {
    public let alias: String
    public let hostname: String
    public let forwards: [Forward]

    public init(alias: String, hostname: String, forwards: [Forward]) {
        self.alias = alias
        self.hostname = hostname
        self.forwards = forwards
    }
}

/// Reads a host's effective config via `ssh -G`, which resolves Include / Match /
/// ProxyJump and emits the real `localforward`/`remoteforward`/`dynamicforward`
/// directives. ssh config stays the complete source of truth; we never parse it
/// by hand and never keep a parallel store.
public enum SSHConfigReader {
    public static func effectiveConfig(
        for alias: String,
        ssh: String = "/usr/bin/ssh",
        configFile: String? = nil
    ) throws -> HostConfig {
        var args: [String] = []
        if let configFile { args += ["-F", configFile] }
        args += ["-G", alias]

        let res = try ProcessRunner.run(ssh, args)
        guard res.ok else {
            throw TunnelError.sshConfig("`ssh -G \(alias)` failed: \(res.stderr)")
        }

        var hostname = alias
        var forwards: [Forward] = []
        for raw in res.stdout.split(separator: "\n") {
            let parts = raw.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let key = parts.first?.lowercased() else { continue }
            switch key {
            case "hostname" where parts.count >= 2:
                hostname = parts[1]
            case "localforward" where parts.count >= 3:
                forwards.append(Forward(flag: "-L",
                                        listen: normalizeHostPort(parts[1]),
                                        connect: normalizeHostPort(parts[2])))
            case "remoteforward" where parts.count >= 3:
                forwards.append(Forward(flag: "-R",
                                        listen: normalizeHostPort(parts[1]),
                                        connect: normalizeHostPort(parts[2])))
            case "dynamicforward" where parts.count >= 2:
                forwards.append(Forward(flag: "-D",
                                        listen: normalizeHostPort(parts[1]),
                                        connect: nil))
            default:
                break
            }
        }
        return HostConfig(alias: alias, hostname: hostname, forwards: forwards)
    }

    /// `ssh -G` brackets the connect host, e.g. "[localhost]:5432" or a bare port
    /// "5432". Re-emit canonically: plain `host:port`, keeping brackets only for
    /// IPv6 literals (host contains ':').
    static func normalizeHostPort(_ token: String) -> String {
        if !token.contains(":") && !token.contains("[") { return token }   // bare port

        var host = ""
        var port = ""
        if token.hasPrefix("["), let close = token.firstIndex(of: "]") {
            host = String(token[token.index(after: token.startIndex)..<close])
            let rest = token[token.index(after: close)...]
            port = rest.hasPrefix(":") ? String(rest.dropFirst()) : String(rest)
        } else if let lastColon = token.lastIndex(of: ":") {
            host = String(token[..<lastColon])
            port = String(token[token.index(after: lastColon)...])
        } else {
            return token
        }

        if host.isEmpty { return port }
        return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
}
