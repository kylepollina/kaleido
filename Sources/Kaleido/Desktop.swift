import AppKit
import KaleidoCore

/// One borderless window per display, sitting just above the wallpaper and below the desktop icons.
/// Windows exist only while playing; hiding closes them, so the normal wallpaper is simply back.
@MainActor
final class DesktopController {
    private let renderer: KaleidoRenderer
    private var windows: [CGDirectDisplayID: (window: NSWindow, view: KaleidoView)] = [:]
    private var screenObserver: NSObjectProtocol?
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
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    func hide() {
        isShowing = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
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

    private func close(_ window: NSWindow) {
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    /// Reconciles windows with the connected displays: adds, removes and re-frames as needed.
    private func rebuild() {
        guard isShowing else { return }
        var live: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            live.insert(id)
            if let entry = windows[id] {
                if entry.window.frame != screen.frame { entry.window.setFrame(screen.frame, display: true) }
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
