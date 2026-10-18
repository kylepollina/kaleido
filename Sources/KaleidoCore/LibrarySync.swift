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
