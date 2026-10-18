import Combine
import Foundation

public struct PhotoItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var bookmark: Data?
    public var path: String
    public var isEnabled: Bool
    public var addedAt: Date

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
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

/// The user's curated photo list. Items are references (bookmark + path), never copies.
public final class PhotoLibrary: ObservableObject {
    @Published public private(set) var items: [PhotoItem] = []
    private let fileURL: URL?

    /// Pass nil for an in-memory library (tests, previews).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let loaded = JSONFile.load([PhotoItem].self, from: fileURL) { items = loaded }
    }

    public var enabledItems: [PhotoItem] { items.filter(\.isEnabled) }
    public func item(_ id: UUID) -> PhotoItem? { items.first { $0.id == id } }

    /// Adds files (and the image files inside folders). Duplicates by path are skipped.
    /// Returns how many were added.
    @discardableResult
    public func add(urls: [URL]) -> Int {
        var existing = Set(items.map(\.path))
        var added = 0
        for url in ImageFiles.collect(from: urls) {
            let std = url.standardizedFileURL
            guard existing.insert(std.path).inserted else { continue }
            items.append(PhotoItem(id: UUID(), bookmark: BookmarkStore.makeBookmark(for: std), path: std.path, isEnabled: true, addedAt: Date()))
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    public func remove(ids: Set<UUID>) {
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

    /// Drops entries whose files no longer exist and whose bookmarks cannot find them either.
    @discardableResult
    public func removeMissing() -> Int {
        let missing = Set(items.filter { BookmarkStore.resolve(bookmark: $0.bookmark, fallbackPath: $0.path) == nil }.map(\.id))
        if !missing.isEmpty { remove(ids: missing) }
        return missing.count
    }

    /// Finds the file for an item, following moves via its bookmark and remembering the new location.
    public func resolveURL(for id: UUID) -> URL? {
        guard let i = items.firstIndex(where: { $0.id == id }),
              let r = BookmarkStore.resolve(bookmark: items[i].bookmark, fallbackPath: items[i].path) else { return nil }
        var changed = false
        if r.url.path != items[i].path { items[i].path = r.url.path; changed = true }
        if let fresh = r.refreshedBookmark { items[i].bookmark = fresh; changed = true }
        if changed { save() }
        return r.url
    }

    private func save() {
        if let fileURL { JSONFile.save(items, to: fileURL) }
    }
}
