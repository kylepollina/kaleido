import Foundation

/// One photo as seen by a source scan: a file path or a Photos asset identifier.
public struct SyncEntry: Equatable, Sendable {
    public var key: String
    public var name: String
    public var isAsset: Bool
    public init(key: String, name: String, isAsset: Bool) { self.key = key; self.name = name; self.isAsset = isAsset }
}

public struct SyncItemState: Sendable {
    public var id: UUID
    public var key: String
    public var sources: Set<String>
    public var isManual: Bool
    public init(id: UUID, key: String, sources: Set<String>, isManual: Bool) {
        self.id = id; self.key = key; self.sources = sources; self.isManual = isManual
    }
}

public struct SyncPlan: Equatable {
    public var adds: [(entry: SyncEntry, sources: Set<String>)] = []
    public var sourceUpdates: [UUID: Set<String>] = [:]
    public var removals: Set<UUID> = []

    public static func == (a: SyncPlan, b: SyncPlan) -> Bool {
        a.sourceUpdates == b.sourceUpdates && a.removals == b.removals
            && a.adds.map(\.entry) == b.adds.map(\.entry) && a.adds.map(\.sources) == b.adds.map(\.sources)
    }
    public var isEmpty: Bool { adds.isEmpty && sourceUpdates.isEmpty && removals.isEmpty }
}

public enum SyncPlanner {
    /// Works out what a sync changes.
    /// - `activeSources`: sources (albums, folders) the user currently wants.
    /// - `listings`: fresh contents of sources that were scanned successfully. An active source missing from
    ///   `listings` (scan failed, permission lapsed) is left alone rather than emptied.
    /// - `dismissed`: keys the user removed by hand; they are not re-added.
    /// Photos added by hand (`isManual`) are never removed. Auto-added ones go away when no source lists them.
    public static func plan(items: [SyncItemState], activeSources: Set<String>, listings: [String: [SyncEntry]], dismissed: Set<String>) -> SyncPlan {
        var plan = SyncPlan()
        var listed: [String: Set<String>] = [:]   // source -> keys
        for (source, entries) in listings where activeSources.contains(source) { listed[source] = Set(entries.map(\.key)) }

        for item in items {
            var next = Set<String>()
            for source in item.sources where activeSources.contains(source) {
                if let keys = listed[source] { if keys.contains(item.key) { next.insert(source) } } else { next.insert(source) }
            }
            // Pick up sources that now list a photo we already have.
            for (source, keys) in listed where keys.contains(item.key) { next.insert(source) }
            if next.isEmpty && !item.isManual { plan.removals.insert(item.id); continue }
            if next != item.sources { plan.sourceUpdates[item.id] = next }
        }

        let have = Set(items.map(\.key))
        var added: [String: (SyncEntry, Set<String>)] = [:]
        var order: [String] = []
        for source in listed.keys.sorted() {
            for entry in listings[source] ?? [] where !have.contains(entry.key) && !dismissed.contains(entry.key) {
                if added[entry.key] == nil { order.append(entry.key); added[entry.key] = (entry, [source]) } else { added[entry.key]!.1.insert(source) }
            }
        }
        plan.adds = order.map { (added[$0]!.0, added[$0]!.1) }
        return plan
    }
}

public struct FolderSource: Codable, Identifiable, Hashable, Sendable {
    public var path: String
    public var bookmark: Data?
    /// "Whole folder": new photos that appear in it are included in the rotation automatically.
    public var autoInclude: Bool
    public var id: String { "folder:" + path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public init(path: String, bookmark: Data?, autoInclude: Bool = true) { self.path = path; self.bookmark = bookmark; self.autoInclude = autoInclude }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        autoInclude = try c.decodeIfPresent(Bool.self, forKey: .autoInclude) ?? true
    }
}

