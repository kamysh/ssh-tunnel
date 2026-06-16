import AppKit
import SwiftUI
import TunnelKit

@main
struct TunnelsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = TunnelsModel(
        hostListFile: ("~/.ssh/tunnels.config" as NSString).expandingTildeInPath,
        sshConfigFile: nil,                      // use ssh's default config (which Includes tunnels.config)
        askpassPath: AppDelegate.siblingAskpass())

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            // Monochrome template in the menu bar → show state via filled vs hollow,
            // not colour. Filled when any host is connected.
            let anyUp = model.hosts.contains { $0.connected }
            Image(systemName: anyUp
                ? "point.3.filled.connected.trianglepath.dotted"
                : "point.3.connected.trianglepath.dotted")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Menu-bar-only: no Dock icon. (For a shipped .app, also set LSUIElement.)
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// The askpass helper is built next to this binary.
    static func siblingAskpass() -> String? {
        guard let dir = (Bundle.main.executablePath as NSString?)?.deletingLastPathComponent
        else { return nil }
        let path = dir + "/tunnels-askpass"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}
