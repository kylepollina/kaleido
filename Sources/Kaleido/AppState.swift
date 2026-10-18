import AppKit
import Combine
import KaleidoCore
import os

@MainActor
final class AppState: ObservableObject, PhotoProvider {
    static let shared = AppState()

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            applySettings()
            scheduleSave()
        }
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var suspensionReason: String?

    let library: PhotoLibrary
    let photos = PhotosService()
    @Published private(set) var isSyncing = false
    private var syncDebounce: Task<Void, Never>?
    private var filterObserver: AnyCancellable?
    let renderer: KaleidoRenderer?
    private var desktop: DesktopController?
    private let queue: PhotoQueue<UUID>
    private let power = PowerMonitor()
    private var saveTask: Task<Void, Never>?
    private var libraryObserver: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let log = Logger(subsystem: "local.kaleido.app", category: "app")

    private var screensAsleep = false, systemAsleep = false, sessionInactive = false, screenLocked = false

    init() {
        var loaded = JSONFile.load(Settings.self, from: Paths.settingsFile) ?? Settings()
        loaded.clamp()
        settings = loaded
        library = PhotoLibrary(fileURL: Paths.libraryFile)
        queue = PhotoQueue(shuffle: loaded.shuffle)
        renderer = KaleidoRenderer()
        renderer?.provider = self
        if let renderer { desktop = DesktopController(renderer: renderer) }
        applySettings()
        libraryObserver = library.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        photos.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        photos.onLibraryChange = { [weak self] in self?.scheduleSync(after: 20) }
        filterObserver = library.$filters.dropFirst().removeDuplicates().sink { [weak self] _ in self?.scheduleSync(after: 1) }
        startSyncSchedule()
        observeSystem()
        power.onChange = { [weak self] in Task { @MainActor in self?.refreshSuspension() } }
        if renderer?.debug == true {
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    FileHandle.standardError.write(Data("kaleido: photos status \(self.photos.status.rawValue), albums \(self.photos.albums.count), items \(self.library.items.count)\n".utf8))
                    if self.isPlaying { FileHandle.standardError.write(Data((self.diagnostics() + "\n").utf8)) }
                }
            }
        }
        handleLaunchArguments()
        if settings.playOnLaunch { play() }
    }

    // MARK: Playback

    func play() {
        guard let desktop, !isPlaying else { return }
        isPlaying = true
        desktop.show(fps: currentFrameRate)
        refreshSuspension()
        log.info("playing on \(desktop.coveredDisplays.count) display(s)")
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        desktop?.hide()
        log.info("stopped")
    }

    func diagnostics() -> String { desktop?.diagnostics() ?? "No Metal device" }

    func rebuildDesktop() { desktop?.rebuild(reassert: true) }

    func togglePlay() { isPlaying ? stop() : play() }
    func nextPhoto() { renderer?.skip() }
    func surpriseMe() { settings.look = Look.random() }
    func apply(_ preset: Preset) { settings.look = preset.look }

    // MARK: PhotoProvider

    func nextPhoto(after current: UUID?) -> PhotoRef? {
        queue.shuffle = settings.shuffle
        let items = library.enabledItems
        let ids = items.map(\.id)
        var cur = current
        // Skip photos whose file has gone missing instead of stalling on them.
        for _ in 0..<min(items.count, 25) {
            guard let id = queue.next(from: ids, current: cur), let item = library.item(id) else { return nil }
            if let assetID = item.assetID { return PhotoRef(id: id, source: .asset(assetID)) }
            if let url = library.resolveURL(for: id) { return PhotoRef(id: id, source: .file(url)) }
            cur = id
        }
        return nil
    }

    // MARK: Syncing photo sources

    func showNow(_ id: UUID) {
        guard let item = library.item(id) else { return }
        if let a = item.assetID { renderer?.show(PhotoRef(id: id, source: .asset(a))) }
        else if let url = library.resolveURL(for: id) { renderer?.show(PhotoRef(id: id, source: .file(url))) }
    }

    func setAlbum(_ album: AlbumInfo, included: Bool) {
        var list = library.albums.filter { $0.localID != album.localID }
        if included { list.append(album.ref) }
        library.setAlbums(list)
        if included { syncNow() }
    }

    func connectPhotos() { Task { await photos.requestAccess(); syncNow() } }

    /// Rescans chosen albums and watched folders, then adds new photos and drops vanished ones.
    func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        let albums = library.albums, folders = library.folders, filters = library.filters
        let authorized = photos.isAuthorized
        Task {
            let listings = await Task.detached(priority: .utility) { () -> [String: [SyncEntry]] in
                var out: [String: [SyncEntry]] = [:]
                for f in folders { if let l = FolderScanner.scan(f) { out[f.id] = l } }
                if authorized {
                    for a in albums { if let l = PhotosService.listing(albumID: a.localID, filters: filters) { out[a.id] = l } }
                }
                return out
            }.value
            library.applySync(listings: listings, markSynced: true)
            photos.refreshAlbums()
            isSyncing = false
            log.info("synced: \(self.library.items.count) photos")
        }
    }

    private func scheduleSync(after seconds: Double) {
        syncDebounce?.cancel()
        syncDebounce = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { syncNow() }
        }
    }

    /// Sync at launch, then check hourly and sync once the last sync is a day old.
    private func startSyncSchedule() {
        scheduleSync(after: 2)
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Date().timeIntervalSince(self.library.lastSync ?? .distantPast) > 23 * 3600 { self.syncNow() }
            }
        }
    }

    // MARK: Settings

    private var currentFrameRate: Int {
        settings.effectiveFrameRate(lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    private func applySettings() {
        guard let renderer else { return }
        renderer.targetLook = settings.look
        renderer.secondsPerPhoto = settings.secondsPerPhoto
        renderer.transitionSeconds = settings.transitionSeconds
        renderer.transitionStyle = settings.transition
        queue.shuffle = settings.shuffle
        desktop?.setFrameRate(currentFrameRate)
        refreshSuspension()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [settings] in
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { JSONFile.save(settings, to: Paths.settingsFile) }
        }
    }

    func flushSettings() {
        saveTask?.cancel()
        JSONFile.save(settings, to: Paths.settingsFile)
    }

    // MARK: Being a good citizen

    private func refreshSuspension() {
        var reason: String?
        if screensAsleep || systemAsleep { reason = "Display asleep" }
        else if screenLocked || sessionInactive { reason = "Screen locked" }
        else if settings.pauseOnBattery && PowerMonitor.onBattery { reason = "On battery" }
        if reason != suspensionReason { suspensionReason = reason }
        desktop?.setSuspended(reason != nil)
    }

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        func watch(_ name: Notification.Name, center: NotificationCenter = ws, _ body: @escaping (AppState) -> Void) {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { guard let self else { return }; body(self); self.refreshSuspension() }
            }
        }
        watch(NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        watch(NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        watch(NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        watch(NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        watch(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        watch(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        let dist = DistributedNotificationCenter.default()
        watch(Notification.Name("com.apple.screenIsLocked"), center: dist) { $0.screenLocked = true }
        watch(Notification.Name("com.apple.screenIsUnlocked"), center: dist) { $0.screenLocked = false }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
    }

    // MARK: Launch arguments (for testing and scripting)

    private func handleLaunchArguments() {
        let args = CommandLine.arguments
        var i = 1
        var play = false
        while i < args.count {
            switch args[i] {
            case "--add" where i + 1 < args.count:
                library.add(urls: [URL(fileURLWithPath: args[i + 1])]); i += 1
            case "--play": play = true
            case "--album" where i + 1 < args.count:
                let want = args[i + 1]; i += 1
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    if let a = self.photos.albums.first(where: { $0.title.localizedCaseInsensitiveContains(want) }) { self.setAlbum(a, included: true) }
                }
            case "--connect-photos": connectPhotos()
            default: break
            }
            i += 1
        }
        if play { self.play() }
        if renderer?.debug == true {
            FileHandle.standardError.write(Data("kaleido: photos status \(photos.status.rawValue), albums \(photos.albums.count)\n".utf8))
        }
    }
}
