import AppKit

// ssh execs this helper for any interactive prompt and reads the answer from
// our stdout (first line). The prompt text arrives as argv[1].
//
//   • passphrase / password / MFA code  -> secure text field, print the value
//   • host-key confirmation ("yes/no")  -> Yes/No buttons, print "yes" / "no"
//
// Exiting non-zero tells ssh the prompt was cancelled, so auth fails cleanly.

let prompt = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "SSH is requesting input"

let app = NSApplication.shared
app.setActivationPolicy(.accessory)        // no Dock icon
app.activate(ignoringOtherApps: true)

func emit(_ s: String) {
    FileHandle.standardOutput.write(Data((s + "\n").utf8))
}

let lower = prompt.lowercased()
let isConfirm =
    lower.contains("yes/no") ||
    lower.contains("(yes/no") ||
    lower.contains("fingerprint")

let alert = NSAlert()
alert.messageText = "SSH Tunnel"
alert.informativeText = prompt

if isConfirm {
    alert.addButton(withTitle: "Yes")
    alert.addButton(withTitle: "No")
    let resp = alert.runModal()
    emit(resp == .alertFirstButtonReturn ? "yes" : "no")
    exit(0)
} else {
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    alert.accessoryView = field
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    let resp = alert.runModal()
    if resp == .alertFirstButtonReturn {
        emit(field.stringValue)
        exit(0)
    }
    exit(1)   // cancelled
}
