import AppKit
import KaleidoCore

/// One borderless window per display, sitting just above the wallpaper and below the desktop icons.
/// Windows exist only while playing; hiding closes them, so the normal wallpaper is simply back.
@MainActor
final class DesktopController {
    private let renderer: KaleidoRenderer
    private var windows: [CGDirectDisplayID: (window: NSWindow, view: KaleidoView)] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var isShowing = false
    private var fps = 30
    private var suspended = false

    init(renderer: KaleidoRenderer) { self.renderer = renderer }

    static let windowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)

    func show(fps: Int) {
        self.fps = fps
        isShowing = true
        renderer.resetClock()
        rebuild()
        // Anything that can move, hide or drop a window re-runs the reconcile, which is cheap and idempotent.
        let ws = NSWorkspace.shared.notificationCenter
        for (center, name) in [(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
                               (ws, NSWorkspace.activeSpaceDidChangeNotification),
                               (ws, NSWorkspace.screensDidWakeNotification),
                               (ws, NSWorkspace.didWakeNotification)] {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.rebuild(reassert: true)
                    // Displays often finish reconfiguring a moment after the notification.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { self?.rebuild(reassert: true) } }
                }
            }))
        }
    }

    func hide() {
        isShowing = false
        for (center, o) in observers { center.removeObserver(o) }
        observers = []
        for (_, entry) in windows { close(entry.window) }
        windows = [:]
    }

    func setFrameRate(_ fps: Int) {
        self.fps = fps
        for (_, e) in windows { e.view.preferredFramesPerSecond = fps }
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        if !value { renderer.resetClock() }
        for (_, e) in windows { e.view.suspended = value }
    }

    /// Display ids of the screens currently covered (for logging and tests).
    var coveredDisplays: [CGDirectDisplayID] { Array(windows.keys) }

    /// Human-readable status of every screen and its window (Debug menu, and the log when KALEIDO_DEBUG is set).
    func diagnostics() -> String {
        var lines = ["Displays: \(NSScreen.screens.count), desktop windows: \(windows.count), showing: \(isShowing), suspended: \(suspended)"]
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            var line = "• \(screen.localizedName) [\(id)] frame \(Int(screen.frame.origin.x)),\(Int(screen.frame.origin.y)) \(Int(screen.frame.width))x\(Int(screen.frame.height)) @\(Int(screen.backingScaleFactor))x"
            if let e = windows[id] {
                let w = e.window, v = e.view
                line += "\n    window #\(w.windowNumber) level \(w.level.rawValue) visible \(w.isVisible) occluded \(v.occluded) paused \(v.isPaused) draws \(v.drawCount) presented \(v.presentCount) center rgb \(v.lastProbe) drawable \(Int(v.drawableSize.width))x\(Int(v.drawableSize.height)) on screen \(w.screen?.localizedName ?? "none")"
            } else {
                line += "\n    NO WINDOW"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private func close(_ window: NSWindow) {
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    /// Reconciles windows with the connected displays: adds, removes and re-frames as needed.
    func rebuild(reassert: Bool = false) {
        guard isShowing else { return }
        var live: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            live.insert(id)
            if let entry = windows[id] {
                if entry.window.frame != screen.frame { entry.window.setFrame(screen.frame, display: true) }
                if reassert {
                    entry.window.level = Self.windowLevel
                    entry.window.orderFrontRegardless()
                }
                continue
            }
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.isReleasedWhenClosed = false
            window.level = Self.windowLevel
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.canHide = false
            window.animationBehavior = .none
            window.title = "Kaleido Desktop"
            let view = KaleidoView(renderer: renderer, fps: fps)
            view.suspended = suspended
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows[id] = (window, view)
        }
        for id in windows.keys where !live.contains(id) {
            close(windows[id]!.window)
            windows[id] = nil
        }
    }
}
