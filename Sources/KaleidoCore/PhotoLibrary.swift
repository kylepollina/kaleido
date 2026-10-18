import Combine
import Foundation

public struct PhotoItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var bookmark: Data?
    /// File path, or empty for a Photos asset.
    public var path: String
    public var isEnabled: Bool
    public var addedAt: Date
    /// Photos library local identifier, for items that live in Photos.
    public var assetID: String?
    public var title: String?
    /// Added by hand (never removed by a sync).
    public var isManual: Bool
    /// Album and folder sources that currently list this photo ("album:ID", "folder:/path").
    public var sources: Set<String>

    public init(id: UUID = UUID(), bookmark: Data? = nil, path: String, isEnabled: Bool = true, addedAt: Date = Date(),
                assetID: String? = nil, title: String? = nil, isManual: Bool = true, sources: Set<String> = []) {
        self.id = id; self.bookmark = bookmark; self.path = path; self.isEnabled = isEnabled; self.addedAt = addedAt
        self.assetID = assetID; self.title = title; self.isManual = isManual; self.sources = sources
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        assetID = try c.decodeIfPresent(String.self, forKey: .assetID)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        isManual = try c.decodeIfPresent(Bool.self, forKey: .isManual) ?? true
        sources = try c.decodeIfPresent(Set<String>.self, forKey: .sources) ?? []
    }

    public var isAsset: Bool { assetID != nil }
    /// Identity used by sync: asset identifier or file path.
    public var key: String { assetID ?? path }
    public var name: String { title ?? URL(fileURLWithPath: path).lastPathComponent }
}

public enum ImageFiles {
    public static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp", "avif"]

    public static func isSupported(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    /// Expands folders (recursively, skipping hidden files and bundles) and filters to image files.
    public static func collect(from urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
                guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: opts) else { continue }
                var found: [URL] = []
                for case let file as URL in e where isSupported(file) { found.append(file) }
                out += found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            } else if isSupported(url) {
                out.append(url)
            }
        }
        return out
    }
}

struct LibraryFile: Codable {
    var items: [PhotoItem] = []
    var folders: [FolderSource] = []
    var albums: [AlbumRef] = []
    var dismissed: Set<String> = []
    var lastSync: Date?
    var filters = PhotoFilters()
    /// macOS Wallpapers source: nil = not used, otherwise whether new wallpapers join automatically.
    var wallpapers: Bool?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([PhotoItem].self, forKey: .items) ?? []
        folders = try c.decodeIfPresent([FolderSource].self, forKey: .folders) ?? []
        albums = try c.decodeIfPresent([AlbumRef].self, forKey: .albums) ?? []
        dismissed = try c.decodeIfPresent(Set<String>.self, forKey: .dismissed) ?? []
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        filters = try c.decodeIfPresent(PhotoFilters.self, forKey: .filters) ?? PhotoFilters()
        wallpapers = try c.decodeIfPresent(Bool.self, forKey: .wallpapers)
    }
}

/// The user's curated photo list: photos added by hand, plus photos pulled in from chosen Photos albums
/// and watched folders. Items are references (bookmark/path/asset id), never copies.
public final class PhotoLibrary: ObservableObject {
    @Published public private(set) var items: [PhotoItem] = []
    @Published public private(set) var folders: [FolderSource] = []
    @Published public private(set) var albums: [AlbumRef] = []
    @Published public private(set) var lastSync: Date?
    @Published public var filters = PhotoFilters() { didSet { if filters != oldValue { save() } } }
    /// macOS Wallpapers: nil = not in use; true = whole source (new wallpapers join); false = hand-picked.
    @Published public private(set) var wallpapers: Bool?
    /// Where built-in wallpapers are looked for (tests point this at a temporary folder).
    public var wallpaperRoots = WallpaperScanner.defaultRoots
    private var dismissed: Set<String> = []
    private let fileURL: URL?

