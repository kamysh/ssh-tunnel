import SwiftUI

struct MenuView: View {
    @ObservedObject var model: TunnelsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SSH Tunnels").font(.headline)

            if model.hosts.isEmpty {
                Text("No hosts found in tunnels.config")
                    .font(.callout).foregroundStyle(.secondary)
            }

            ForEach(model.hosts) { host in
                HostRow(host: host) { model.toggle(host) }
            }

            if let e = model.lastError {
                Text(e).font(.caption).foregroundStyle(.red).lineLimit(2)
            }

            Divider()

            HStack {
                Button("Reload") { model.refresh() }
                Button("Open Config") { model.openConfig() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}

private struct HostRow: View {
    let host: HostState
    let toggle: () -> Void
    @State private var expanded = false

    private var dotColor: Color {
        switch host.health {
        case .down:    return .gray
        case .partial: return .orange
        case .up:      return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Circle().fill(dotColor).frame(width: 9, height: 9)
                Text(host.id).fontWeight(.medium)
                Text(host.hostname).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(host.connected ? "Disconnect" : "Connect", action: toggle)
                    .controlSize(.small)
            }

            DisclosureGroup(isExpanded: $expanded) {
                ForEach(host.forwards) { f in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(f.probeable ? (f.listening ? Color.green : Color.gray)
                                              : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(f.display).font(.system(.caption, design: .monospaced))
                        Spacer()
                    }
                }
            } label: {
                Text("\(host.forwards.count) forward\(host.forwards.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
