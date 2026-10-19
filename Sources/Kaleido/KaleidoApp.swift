import AppKit
import KaleidoCore
import SwiftUI

@main
struct KaleidoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState.shared

    init() {
        if CommandLine.arguments.contains("--snapshot") {
            MainActor.assumeIsolated { Snapshot.runAndExit() }
        }
    }

    var body: some Scene {
        Window("Kaleido", id: "main") {
            ContentView().environmentObject(app)
        }
        .defaultSize(width: 1100, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Debug") {
                Button("Display Diagnostics…") { DebugTools.showDiagnostics(app) }
                Button("Rebuild Desktop Windows") { app.rebuildDesktop() }
                Button("Save Window Report") { app.writeWindowReport(nil) }
            }
        }

        MenuBarExtra {
            MenuBarContent().environmentObject(app)
        } label: {
            Image(systemName: app.isPlaying ? "camera.macro.circle.fill" : "camera.macro")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private var spaceMonitor: Any?

    /// Space plays and stops, except while typing in a text field.
    func applicationDidFinishLaunching(_ notification: Notification) {
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            guard event.keyCode == 49, mods.isEmpty, !event.isARepeat,
                  !(event.window?.firstResponder is NSText) else { return event }
            MainActor.assumeIsolated { AppState.shared.togglePlay() }
            return nil
        }
    }

    /// Switching back to Kaleido (Cmd-Tab, Dock) brings the window back if it was closed.
    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated {
            let hasWindow = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && $0.level == .normal }
            if !hasWindow { AppState.shared.openMainWindow?() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppState.shared.flushSettings()
            AppState.shared.stop()   // closes the desktop windows so nothing lingers
        }
    }
}

enum DebugTools {
    /// App diagnostics plus every desktop-level window the window server knows about.
    @MainActor
    static func fullReport(_ app: AppState) -> String {
        var out = app.diagnostics() + "\n\nWindow server, windows at or below the desktop-icon level:\n"
        let icons = Int(CGWindowLevelForKey(.desktopIconWindow))
        var order = 0
        for w in (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]) ?? [] {
            order += 1
            let layer = w["kCGWindowLayer"] as? Int ?? 0
            guard layer <= icons else { continue }
            let b = w["kCGWindowBounds"] as? [String: Any] ?? [:]
            out += "#\(order) layer \(layer) owner \(w["kCGWindowOwnerName"] ?? "?") name '\(w["kCGWindowName"] ?? "")' id \(w["kCGWindowNumber"] ?? 0) frame \(b["X"] ?? 0),\(b["Y"] ?? 0) \(b["Width"] ?? 0)x\(b["Height"] ?? 0) alpha \(w["kCGWindowAlpha"] ?? 1) sharing \(w["kCGWindowSharingState"] ?? "?") onscreen \(w["kCGWindowIsOnscreen"] ?? false)\n"
        }
        return out
    }

    @MainActor
    static func showDiagnostics(_ app: AppState) {
        let text = app.isPlaying ? app.diagnostics() : "Not playing. Press Play first, then run this again.\n\n" + app.diagnostics()
        let alert = NSAlert()
        alert.messageText = "Kaleido display diagnostics"
        alert.informativeText = text
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
