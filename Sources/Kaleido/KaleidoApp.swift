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
        .defaultSize(width: 1040, height: 760)
        .commands {
            CommandMenu("Debug") {
                Button("Display Diagnostics…") { DebugTools.showDiagnostics(app) }
                Button("Rebuild Desktop Windows") { app.rebuildDesktop() }
            }
        }

        MenuBarExtra {
            MenuBarContent().environmentObject(app)
        } label: {
            Image(systemName: app.isPlaying ? "sparkles" : "hexagon")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppState.shared.flushSettings()
            AppState.shared.stop()   // closes the desktop windows so nothing lingers
        }
    }
}

enum DebugTools {
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