public struct AlbumRef: Codable, Identifiable, Hashable, Sendable {
    public var localID: String
    public var title: String
    /// "Whole album": new photos that appear in it are included in the rotation automatically. When false the
    /// user picked specific photos and new ones are listed but not included.
    public var autoInclude: Bool
    public var id: String { "album:" + localID }
    public init(localID: String, title: String, autoInclude: Bool = true) { self.localID = localID; self.title = title; self.autoInclude = autoInclude }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        localID = try c.decode(String.self, forKey: .localID)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        autoInclude = try c.decodeIfPresent(Bool.self, forKey: .autoInclude) ?? true
    }
}

public enum SelectionState: Equatable, Sendable {
    case none, partial(selected: Int, total: Int), all(total: Int)

    public init(selected: Int, total: Int) {
        if selected <= 0 { self = .none } else if selected >= total { self = .all(total: total) } else { self = .partial(selected: selected, total: total) }
    }
}

public enum RangeSelection {
    /// Ids between two clicked positions, inclusive, in display order (for shift-click).
    public static func ids<ID>(in order: [ID], from anchor: ID, to target: ID) -> [ID] where ID: Equatable {
        guard let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: target) else { return [target] }
        return Array(order[min(a, b)...max(a, b)])
    }
}

public struct PhotoFilters: Codable, Equatable, Sendable {
    public var excludeScreenshots = true
    /// Skip photos whose longest side is below this many pixels (0 = keep everything).
    public var minLongEdge = 1600
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        excludeScreenshots = try c.decodeIfPresent(Bool.self, forKey: .excludeScreenshots) ?? true
        minLongEdge = try c.decodeIfPresent(Int.self, forKey: .minLongEdge) ?? 1600
    }
}

public enum FolderScanner {
    /// Image files inside a folder source, or nil if the folder cannot be found or read right now.
    public static func scan(_ folder: FolderSource) -> [SyncEntry]? {
        guard let resolved = BookmarkStore.resolve(bookmark: folder.bookmark, fallbackPath: folder.path) else { return nil }
        let url = resolved.url
        return BookmarkStore.withAccess(to: url) {
            guard (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil else { return nil }
            return ImageFiles.collect(from: [url]).map { SyncEntry(key: $0.standardizedFileURL.path, name: $0.lastPathComponent, isAsset: false) }
        }
    }
}

/// The built-in "macOS Aerials" source: the slow-motion aerial videos (landscapes, cities, underwater, space)
/// that macOS has downloaded for its moving wallpapers and screen saver. Only what is already on disk is used;
/// more arrive when you pick them in System Settings > Wallpaper.
public enum AerialScanner {
    public static let sourceID = "aerials"

    public static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")

    /// Downloaded aerial videos, named from Apple's manifest ("Yosemite", "London", ...): the ones macOS downloaded,
    /// plus any Kaleido downloaded itself into `downloads` (its own folder; macOS's is never written to).
    public static func scan(root: URL = defaultRoot, downloads: URL? = nil) -> [SyncEntry] {
        let fm = FileManager.default
        var files = (try? fm.contentsOfDirectory(at: root.appendingPathComponent("videos"), includingPropertiesForKeys: nil)) ?? []
        let systemIDs = Set(files.map(stem))
        if let downloads, let mine = try? fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil) {
            files += mine.filter { !systemIDs.contains(stem($0)) }   // macOS's own copy wins
        }
        let names = manifestNames(root: root)
        var used: [String: Int] = [:]
        return files.filter(VideoFiles.isVideo)
            .map { $0.standardizedFileURL }
            .sorted { (names[stem($0)] ?? "~").localizedStandardCompare(names[stem($1)] ?? "~") == .orderedAscending }
            .map { url in
                var name = names[stem(url)] ?? "Aerial"
                used[name, default: 0] += 1
                if used[name]! > 1 { name += " \(used[name]!)" }   // several shots share a place name
                return SyncEntry(key: url.path, name: name, isAsset: false)
            }
    }

