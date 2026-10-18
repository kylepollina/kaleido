import AppKit
import KaleidoCore
import Photos
import os

struct AlbumInfo: Identifiable, Hashable {
    enum Group: String { case smart = "Smart albums", user = "My albums", shared = "Shared albums" }
    let localID: String
    let title: String
    let count: Int
    let group: Group
    var id: String { "album:" + localID }
    var ref: AlbumRef { AlbumRef(localID: localID, title: title) }
}

enum PhotosError: Error { case notFound, failed, timedOut }

/// PhotoKit access: permission, the album list, scans of chosen albums, and image loading.
/// Read-only; Kaleido never changes the Photos library.
@MainActor
final class PhotosService: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var status: PHAuthorizationStatus
    @Published private(set) var albums: [AlbumInfo] = []
    var onLibraryChange: (() -> Void)?
    private let log = Logger(subsystem: "local.kaleido.app", category: "photos")

    /// Per-album cap on how many photos are pulled in (most recent first), to keep huge libraries light.
    nonisolated static let albumCap = 3000

    override init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
        if isAuthorized {
            PHPhotoLibrary.shared().register(self)
            refreshAlbums()
        }
    }

    var isAuthorized: Bool { status == .authorized || status == .limited }

    func requestAccess() async {
        let was = isAuthorized
        let new = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = new
        log.info("photos authorization: \(new.rawValue)")
        if isAuthorized && !was {
            PHPhotoLibrary.shared().register(self)
            refreshAlbums()
            onLibraryChange?()
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.onLibraryChange?() }
    }

    func refreshAlbums() {
        guard isAuthorized else { albums = []; return }
        var out: [AlbumInfo] = []
        let imageOnly = PHFetchOptions()
        imageOnly.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        func collect(_ result: PHFetchResult<PHAssetCollection>, _ group: AlbumInfo.Group, skip: Set<PHAssetCollectionSubtype> = []) {
            result.enumerateObjects { c, _, _ in
                if skip.contains(c.assetCollectionSubtype) { return }
                let n = PHAsset.fetchAssets(in: c, options: imageOnly).count
                if n > 0 { out.append(AlbumInfo(localID: c.localIdentifier, title: c.localizedTitle ?? "Untitled", count: n, group: group)) }
            }
        }
        let skipSmart: Set<PHAssetCollectionSubtype> = [.smartAlbumVideos, .smartAlbumSlomoVideos, .smartAlbumTimelapses, .smartAlbumAllHidden, .smartAlbumScreenshots]
        collect(PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil), .smart, skip: skipSmart)
        collect(PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil), .user)
        collect(PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil), .shared)
        albums = out
    }

    // MARK: Scanning (callable from any thread)

    nonisolated static func listing(albumID: String, filters: PhotoFilters) -> [SyncEntry]? {
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else { return nil }
        var preds = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]
        if filters.excludeScreenshots {
            preds.append(NSPredicate(format: "(mediaSubtypes & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue))
        }
        if filters.minLongEdge > 0 {
            preds.append(NSPredicate(format: "(pixelWidth >= %d) OR (pixelHeight >= %d)", filters.minLongEdge, filters.minLongEdge))
        }
        let o = PHFetchOptions()
        o.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.fetchLimit = albumCap
        let result = PHAsset.fetchAssets(in: collection, options: o)
        var out: [SyncEntry] = []
        out.reserveCapacity(result.count)
        result.enumerateObjects { a, _, _ in out.append(SyncEntry(key: a.localIdentifier, name: "Photo", isAsset: true)) }
        return out
    }

    // MARK: Images

    /// A display-sized image for the renderer. Allows iCloud download; fails (never hangs) after 90 s.
    nonisolated static func image(assetID: String, maxDimension: CGFloat) async throws -> CGImage {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { throw PhotosError.notFound }
        return try await request(asset: asset, size: CGSize(width: maxDimension, height: maxDimension), mode: .highQualityFormat, timeout: 90)
    }

    nonisolated static func thumbnail(assetID: String, maxDimension: CGFloat = 360) async -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return nil }
        return try? await request(asset: asset, size: CGSize(width: maxDimension, height: maxDimension), mode: .opportunistic, timeout: 30)
    }

    private nonisolated static func request(asset: PHAsset, size: CGSize, mode: PHImageRequestOptionsDeliveryMode, timeout: Double) async throws -> CGImage {
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = true
        o.deliveryMode = mode
        o.resizeMode = .fast
        o.isSynchronous = false
        let state = RequestState()
        return try await withCheckedThrowingContinuation { cont in
            let rid = PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: o) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true && mode == .highQualityFormat { return }
                guard state.finish() else { return }
                if let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) { cont.resume(returning: cg) }
                else { cont.resume(throwing: PhotosError.failed) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard state.finish() else { return }
                PHImageManager.default().cancelImageRequest(rid)
                cont.resume(throwing: PhotosError.timedOut)
            }
        }
    }
}

private final class RequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    /// True the first time it is called.
    func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
