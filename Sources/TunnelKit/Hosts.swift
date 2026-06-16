import Foundation

/// Enumerates the hosts the app manages: the concrete `Host` aliases declared in
/// a config file (the dedicated `tunnels.config`). Wildcard patterns are skipped —
/// they're not connectable hosts.
public enum ManagedHosts {
    public static func aliases(inFile file: String) throws -> [String] {
        let path = (file as NSString).expandingTildeInPath
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var aliases: [String] = []
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix("host ") else { continue }
            for name in line.dropFirst(5).split(separator: " ").map(String.init) {
                if !name.contains("*"), !name.contains("?"), !aliases.contains(name) {
                    aliases.append(name)
                }
            }
        }
        return aliases
    }
}