    /// Apple's own still for a video, if it has one.
    public static func thumbnail(for video: URL, root: URL = defaultRoot) -> URL? {
        let url = root.appendingPathComponent("thumbnails/\(stem(video)).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func stem(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    /// One aerial in Apple's catalogue, downloaded or not.
    public struct CatalogEntry: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        /// Apple's copy of the video (4K, SDR).
        public let remote: URL
        /// A still: Apple's local thumbnail when macOS has one, else its web preview.
        public let localThumbnail: URL?
        public let previewImage: URL?
        public let isDownloaded: Bool
    }

    /// Every aerial in Apple's manifest, sorted by place name, marking the ones already on this Mac.
    public static func catalog(root: URL = defaultRoot, downloads: URL? = nil) -> [CatalogEntry] {
        struct Manifest: Decodable {
            struct Asset: Decodable {
                let id: String
                let accessibilityLabel: String?
                let previewImage: String?
                let url: String?
                enum CodingKeys: String, CodingKey { case id, accessibilityLabel, previewImage, url = "url-4K-SDR-240FPS" }
            }
            let assets: [Asset]
        }
        guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest/entries.json")),
              let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        let have = Set(scan(root: root, downloads: downloads).map { stem(URL(fileURLWithPath: $0.key)) })
        let fm = FileManager.default
        var used: [String: Int] = [:]
        return m.assets
            .compactMap { a -> (Manifest.Asset, URL)? in a.url.flatMap(URL.init(string:)).map { (a, $0) } }
            .sorted { ($0.0.accessibilityLabel ?? "~").localizedStandardCompare($1.0.accessibilityLabel ?? "~") == .orderedAscending }
            .map { a, remote in
                var name = a.accessibilityLabel.flatMap { $0.isEmpty ? nil : $0 } ?? "Aerial"
                used[name, default: 0] += 1
                if used[name]! > 1 { name += " \(used[name]!)" }
                let thumb = root.appendingPathComponent("thumbnails/\(a.id).png")
                return CatalogEntry(id: a.id, name: name, remote: remote,
                                    localThumbnail: fm.fileExists(atPath: thumb.path) ? thumb : nil,
                                    previewImage: a.previewImage.flatMap(URL.init(string:)),
                                    isDownloaded: have.contains(a.id))
            }
    }

    /// Video id to place name, from manifest/entries.json.
    static func manifestNames(root: URL) -> [String: String] {
        struct Manifest: Decodable {
            struct Asset: Decodable { let id: String; let accessibilityLabel: String? }
            let assets: [Asset]
        }
        guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest/entries.json")),
              let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return [:] }
        var out: [String: String] = [:]
        for a in m.assets { if let label = a.accessibilityLabel, !label.isEmpty { out[a.id] = label } }
        return out
    }
}

/// The built-in "macOS Wallpapers" source: Apple's desktop pictures that are actually on disk.
/// Most scenic ones (Big Sur, Catalina, The Lake...) are only stubs until downloaded in System Settings >
/// Wallpaper; once downloaded they land in the MobileAsset folder and are picked up on the next sync.
public enum WallpaperScanner {
    public static let sourceID = "wallpapers"

    public static let defaultRoots: [URL] = [
        URL(fileURLWithPath: "/System/Library/Desktop Pictures"),
        URL(fileURLWithPath: "/Library/Desktop Pictures"),
        URL(fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture"),
    ]

    /// Image files under the roots, skipping the plain "Solid Colors" swatches and hidden thumbnails.
    public static func scan(roots: [URL] = defaultRoots) -> [SyncEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [SyncEntry] = []
        for root in roots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            var found: [URL] = []
            for case let url as URL in e {
                if url.lastPathComponent == "Solid Colors" || url.pathExtension == "madesktop" { e.skipDescendants(); continue }
                if ImageFiles.isSupported(url) { found.append(url.standardizedFileURL) }
            }
            for url in found.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
            where seen.insert(url.path).inserted {
                out.append(SyncEntry(key: url.path, name: url.deletingPathExtension().lastPathComponent, isAsset: false))
            }
        }
        return out
    }
}
