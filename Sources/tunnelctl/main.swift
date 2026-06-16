import Foundation
import TunnelKit

func err(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }

func usage() -> Never {
    err("usage: tunnelctl [-F <ssh_config>] <up|down|status> <host-alias>\n")
    err("  up    connect the host (brings up all its configured forwards)\n")
    err("  down  disconnect the host (drops all its forwards)\n")
    err("  status  show the host's forwards and health\n")
    exit(2)
}

// tunnelctl [-F/--config FILE] <command> <alias>
var rest = Array(CommandLine.arguments.dropFirst())
var configFile: String? = nil
if let flag = rest.first, flag == "-F" || flag == "--config" {
    guard rest.count >= 2 else { usage() }
    configFile = rest[1]
    rest.removeFirst(2)
}
guard rest.count >= 2 else { usage() }
let command = rest[0]
let alias = rest[1]

// askpass helper is a sibling binary
let selfPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
let askpass = (selfPath as NSString).deletingLastPathComponent + "/tunnels-askpass"
let askpassPath = FileManager.default.isExecutableFile(atPath: askpass) ? askpass : nil

let host = HostConnection(alias: alias, askpassPath: askpassPath, configFile: configFile)

func dot(_ up: Bool) -> String { up ? "🟢" : "🔴" }

func report(_ cfg: HostConfig, connected: Bool) {
    print("Host \(cfg.alias) → \(cfg.hostname)  [\(connected ? "connected" : "disconnected")]")
    if cfg.forwards.isEmpty { print("  (no forwards declared)"); return }
    for f in cfg.forwards {
        if let p = f.localPort {
            let up = PortProbe.isListening(p)
            print("  \(dot(up)) \(f.kind)\t\(f.display)\t(127.0.0.1/[::1]:\(p) \(up ? "listening" : "down"))")
        } else {
            print("  ⚪️ \(f.kind)\t\(f.display)\t(remote — not locally probable)")
        }
    }
}

do {
    let cfg = try SSHConfigReader.effectiveConfig(for: alias, configFile: configFile)

    switch command {
    case "up":
        if host.isConnected() {
            print("Already connected.")
        } else {
            print("Connecting \(alias) (askpass=\(askpassPath ?? "none"))…")
            let r = try host.connect()
            guard r.ok else { err("connect FAILED:\n\(r.stderr)\n"); exit(1) }
        }
        Thread.sleep(forTimeInterval: 0.3)
        report(cfg, connected: host.isConnected())

    case "down":
        let r = try host.disconnect()
        print(r.ok
            ? "Disconnected \(alias)."
            : "Not connected (\(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))")

    case "status":
        report(cfg, connected: host.isConnected())

    default:
        usage()
    }
} catch {
    err("error: \(error)\n"); exit(1)
}
