import Foundation

public struct ResolvedFile: Equatable {
    public var url: URL
    /// A fresh bookmark when the old one was stale (the file moved or was renamed), else nil.
    public var refreshedBookmark: Data?
}

/// Security-scoped bookmarks with a plain-path fallback. Bookmarks keep following a file when it is
/// moved or renamed (and are what a sandboxed build would need); the path covers bookmark failures.
public enum BookmarkStore {
    public static func makeBookmark(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public static func resolve(bookmark: Data?, fallbackPath: String) -> ResolvedFile? {
        if let bookmark {
            for options: URL.BookmarkResolutionOptions in [[.withSecurityScope, .withoutUI], [.withoutUI]] {
                var stale = false
                guard let url = try? URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale),
                      FileManager.default.fileExists(atPath: url.path)
                else { continue }
                return ResolvedFile(url: url, refreshedBookmark: stale ? makeBookmark(for: url) : nil)
            }
        }
        let url = URL(fileURLWithPath: fallbackPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return ResolvedFile(url: url, refreshedBookmark: bookmark == nil ? makeBookmark(for: url) : nil)
    }

    /// Runs `body` with security-scoped access to `url` (a harmless no-op outside the sandbox).
    public static func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}
