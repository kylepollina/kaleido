import AppKit
import Combine
import IOKit.pwr_mgt
import KaleidoCore
import os
import Photos

@MainActor
final class AppState: ObservableObject, PhotoProvider {
    static let shared = AppState()

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            applySettings()
            if settings.effectSwitches != oldValue.effectSwitches {
                renderer?.applyEffectSwitchesNow(hueAllowed: settings.allowHueChanges)
            }
            scheduleSave()
        }
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var suspensionReason: String?

    let library: PhotoLibrary
    let presets = PresetLibrary(fileURL: Paths.presetsFile)
    let scenes = SceneLibrary(fileURL: Paths.scenesFile)
    let photos = PhotosService()
    /// The scene on screen, if any. A scene holds its photo until Next, Previous or another preset.
    @Published private(set) var activeSceneID: UUID?
    /// Unsaved edits in the preset or scene editor: on screen at once, written only by Save.
    @Published private(set) var draft: EditDraft? {
        didSet { if draft?.target != oldValue?.target { updateHold() } }
    }
    /// Bumped whenever a scene's thumbnail is rewritten, so cards reload it.
    @Published private(set) var sceneThumbVersion = 0
    private var sceneArriving: SavedScene?
    @Published private(set) var isSyncing = false
    private var syncAgain = false
    private var sleepAssertion: IOPMAssertionID?
    /// Set by the main window while it exists; reopens it later (e.g. on Cmd-Tab after it was closed).
    var openMainWindow: (() -> Void)?
    private var surprisePending = false
    /// A scene as it was on screen, so Back can bring back its pattern along with its photo.
    private struct ShownScene { var photoID: UUID?; var look: Look; var patternID: UUID?; var savedID: UUID? }
    private var sceneHistory: [ShownScene] = []
    /// The saved scene Shuffle picked for the photo it handed the renderer.
    private var plannedScene: SavedScene?
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
        renderer?.willStartTransition = { [weak self] id, back in self?.sceneWillStart(photoID: id, back: back) }
        renderer?.didReverseTransition = { [weak self] in self?.sceneCancelled() }
        if let renderer { desktop = DesktopController(renderer: renderer) }
        applySettings()
        libraryObserver = library.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        presets.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        scenes.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        renderer?.didDrag = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .scene = self.draft?.target else { return }
                self.draft?.moved = true
            }
        }
        if settings.activePresetID == nil, let match = presets.presets.first(where: { $0.look == settings.look }) {
            settings.activePresetID = match.id
        }
        // Play the active preset as it is now (presets can change between versions, e.g. new defaults).
        if let p = presets.preset(settings.activePresetID) {
            if p.look != settings.look { settings.look = p.look }
        } else if settings.activePresetID != nil, let first = presets.favorites.first ?? presets.presets.first {
            apply(first)   // the preset that was playing has been retired
        }
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
        updateKeepAwake()
        log.info("playing on \(desktop.coveredDisplays.count) display(s)")
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        desktop?.hide()
        updateKeepAwake()
        log.info("stopped")
    }

    /// Holds a "prevent display sleep" power assertion only while playing with Keep screen awake on.
    private func updateKeepAwake() {
        let want = isPlaying && settings.keepScreenAwake
        if want, sleepAssertion == nil {
            var id: IOPMAssertionID = 0
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Kaleido is playing on the desktop" as CFString, &id)
            if r == kIOReturnSuccess { sleepAssertion = id }
        } else if !want, let id = sleepAssertion {
            IOPMAssertionRelease(id)
            sleepAssertion = nil
        }
    }

    func diagnostics() -> String { desktop?.diagnostics() ?? "No Metal device" }

    /// Writes the diagnostics report (default: Application Support/Kaleido/window-report.txt) and returns its path.
    @discardableResult
    func writeWindowReport(_ path: String?) -> String {
        let url = path.map { URL(fileURLWithPath: $0) } ?? Paths.dataDirectory.appendingPathComponent("window-report.txt")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? DebugTools.fullReport(self).write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func rebuildDesktop() { desktop?.rebuild(reassert: true) }

    func togglePlay() { isPlaying ? stop() : play() }
    /// The next scene (saved or new, as Shuffle says; a new one even when Shuffle is off).
    func nextPhoto() {
        if library.enabledItems.count <= 1 && scenes.favorites.isEmpty {
            // No fade will come: keep the photo, change the pattern.
            sceneWillStart(photoID: renderer?.currentPhotoID, back: false)
        }
        renderer?.skip()
    }

    /// Back to the scene before: its photo and its pattern.
    func previousPhoto() { renderer?.previous() }

    /// While a pattern or scene editor is open, shuffling never swaps out what is being edited.
    var isEditingPresets = false { didSet { updateHold() } }

    func nextPhotoKeepingPreset() { renderer?.skip() }

    /// Shuffle off, or a scene open in the editor: the scene stays until you move on.
    private func updateHold() {
        var editingScene = false
        if case .scene = draft?.target { editingScene = true }
        renderer?.holdPhoto = settings.sceneShuffle == .off || editingScene || sceneTweaked
    }

    /// "Remove from selected photos" on the Original tab: out of the rotation (it stays in its album), then move on.
    func removeCurrentFromRotation() {
        // Only this photo goes; a whole album stays whole, so its new photos still join automatically.
        guard let id = renderer?.currentPhotoID, library.item(id) != nil else { return }
        library.setEnabled(false, ids: [id])
        renderer?.skip()
    }

    func revealCurrentPhoto() {
        guard let id = renderer?.currentPhotoID, let item = library.item(id) else { return }
        if item.isAsset {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
        } else if let url = library.resolveURL(for: id) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Runs as each new photo starts fading in, so the scene's pattern rides along with its photo.
    private func sceneWillStart(photoID: UUID?, back: Bool) {
        clearTweaked()
        if back, let last = sceneHistory.last, last.photoID == photoID {
            sceneHistory.removeLast()
            restore(last)
            return
        }
        sceneHistory.append(ShownScene(photoID: renderer?.currentPhotoID, look: settings.look,
                                       patternID: settings.activePresetID, savedID: activeSceneID))
        if sceneHistory.count > 40 { sceneHistory.removeFirst() }
        if let s = sceneArriving ?? plannedScene, s.photoID == photoID {
            sceneArriving = nil
            plannedScene = nil
            show(saved: s)
            return
        }
        plannedScene = nil
        // A new scene: this photo with a pattern from where Settings says (or the one being edited).
        var look = settings.look, id = settings.activePresetID
        var g = SystemRandomNumberGenerator()
        if surprisePending {
            look = Look.random(shapes: settings.inventedShapes, using: &g); id = nil
        } else if !isEditingPresets {
            (look, id) = settings.patternSource.pick(current: settings.look, currentID: settings.activePresetID,
                                                     patterns: presets, inventedShapes: settings.inventedShapes, using: &g)
        }
        surprisePending = false
        activeSceneID = nil
        settings.activePresetID = id
        settings.look = look
    }

    /// The fade to a new scene was turned back: the scene before it returns.
    private func sceneCancelled() {
        if let last = sceneHistory.popLast() { restore(last) }
    }

    private func restore(_ s: ShownScene) {
        activeSceneID = scenes.scene(s.savedID) != nil ? s.savedID : nil
        settings.activePresetID = s.patternID
        settings.look = s.look
    }

    private func show(saved s: SavedScene) {
        activeSceneID = s.id
        settings.activePresetID = nil
        settings.look = draft?.target == .scene(s.id) ? draft!.look : s.look
        renderer?.glidePan(to: SIMD2(s.panX, s.panY))
    }

    /// A new photo with an invented pattern.
    func surpriseMe() {
        surprisePending = true
        if library.enabledItems.count <= 1 { sceneWillStart(photoID: renderer?.currentPhotoID, back: false) }
        renderer?.skip()
    }

    /// Puts a pattern on the photo that is showing (a new, unsaved scene).
    func apply(_ preset: SavedPreset) {
        activeSceneID = nil
        sceneArriving = nil
        settings.activePresetID = preset.id
        settings.look = preset.look
    }

    /// Home changed the scene on screen (a pattern picked or a setting moved). Shuffle waits on it until Next,
    /// Back or Save scene, so the changes are not whisked away.
    @Published private(set) var sceneTweaked = false

    private func markTweaked() {
        activeSceneID = nil   // it is a new scene now, even if it started as a saved one
        if !sceneTweaked { sceneTweaked = true; updateHold() }
    }

    /// Home's pattern menu: loads the pattern's settings onto the photo showing.
    func choosePattern(_ preset: SavedPreset) {
        apply(preset)
        markTweaked()
    }

    /// Home's controls: changes the scene on screen (not the pattern it came from).
    func tweakScene(_ change: (inout Look) -> Void) {
        var l = settings.look
        change(&l)
        l.clamp()
        guard l != settings.look else { return }
        settings.look = l
        markTweaked()
    }

    private func clearTweaked() {
        if sceneTweaked { sceneTweaked = false; updateHold() }
    }

    /// Keeps an invented pattern that is showing.
    @discardableResult
    func saveCurrentPattern() -> UUID {
        let id = presets.add(name: "My pattern", look: settings.look)
        settings.activePresetID = id
        return id
    }

    // MARK: Scenes

    private func photoRef(_ id: UUID) -> PhotoRef? {
        guard let item = library.item(id) else { return nil }
        if let a = item.assetID { return PhotoRef(id: id, source: .asset(a)) }
        return library.resolveURL(for: id).map { PhotoRef(id: id, source: .file($0)) }
    }

    func isSceneAvailable(_ s: SavedScene) -> Bool { library.item(s.photoID) != nil }

    /// Shows a saved scene: its photo with its pattern and position.
    func showScene(_ s: SavedScene) {
        guard let renderer, let ref = photoRef(s.photoID) else { return }
        if renderer.currentPhotoID == s.photoID && activeSceneID == s.id {
            sceneArriving = nil
            show(saved: s)
        } else {
            // Always through a fade, even on the same photo, so a different pattern never jumps into place.
            sceneArriving = s
            renderer.show(ref, refade: true)
        }
    }

    /// Saved scenes Shuffle can pick: hearted, with their photo still in the library.
    private var shuffleScenes: [SavedScene] { scenes.favorites.filter(isSceneAvailable) }

    /// Freezes what is on screen (photo, look and where the photo sits) as a new scene.
    @discardableResult
    func saveScene() -> UUID? {
        guard let renderer, let photo = renderer.currentPhotoID else { return nil }
        let base = presets.preset(settings.activePresetID).map { "\($0.name) scene" } ?? "Scene"
        let id = scenes.add(name: base, photoID: photo, look: settings.look, panX: renderer.pan.x, panY: renderer.pan.y)
        writeSceneThumbnail(id)
        activeSceneID = id
        clearTweaked()
        return id
    }

    func deleteScene(_ id: UUID) {
        if activeSceneID == id { activeSceneID = nil }
        if draft?.target == .scene(id) { draft = nil }
        scenes.delete(id)
        try? FileManager.default.removeItem(at: Self.sceneThumbnailURL(id))
    }

    static func sceneThumbnailURL(_ id: UUID) -> URL {
        Paths.dataDirectory.appendingPathComponent("scene-thumbnails/\(id.uuidString).png")
    }

    /// A small picture of the kaleidoscope as it is right now, for the scene's card.
    private func writeSceneThumbnail(_ id: UUID) {
        guard let image = renderer?.snapshot(width: 384, height: 216) else { return }
        let url = Self.sceneThumbnailURL(id)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        sceneThumbVersion += 1
    }

    // MARK: Editing presets and scenes

    /// Opens a preset in the editor: it plays, and edits wait for Save.
    func beginEditing(preset id: UUID) {
        guard draft?.target != .preset(id) else { return }
        discardDraft()
        guard let p = presets.preset(id) else { return }
        draft = EditDraft(target: .preset(id), name: p.name, look: p.look)
        apply(p)
    }

    func beginEditing(scene id: UUID) {
        guard draft?.target != .scene(id) else { return }
        discardDraft()
        guard let s = scenes.scene(id) else { return }
        draft = EditDraft(target: .scene(id), name: s.name, look: s.look)
        showScene(s)
    }

    /// Changes the draft and shows it right away; nothing is saved.
    func edit(_ change: (inout Look) -> Void) {
        guard var d = draft else { return }
        change(&d.look)
        d.look.clamp()
        draft = d
        settings.look = d.look
    }

    func renameDraft(_ name: String) { draft?.name = name }

    func saveDraft() {
        guard let d = draft, d.hasChanges else { return }
        switch d.target {
        case .preset(let id):
            if d.name != d.savedName { presets.rename(id, to: d.name) }
            presets.update(id, look: d.look)
            draft = EditDraft(target: d.target, name: d.name, look: d.look)
        case .scene(let id):
            let pan = d.moved ? renderer.map { ($0.pan.x, $0.pan.y) } : nil
            scenes.update(id, name: d.name, look: d.look, pan: pan)
            draft = EditDraft(target: d.target, name: d.name, look: d.look)
            if activeSceneID == id, renderer?.currentPhotoID == scenes.scene(id)?.photoID { writeSceneThumbnail(id) }
        }
    }

    /// Back to the saved version, on screen too.
    func revertDraft() {
        guard let d = draft else { return }
        draft = EditDraft(target: d.target, name: d.savedName, look: d.savedLook)
        if d.look != d.savedLook { settings.look = d.savedLook }
        if case .scene(let id) = d.target, d.moved, let s = scenes.scene(id) { renderer?.glidePan(to: SIMD2(s.panX, s.panY)) }
    }

    /// Leaving the editor without saving throws the edits away.
    func discardDraft() {
        guard draft != nil else { return }
        revertDraft()
        draft = nil
    }

    /// Reset (presets): the factory look, or how you created it. Still needs Save.
    func resetDraftToOriginal() {
        guard case .preset(let id) = draft?.target, let p = presets.preset(id) else { return }
        draft?.name = p.originalName
        edit { $0 = p.originalLook }
    }

    /// Saves whatever is on screen (e.g. a Surprise me look) as a new hearted preset.
    @discardableResult
    func saveCurrentAsPreset() -> UUID {
        let id = presets.add(name: "My preset", look: settings.look)
        settings.activePresetID = id
        return id
    }

    // MARK: PhotoProvider

    func nextPhoto(after current: UUID?) -> PhotoRef? {
        plannedScene = nil
        let saved = shuffleScenes.filter { $0.id != activeSceneID }
        if !isEditingPresets, settings.sceneShuffle.nextIsSaved(savedCount: saved.count, roll: Double.random(in: 0..<1)),
           let s = saved.randomElement(), let ref = photoRef(s.photoID) {
            plannedScene = s
            return ref
        }
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

    /// Card checkbox: put a whole album (or folder, or the hand-added photos) in or out of the rotation.
    func toggleWhole(_ card: SourceCard) {
        let on = card.state == .none || { if case .partial = card.state { return true } else { return false } }()
        if card.id == WallpaperScanner.sourceID {
            if library.wallpapers == nil || on { library.setWallpapers(true) } else { library.setWallpapers(false) }
            return
        }
        if let album = card.album, !library.albums.contains(where: { $0.localID == album.localID }) {
            library.trackAlbum(album.ref)   // arrives with nothing selected; the sync that follows fills it in
            library.setAutoInclude(card.id, true)
            syncNow()
            return
        }
        if on { library.selectAll(in: card.id) } else {
            library.deselectAll(in: card.id)
            library.untrackIfUnused(card.id)
        }
    }

    /// Opening an album to browse it starts tracking it (nothing selected) and pulls its photos in.
    func open(_ card: SourceCard) {
        if card.id == WallpaperScanner.sourceID, library.wallpapers == nil { library.setWallpapers(true); return }
        if let album = card.album, !library.albums.contains(where: { $0.localID == album.localID }) {
            library.trackAlbum(album.ref)
            syncNow()
        }
    }

    func connectPhotos() { Task { await photos.requestAccess(); syncNow() } }

    /// Rescans chosen albums and watched folders, then adds new photos and drops vanished ones.
    func syncNow() {
        guard !isSyncing else { syncAgain = true; return }
        isSyncing = true
        let albums = library.albums, folders = library.folders, filters = library.filters
        let wallpaperRoots = library.wallpapers != nil ? library.wallpaperRoots : nil
        let authorized = photos.isAuthorized
        Task {
            let listings = await Task.detached(priority: .utility) { () -> [String: [SyncEntry]] in
                var out: [String: [SyncEntry]] = [:]
                for f in folders { if let l = FolderScanner.scan(f) { out[f.id] = l } }
                if let wallpaperRoots { out[WallpaperScanner.sourceID] = WallpaperScanner.scan(roots: wallpaperRoots) }
                if authorized {
                    for a in albums { if let l = PhotosService.listing(albumID: a.localID, filters: filters) { out[a.id] = l } }
                }
                return out
            }.value
            library.applySync(listings: listings, markSynced: true)
            photos.refreshAlbums()
            isSyncing = false
            if syncAgain { syncAgain = false; syncNow() }
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
        renderer.targetLook = settings.effectiveLook(settings.look)
        renderer.secondsPerPhoto = settings.secondsPerPhoto
        renderer.transitionSeconds = settings.transitionSeconds
        renderer.transitionStyle = settings.transition
        queue.shuffle = settings.shuffle
        updateHold()
        desktop?.setFrameRate(currentFrameRate)
        refreshSuspension()
        updateKeepAwake()
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
            case "--photos-probe":
                Task.detached {
                    func n(_ pred: [NSPredicate]) -> Int {
                        guard let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil).firstObject else { return -1 }
                        let o = PHFetchOptions(); o.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: pred)
                        return PHAsset.fetchAssets(in: c, options: o).count
                    }
                    let img = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                    let shot = NSPredicate(format: "(mediaSubtypes & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
                    let size = NSPredicate(format: "(pixelWidth >= %d) OR (pixelHeight >= %d)", 1600, 1600)
                    let msg = "probe favorites: all \(n([])) image \(n([img])) image+noshot \(n([img, shot])) image+size \(n([img, size])) all three \(n([img, shot, size]))\n"
                    FileHandle.standardError.write(Data(msg.utf8))
                }
            case "--play", "--autoplay": play = true
            case "--dump-windows":
                let path = (i + 1 < args.count && !args[i + 1].hasPrefix("--")) ? args[i + 1] : nil
                if path != nil { i += 1 }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(6))
                    self.writeWindowReport(path)
                    NSApp.terminate(nil)
                }
            case "--album" where i + 1 < args.count:
                let want = args[i + 1]; i += 1
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    if let a = self.photos.albums.first(where: { $0.title.localizedCaseInsensitiveContains(want) }) { self.library.trackAlbum(a.ref); self.library.setAutoInclude(a.id, true); self.syncNow() }
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