    /// Pass nil for an in-memory library (tests, previews).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        guard let fileURL else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        if let file = try? dec.decode(LibraryFile.self, from: data) {
            apply(file)
        } else if let legacy = try? dec.decode([PhotoItem].self, from: data) {
            items = legacy   // first version saved a bare array
        } else {
            _ = JSONFile.load(LibraryFile.self, from: fileURL)   // moves the unreadable file aside
        }
    }

    private func apply(_ f: LibraryFile) {
        items = f.items; folders = f.folders; albums = f.albums; dismissed = f.dismissed; lastSync = f.lastSync; filters = f.filters
        wallpapers = f.wallpapers
    }

    public var enabledItems: [PhotoItem] { items.filter(\.isEnabled) }
    public func item(_ id: UUID) -> PhotoItem? { items.first { $0.id == id } }
    public var activeSources: Set<String> {
        var s = Set(albums.map(\.id)).union(folders.map(\.id))
        if wallpapers != nil { s.insert(WallpaperScanner.sourceID) }
        return s
    }
    private var autoSources: Set<String> {
        var s = Set(albums.filter(\.autoInclude).map(\.id)).union(folders.filter(\.autoInclude).map(\.id))
        if wallpapers == true { s.insert(WallpaperScanner.sourceID) }
        return s
    }

    /// Turns the built-in macOS Wallpapers source on (everything included) or off (its photos leave).
    public func setWallpapers(_ on: Bool) {
        wallpapers = on ? true : nil
        applySync(listings: on ? [WallpaperScanner.sourceID: WallpaperScanner.scan(roots: wallpaperRoots)] : [:])
    }
    public var dismissedCount: Int { dismissed.count }

    /// Adds files by hand. A folder becomes a watched folder: its images are imported now and new ones are
    /// picked up on every sync. Duplicates are skipped. Returns how many photos were added.
    @discardableResult
    public func add(urls: [URL]) -> Int {
        let before = items.count
        var newFolders = false
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let std = url.standardizedFileURL
            if isDir.boolValue {
                if !folders.contains(where: { $0.path == std.path }) {
                    folders.append(FolderSource(path: std.path, bookmark: BookmarkStore.makeBookmark(for: std)))
                    newFolders = true
                }
            } else if ImageFiles.isSupported(std), !items.contains(where: { $0.path == std.path }) {
                dismissed.remove(std.path)
                items.append(PhotoItem(bookmark: BookmarkStore.makeBookmark(for: std), path: std.path))
            }
        }
        if newFolders { syncFoldersNow() }
        save()
        return items.count - before
    }

    /// Rescans watched folders on the calling thread and applies the result.
    public func syncFoldersNow() {
        var listings: [String: [SyncEntry]] = [:]
        for f in folders { if let l = FolderScanner.scan(f) { listings[f.id] = l } }
        if wallpapers != nil { listings[WallpaperScanner.sourceID] = WallpaperScanner.scan(roots: wallpaperRoots) }
        applySync(listings: listings)
    }

    /// Applies fresh scan results for the active sources: adds new photos, drops vanished ones.
    public func applySync(listings: [String: [SyncEntry]], markSynced: Bool = false) {
        let states = items.map { SyncItemState(id: $0.id, key: $0.key, sources: $0.sources, isManual: $0.isManual) }
        let plan = SyncPlanner.plan(items: states, activeSources: activeSources, listings: listings, dismissed: dismissed)
        if !plan.removals.isEmpty { items.removeAll { plan.removals.contains($0.id) } }
        for i in items.indices { if let s = plan.sourceUpdates[items[i].id] { items[i].sources = s } }
        let auto = autoSources
        for (entry, sources) in plan.adds {
            let on = !sources.isDisjoint(with: auto)   // photos new to a partly-selected album are listed but off
            if entry.isAsset {
                items.append(PhotoItem(path: "", isEnabled: on, assetID: entry.key, title: entry.name, isManual: false, sources: sources))
            } else {
                let url = URL(fileURLWithPath: entry.key)
                items.append(PhotoItem(bookmark: BookmarkStore.makeBookmark(for: url), path: entry.key, isEnabled: on, isManual: false, sources: sources))
            }
        }
        if markSynced { lastSync = Date() }
        save()
    }

    /// Replaces the chosen albums. Photos only in removed albums disappear right away; newly chosen albums
    /// need a scan (the caller follows with `applySync`).
    public func setAlbums(_ new: [AlbumRef]) {
        albums = new
        applySync(listings: [:])
    }

    public func removeFolder(_ id: String) {
        folders.removeAll { $0.id == id }
        applySync(listings: [:])
    }

    // MARK: Per-source selection (album and folder cards)

    /// Source id for photos added one by one.
    public static let manualSource = "manual"

    public func itemIDs(in source: String) -> [UUID] {
        source == Self.manualSource ? items.filter(\.isManual).map(\.id) : items.filter { $0.sources.contains(source) }.map(\.id)
    }

    public func selectionState(in source: String) -> SelectionState {
        let members = source == Self.manualSource ? items.filter(\.isManual) : items.filter { $0.sources.contains(source) }
        return SelectionState(selected: members.filter(\.isEnabled).count, total: members.count)
    }

    public func autoInclude(_ source: String) -> Bool {
        if source == WallpaperScanner.sourceID { return wallpapers == true }
        return albums.first { $0.id == source }?.autoInclude ?? folders.first { $0.id == source }?.autoInclude ?? false
    }

    private func setAuto(_ source: String, _ value: Bool) {
        if source == WallpaperScanner.sourceID, wallpapers != nil { wallpapers = value }
        if let i = albums.firstIndex(where: { $0.id == source }) { albums[i].autoInclude = value }
        if let i = folders.firstIndex(where: { $0.id == source }) { folders[i].autoInclude = value }
    }

    /// Flip only the "include new photos automatically" flag, leaving the current selection alone.
    public func setAutoInclude(_ source: String, _ value: Bool) { setAuto(source, value); save() }

    /// Whole-source toggles: everything in, and new photos follow; or everything out.
    public func selectAll(in source: String) {
        setEnabledQuiet(true, itemIDs(in: source)); setAuto(source, true); save()
    }

    public func deselectAll(in source: String) {
        setEnabledQuiet(false, itemIDs(in: source)); setAuto(source, false); save()
    }

    public func invertSelection(in source: String) {
        let ids = Set(itemIDs(in: source))
        for i in items.indices where ids.contains(items[i].id) { items[i].isEnabled.toggle() }
        setAuto(source, false); save()
    }

    /// Picking specific photos turns a source into a partial one: new photos in it are no longer auto-included.
    public func setSelected(_ ids: [UUID], _ on: Bool, in source: String) {
        setEnabledQuiet(on, ids); setAuto(source, false); save()
    }

    public func toggle(_ id: UUID, in source: String) {
        guard let it = item(id) else { return }
        setSelected([id], !it.isEnabled, in: source)
    }

    /// Starts tracking an album with nothing selected, so its photos can be browsed and picked.
    public func trackAlbum(_ ref: AlbumRef) {
        guard !albums.contains(where: { $0.localID == ref.localID }) else { return }
        var r = ref; r.autoInclude = false
        albums.append(r)
        save()
    }

    /// Stops tracking an album that ended up with nothing selected (e.g. it was only opened to look).
    public func untrackIfUnused(_ source: String) {
        guard source.hasPrefix("album:"), !autoInclude(source), selectionState(in: source) == .none else { return }
        albums.removeAll { $0.id == source }
        applySync(listings: [:])
    }

    private func setEnabledQuiet(_ on: Bool, _ ids: [UUID]) {
        let set = Set(ids)
        for i in items.indices where set.contains(items[i].id) { items[i].isEnabled = on }
    }

    /// Forget photos the user removed by hand, so the next sync can bring them back.
    public func resetDismissed() { dismissed = []; save() }

    public func remove(ids: Set<UUID>) {
        for item in items where ids.contains(item.id) && !item.sources.isEmpty { dismissed.insert(item.key) }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    public func setEnabled(_ enabled: Bool, ids: Set<UUID>? = nil) {
        for i in items.indices where ids == nil || ids!.contains(items[i].id) { items[i].isEnabled = enabled }
        save()
    }

    public func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isEnabled.toggle()
        save()
    }

    /// Drops file entries whose files no longer exist and whose bookmarks cannot find them either.
    @discardableResult
    public func removeMissing() -> Int {
        let missing = Set(items.filter { !$0.isAsset && BookmarkStore.resolve(bookmark: $0.bookmark, fallbackPath: $0.path) == nil }.map(\.id))
        if !missing.isEmpty { remove(ids: missing) }
        return missing.count
    }

    /// Finds the file for a file item, following moves via its bookmark and remembering the new location.
    public func resolveURL(for id: UUID) -> URL? {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].isAsset,
              let r = BookmarkStore.resolve(bookmark: items[i].bookmark, fallbackPath: items[i].path) else { return nil }
        var changed = false
        if r.url.path != items[i].path {
            items[i].path = r.url.path
            changed = true
        }
        if let fresh = r.refreshedBookmark { items[i].bookmark = fresh; changed = true }
        if changed { save() }
        return r.url
    }

    private func save() {
        guard let fileURL else { return }
        var f = LibraryFile()
        f.items = items; f.folders = folders; f.albums = albums; f.dismissed = dismissed; f.lastSync = lastSync; f.filters = filters
        f.wallpapers = wallpapers
        JSONFile.save(f, to: fileURL)
    }
}
