import AppKit
import Foundation
import TunnelKit
import UniformTypeIdentifiers

enum HostHealth { case down, partial, up }

struct ForwardState: Identifiable {
    let id: String
    let kind: String
    let display: String
    let listening: Bool
    let probeable: Bool
}

struct HostState: Identifiable {
    let id: String          // alias
    let hostname: String
    let connected: Bool
    let forwards: [ForwardState]

    var health: HostHealth {
        if !connected { return .down }
        let probeable = forwards.filter { $0.probeable }
        if probeable.isEmpty { return .up }
        return probeable.allSatisfy { $0.listening } ? .up : .partial
    }
}

/// Drives the menu: scans the catalog + health off the main thread and publishes
/// state. Holds no tunnel state of its own — it reflects ssh config + live status.
final class TunnelsModel: ObservableObject {
    @Published var hosts: [HostState] = []
    @Published var lastError: String?

    let hostListFile: String
    let sshConfigFile: String?   // nil → ssh's default config
    let askpassPath: String?

    private var timer: Timer?
    private let work = DispatchQueue(label: "org.kamysh.tunnels.refresh")

    init(hostListFile: String, sshConfigFile: String?, askpassPath: String?) {
        self.hostListFile = hostListFile
        self.sshConfigFile = sshConfigFile
        self.askpassPath = askpassPath
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let file = hostListFile
        let cfg = sshConfigFile
        work.async { [weak self] in
            let states = TunnelsModel.scan(hostListFile: file, sshConfigFile: cfg)
            DispatchQueue.main.async { self?.hosts = states }
        }
    }

    func toggle(_ host: HostState) {
        let alias = host.id
        let cfg = sshConfigFile
        let ask = askpassPath
        let file = hostListFile
        let connect = !host.connected
        work.async { [weak self] in
            let conn = HostConnection(alias: alias, askpassPath: ask, configFile: cfg)
            var failure: String? = nil
            do {
                // A failed ssh returns a non-zero result (it does NOT throw), so we
                // must check .ok and surface stderr — otherwise failures are silent.
                let r = connect ? try conn.connect() : try conn.disconnect()
                if !r.ok {
                    let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    failure = "\(connect ? "Connect" : "Disconnect") \(alias) failed: "
                        + (msg.isEmpty ? "ssh exit \(r.status)" : msg)
                }
            } catch {
                failure = "\(alias): \(error)"
            }
            let states = TunnelsModel.scan(hostListFile: file, sshConfigFile: cfg)
            DispatchQueue.main.async {
                self?.lastError = failure       // nil on success → clears any prior error
                self?.hosts = states
            }
        }
    }

    func openConfig() {
        let url = URL(fileURLWithPath: (hostListFile as NSString).expandingTildeInPath)
        // The `.config` extension is associated with Xcode, so a plain "open" hands
        // it to Xcode. Open it in the user's default *plain-text* editor instead;
        // if there's none, just reveal it in Finder.
        if let editor = NSWorkspace.shared.urlForApplication(toOpen: UTType.plainText) {
            NSWorkspace.shared.open([url], withApplicationAt: editor,
                                    configuration: NSWorkspace.OpenConfiguration(),
                                    completionHandler: nil)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private static func scan(hostListFile: String, sshConfigFile: String?) -> [HostState] {
        let aliases = (try? ManagedHosts.aliases(inFile: hostListFile)) ?? []
        var out: [HostState] = []
        for alias in aliases {
            guard let cfg = try? SSHConfigReader.effectiveConfig(for: alias, configFile: sshConfigFile)
            else { continue }
            let connected = HostConnection(alias: alias, configFile: sshConfigFile).isConnected()
            let forwards = cfg.forwards.map { f in
                ForwardState(
                    id: f.id,
                    kind: f.kind,
                    display: f.display,
                    listening: f.localPort.map(PortProbe.isListening) ?? false,
                    probeable: f.localPort != nil)
            }
            out.append(HostState(id: alias, hostname: cfg.hostname, connected: connected, forwards: forwards))
        }
        return out
    }
}
