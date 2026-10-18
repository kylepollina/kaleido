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
