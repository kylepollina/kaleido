import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import KaleidoCore

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kaleido-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writePNG(_ url: URL) {
    let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

final class PhotoQueueTests: XCTestCase {
    func testShuffleShowsEveryPhotoOncePerRound() {
        let q = PhotoQueue<Int>(shuffle: true, seed: 1)
        let ids = Array(0..<10)
        var current: Int?
        for _ in 0..<5 {
            var seen: [Int] = []
            for _ in ids {
                current = q.next(from: ids, current: current)
                seen.append(current!)
            }
            XCTAssertEqual(Set(seen), Set(ids))
        }
    }

    func testNeverRepeatsImmediately() {
        for seed in 0..<50 {
            let q = PhotoQueue<Int>(shuffle: true, seed: UInt64(seed))
            var current: Int?
            for _ in 0..<60 {
                let n = q.next(from: [1, 2, 3], current: current)
                XCTAssertNotEqual(n, current)
                current = n
            }
        }
    }

    func testSequentialWrapsInOrder() {
        let q = PhotoQueue<Int>(shuffle: false, seed: 1)
        XCTAssertEqual(q.next(from: [5, 6, 7], current: nil), 5)
        XCTAssertEqual(q.next(from: [5, 6, 7], current: 5), 6)
        XCTAssertEqual(q.next(from: [5, 6, 7], current: 7), 5)
        XCTAssertEqual(q.next(from: [5, 6, 7], current: 99), 5, "unknown current starts over")
    }

    func testEmptyAndSingle() {
        let q = PhotoQueue<Int>(shuffle: true, seed: 1)
        XCTAssertNil(q.next(from: [], current: nil))
        XCTAssertEqual(q.next(from: [4], current: 4), 4)
    }

    func testDisabledPhotosDropOutAndNewOnesJoin() {
        let q = PhotoQueue<Int>(shuffle: true, seed: 7)
        var current = q.next(from: [1, 2, 3, 4], current: nil)
        for _ in 0..<20 {
            current = q.next(from: [2, 3, 9], current: current)
            XCTAssertTrue([2, 3, 9].contains(current!))
        }
    }

    func testSeededShuffleIsDeterministic() {
        func run() -> [Int] {
            let q = PhotoQueue<Int>(shuffle: true, seed: 42)
            var cur: Int?
            return (0..<12).map { _ in cur = q.next(from: Array(0..<6), current: cur); return cur! }
        }
        XCTAssertEqual(run(), run())
    }
}

final class SettingsTests: XCTestCase {
    func testRoundTrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        var s = Settings()
        s.look.mode = .hex
        s.look.segments = 11
        s.look.hueSpeed = 0.3
        s.secondsPerPhoto = 42
        s.shuffle = false
        s.transition = .iris
        s.frameRate = 60
        JSONFile.save(s, to: file)
        XCTAssertEqual(JSONFile.load(Settings.self, from: file), s)
    }

    func testMissingKeysUseDefaultsAndValuesAreClamped() throws {
        let json = #"{"version": 3, "secondsPerPhoto": 0.1, "look": {"segments": 500, "mode": "fractal"}, "frameRate": 45}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.secondsPerPhoto, 10)
        XCTAssertEqual(s.look.segments, 24)
        XCTAssertEqual(s.look.mode, .fractal)
        XCTAssertEqual(s.frameRate, 30)
        XCTAssertEqual(s.look.zoom, Look().zoom)
        XCTAssertTrue(s.shuffle)
    }

    func testOldSettingsAreMigratedToCalmSpeeds() throws {
        let old = #"{"secondsPerPhoto": 20, "transitionSeconds": 2.5, "shuffle": false, "look": {"mode": "hex", "segments": 9, "rotationSpeed": 30, "driftSpeed": 3, "hueSpeed": 20, "twist": 1.5, "saturation": 1.3}}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(old.utf8))
        let d = Settings()
        XCTAssertEqual(s.version, Settings.currentVersion)
        XCTAssertEqual(s.look.rotationSpeed, d.look.rotationSpeed)
        XCTAssertEqual(s.look.driftSpeed, d.look.driftSpeed)
        XCTAssertEqual(s.look.hueSpeed, 0)
        XCTAssertEqual(s.look.twist, 0)
        XCTAssertEqual(s.transitionSeconds, d.transitionSeconds)
        XCTAssertEqual(s.secondsPerPhoto, d.secondsPerPhoto)
        XCTAssertEqual(s.look.mode, .hex, "non-speed choices survive")
        XCTAssertEqual(s.look.segments, 9)
        XCTAssertFalse(s.shuffle)
        XCTAssertEqual(s.look.saturation, 1.3)
    }

    func testCurrentSettingsAreNotMigratedAgain() throws {
        var s = Settings()
        s.look.rotationSpeed = 0.4
        s.secondsPerPhoto = 15
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(back.look.rotationSpeed, 0.4)
        XCTAssertEqual(back.secondsPerPhoto, 15)
    }

    func testDefaultsAndMaximumsAreBarelyMoving() {
        let s = Settings()
        XCTAssertLessThanOrEqual(abs(s.look.rotationSpeed), 0.1, "slower than a turn per hour")
        XCTAssertLessThanOrEqual(s.look.driftSpeed, 0.1)
        XCTAssertEqual(s.look.hueSpeed, 0)
        XCTAssertGreaterThanOrEqual(s.transitionSeconds, 10)
        XCTAssertEqual(s.look.segments, 12, "defaults follow the slow mandala look")
        var wild = Look()
        wild.rotationSpeed = 500; wild.hueSpeed = 500; wild.driftSpeed = 99; wild.twist = 9; wild.motion = 50
        wild.clamp()
        XCTAssertEqual(wild.rotationSpeed, 0.6); XCTAssertEqual(wild.hueSpeed, 0.6)
        XCTAssertEqual(wild.driftSpeed, 0.5); XCTAssertEqual(wild.twist, 1); XCTAssertEqual(wild.motion, 2)
        for p in Preset.all { XCTAssertLessThanOrEqual(abs(p.look.rotationSpeed), 0.15, p.name); XCTAssertLessThanOrEqual(p.look.driftSpeed, 0.15, p.name); XCTAssertLessThanOrEqual(p.look.hueSpeed, 0.2, p.name) }
        var g = SplitMix64(seed: 9)
        for _ in 0..<300 {
            let l = Look.random(using: &g)
            XCTAssertLessThanOrEqual(abs(l.rotationSpeed), 0.15); XCTAssertLessThanOrEqual(l.hueSpeed, 0.2); XCTAssertLessThanOrEqual(l.driftSpeed, 0.15)
        }
    }

    func testVersionTwoSettingsAreMigratedAgain() throws {
        let v2 = #"{"version": 2, "secondsPerPhoto": 45, "transitionSeconds": 6, "look": {"rotationSpeed": 0.4, "driftSpeed": 0.3, "hueSpeed": 1, "segments": 7}}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(v2.utf8))
        XCTAssertEqual(s.version, 3)
        XCTAssertEqual(s.look.rotationSpeed, Look().rotationSpeed)
        XCTAssertEqual(s.look.driftSpeed, Look().driftSpeed)
        XCTAssertEqual(s.look.hueSpeed, 0)
        XCTAssertEqual(s.transitionSeconds, 12)
        XCTAssertEqual(s.secondsPerPhoto, 90)
        XCTAssertEqual(s.look.segments, 7)
    }

    func testCorruptFileIsMovedAsideAndReportedAsMissing() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        try! Data("{not json".utf8).write(to: file)
        XCTAssertNil(JSONFile.load(Settings.self, from: file))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.corrupt.json").path))
    }

    func testLowPowerModeCapsFrameRate() {
        var s = Settings()
        s.frameRate = 60
        XCTAssertEqual(s.effectiveFrameRate(lowPowerMode: false), 60)
        XCTAssertEqual(s.effectiveFrameRate(lowPowerMode: true), 30)
        s.limitInLowPowerMode = false
        XCTAssertEqual(s.effectiveFrameRate(lowPowerMode: true), 60)
    }

    func testRandomLooksStayInRange() {
        var g = SplitMix64(seed: 3)
        for _ in 0..<500 {
            var l = Look.random(using: &g)
            let before = l
            l.clamp()
            XCTAssertEqual(l, before)
        }
    }

    func testPresetsAreValidAndUnique() {
        XCTAssertEqual(Set(Preset.all.map(\.name)).count, Preset.all.count)
        for p in Preset.all {
            var l = p.look
            l.clamp()
            XCTAssertEqual(l, p.look)
        }
    }

    func testEasingMovesTowardTargetAndSnapsDiscreteValues() {
        var a = Look(); a.zoom = 1; a.rotationSpeed = 0; a.segments = 4; a.mode = .radial
        var b = Look(); b.zoom = 4; b.rotationSpeed = 10; b.segments = 12; b.mode = .hex
        let half = a.eased(toward: b, by: 0.5)
        XCTAssertEqual(half.zoom, 2, accuracy: 1e-9, "zoom eases geometrically")
        XCTAssertEqual(half.rotationSpeed, 5, accuracy: 1e-9)
        XCTAssertEqual(half.segments, 12)
        XCTAssertEqual(half.mode, .hex)
        XCTAssertEqual(a.eased(toward: b, by: 1).zoom, 4, accuracy: 1e-9)
    }
}

final class BookmarkAndLibraryTests: XCTestCase {
    func testBookmarkFollowsRenamedFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.png")
        writePNG(original)
        let bookmark = BookmarkStore.makeBookmark(for: original)
        XCTAssertNotNil(bookmark)

        let moved = dir.appendingPathComponent("renamed.png")
        try FileManager.default.moveItem(at: original, to: moved)
        let resolved = BookmarkStore.resolve(bookmark: bookmark, fallbackPath: original.path)
        XCTAssertEqual(resolved?.url.resolvingSymlinksInPath().path, moved.resolvingSymlinksInPath().path)
    }

    func testResolveFallsBackToPathAndFailsWhenGone() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.png")
        writePNG(file)
        XCTAssertEqual(BookmarkStore.resolve(bookmark: nil, fallbackPath: file.path)?.url.path, file.path)
        XCTAssertEqual(BookmarkStore.resolve(bookmark: Data([1, 2, 3]), fallbackPath: file.path)?.url.path, file.path, "garbage bookmark falls back to the path")
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(BookmarkStore.resolve(bookmark: nil, fallbackPath: file.path))
    }

    func testAddFilesAndFoldersFiltersAndDedupes() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        writePNG(dir.appendingPathComponent("one.png"))
        writePNG(sub.appendingPathComponent("two.PNG"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        try Data("x".utf8).write(to: dir.appendingPathComponent(".hidden.png"))

        let lib = PhotoLibrary(fileURL: nil)
        XCTAssertEqual(lib.add(urls: [dir]), 2)
        XCTAssertEqual(lib.add(urls: [dir, dir.appendingPathComponent("one.png")]), 0, "duplicates are skipped")
        XCTAssertEqual(lib.add(urls: [dir.appendingPathComponent("notes.txt")]), 0)
        XCTAssertEqual(lib.items.count, 2)
    }

    func testPersistenceKeepsSelectionAndSurvivesMoves() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.png"), b = dir.appendingPathComponent("b.png")
        writePNG(a); writePNG(b)
        let store = dir.appendingPathComponent("library.json")

        let lib = PhotoLibrary(fileURL: store)
        lib.add(urls: [a, b])
        let idB = lib.items.first { $0.name == "b.png" }!.id
        lib.toggle(idB)
        XCTAssertEqual(lib.enabledItems.map(\.name), ["a.png"])

        let reloaded = PhotoLibrary(fileURL: store)
        XCTAssertEqual(reloaded.items, lib.items)
        XCTAssertEqual(reloaded.enabledItems.map(\.name), ["a.png"])

        let renamed = dir.appendingPathComponent("a2.png")
        try FileManager.default.moveItem(at: a, to: renamed)
        let idA = reloaded.items.first { $0.name == "a.png" }!.id
        let url = reloaded.resolveURL(for: idA)
        XCTAssertEqual(url?.lastPathComponent, "a2.png")
        XCTAssertEqual(reloaded.item(idA)?.name, "a2.png", "new location is remembered")
    }

    func testEnableDisableRemoveAndMissing() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.png"), b = dir.appendingPathComponent("b.png")
        writePNG(a); writePNG(b)
        let lib = PhotoLibrary(fileURL: nil)
        lib.add(urls: [a, b])
        lib.setEnabled(false)
        XCTAssertTrue(lib.enabledItems.isEmpty)
        lib.setEnabled(true, ids: [lib.items[0].id])
        XCTAssertEqual(lib.enabledItems.count, 1)

        try FileManager.default.removeItem(at: b)
        XCTAssertEqual(lib.removeMissing(), 1)
        XCTAssertEqual(lib.items.count, 1)
        lib.remove(ids: Set(lib.items.map(\.id)))
        XCTAssertTrue(lib.items.isEmpty)
    }
}

final class SliderScaleTests: XCTestCase {
    func testLogScaleRoundTripsAndIsFineAtTheSlowEnd() {
        let s = SliderScale.log(0.02, 1.5)
        XCTAssertEqual(s.value(at: 0), 0.02, accuracy: 1e-12)
        XCTAssertEqual(s.value(at: 1), 1.5, accuracy: 1e-12)
        XCTAssertLessThan(s.value(at: 0.5), 0.3, "half the slider is still calm")
        for v in [0.02, 0.1, 0.3, 1.0, 1.5] { XCTAssertEqual(s.value(at: s.position(for: v)), v, accuracy: 1e-9) }
    }

    func testSignedLogHasZeroInTheMiddleAndIsSymmetric() {
        let s = SliderScale.signedLog(min: 0.02, max: 3)
        XCTAssertEqual(s.value(at: 0.5), 0)
        XCTAssertEqual(s.value(at: 0), -3, accuracy: 1e-9)
        XCTAssertEqual(s.value(at: 1), 3, accuracy: 1e-9)
        XCTAssertEqual(s.value(at: 0.3), -s.value(at: 0.7), accuracy: 1e-9)
        XCTAssertEqual(s.position(for: 0), 0.5)
        for v in [-3.0, -0.4, -0.02, 0.02, 0.4, 3.0] { XCTAssertEqual(s.value(at: s.position(for: v)), v, accuracy: 1e-9) }
        var last = -Double.infinity
        for i in 0...100 { let v = s.value(at: Double(i) / 100); XCTAssertGreaterThanOrEqual(v, last); last = v }
    }

    func testZeroLogIsStillAtZeroAndFineNearTheSlowEnd() {
        let s = SliderScale.zeroLog(min: 0.05, max: 2)
        XCTAssertEqual(s.value(at: 0), 0)
        XCTAssertEqual(s.value(at: 0.03), 0)
        XCTAssertEqual(s.value(at: 1), 2, accuracy: 1e-9)
        XCTAssertLessThan(s.value(at: 0.5), 0.4)
        XCTAssertEqual(s.position(for: 0), 0)
        for v in [0.05, 0.3, 1.0, 2.0] { XCTAssertEqual(s.value(at: s.position(for: v)), v, accuracy: 1e-9) }
    }

    func testLinearClamps() {
        let s = SliderScale.linear(2, 4)
        XCTAssertEqual(s.value(at: -1), 2); XCTAssertEqual(s.value(at: 9), 4); XCTAssertEqual(s.position(for: 3), 0.5)
    }
}

final class SyncTests: XCTestCase {
    private func e(_ k: String, asset: Bool = true) -> SyncEntry { SyncEntry(key: k, name: k, isAsset: asset) }
    private func st(_ k: String, _ sources: Set<String> = [], manual: Bool = false) -> SyncItemState {
        SyncItemState(id: UUID(), key: k, sources: sources, isManual: manual)
    }

    func testAddsNewAndRemovesVanished() {
        let a = st("a", ["album:1"]), b = st("b", ["album:1"])
        let plan = SyncPlanner.plan(items: [a, b], activeSources: ["album:1"], listings: ["album:1": [e("b"), e("c")]], dismissed: [])
        XCTAssertEqual(plan.removals, [a.id])
        XCTAssertEqual(plan.adds.map(\.entry.key), ["c"])
        XCTAssertTrue(plan.sourceUpdates.isEmpty)
    }

    func testManualPhotosSurviveAndDismissedStayGone() {
        let m = st("m", [], manual: true)
        let plan = SyncPlanner.plan(items: [m], activeSources: ["album:1"], listings: ["album:1": [e("x"), e("y")]], dismissed: ["x"])
        XCTAssertTrue(plan.removals.isEmpty)
        XCTAssertEqual(plan.adds.map(\.entry.key), ["y"])
    }

    func testDeselectedSourceDropsItsPhotosButKeepsSharedOnes() {
        let only = st("only", ["album:1"]), both = st("both", ["album:1", "album:2"])
        let plan = SyncPlanner.plan(items: [only, both], activeSources: ["album:2"], listings: [:], dismissed: [])
        XCTAssertEqual(plan.removals, [only.id])
        XCTAssertEqual(plan.sourceUpdates[both.id], ["album:2"])
    }

    func testFailedScanLeavesSourceUntouched() {
        let a = st("a", ["album:1"])
        let plan = SyncPlanner.plan(items: [a], activeSources: ["album:1"], listings: [:], dismissed: [])
        XCTAssertTrue(plan.isEmpty, "no listing means no change, not an empty album")
    }

    func testPhotoInTwoAlbumsIsAddedOnceAndExistingGainsSource() {
        let have = st("h", ["album:1"])
        let plan = SyncPlanner.plan(items: [have], activeSources: ["album:1", "album:2"],
                                    listings: ["album:1": [e("h"), e("n")], "album:2": [e("h"), e("n")]], dismissed: [])
        XCTAssertEqual(plan.adds.count, 1)
        XCTAssertEqual(plan.adds[0].sources, ["album:1", "album:2"])
        XCTAssertEqual(plan.sourceUpdates[have.id], ["album:1", "album:2"])
    }

    func testIsIdempotent() {
        let items = [st("a", ["album:1"])]
        let plan = SyncPlanner.plan(items: items, activeSources: ["album:1"], listings: ["album:1": [e("a")]], dismissed: [])
        XCTAssertTrue(plan.isEmpty)
    }
}

final class SourcePersistenceTests: XCTestCase {
    func testAlbumSelectionAssetsAndFiltersPersist() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("library.json")
        let lib = PhotoLibrary(fileURL: store)
        lib.setAlbums([AlbumRef(localID: "A1", title: "Favorites"), AlbumRef(localID: "A2", title: "Trip")])
        lib.applySync(listings: ["album:A1": [SyncEntry(key: "asset-1", name: "IMG_1", isAsset: true), SyncEntry(key: "asset-2", name: "IMG_2", isAsset: true)],
                                 "album:A2": [SyncEntry(key: "asset-2", name: "IMG_2", isAsset: true)]], markSynced: true)
        lib.filters.minLongEdge = 2400
        lib.filters.excludeScreenshots = false

        let back = PhotoLibrary(fileURL: store)
        XCTAssertEqual(back.albums.map(\.title), ["Favorites", "Trip"])
        XCTAssertEqual(back.items.count, 2)
        XCTAssertTrue(back.items.allSatisfy { $0.isAsset && !$0.isManual })
        XCTAssertEqual(back.items.first { $0.assetID == "asset-2" }?.sources, ["album:A1", "album:A2"])
        XCTAssertNotNil(back.lastSync)
        XCTAssertEqual(back.filters.minLongEdge, 2400)
        XCTAssertFalse(back.filters.excludeScreenshots)

        back.setAlbums([AlbumRef(localID: "A2", title: "Trip")])
        XCTAssertEqual(back.items.map { $0.assetID }, ["asset-2"], "photos only in the deselected album go")
    }

    func testRemovingAnAutoPhotoKeepsItGoneAcrossSyncs() {
        let lib = PhotoLibrary(fileURL: nil)
        lib.setAlbums([AlbumRef(localID: "A", title: "A")])
        let listing = ["album:A": [SyncEntry(key: "x", name: "x", isAsset: true), SyncEntry(key: "y", name: "y", isAsset: true)]]
        lib.applySync(listings: listing)
        lib.remove(ids: [lib.items.first { $0.assetID == "x" }!.id])
        lib.applySync(listings: listing)
        XCTAssertEqual(lib.items.map { $0.assetID }, ["y"])
        lib.resetDismissed()
        lib.applySync(listings: listing)
        XCTAssertEqual(Set(lib.items.compactMap { $0.assetID }), ["x", "y"])
    }

    func testWatchedFolderPicksUpNewFilesAndDropsDeletedOnes() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let photos = dir.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        writePNG(photos.appendingPathComponent("1.png"))
        let lib = PhotoLibrary(fileURL: dir.appendingPathComponent("library.json"))
        lib.add(urls: [photos])
        XCTAssertEqual(lib.items.count, 1)
        XCTAssertEqual(lib.folders.count, 1)

        writePNG(photos.appendingPathComponent("2.png"))
        try FileManager.default.removeItem(at: photos.appendingPathComponent("1.png"))
        lib.syncFoldersNow()
        XCTAssertEqual(lib.items.map(\.name), ["2.png"])

        let handAdded = dir.appendingPathComponent("solo.png")
        writePNG(handAdded)
        lib.add(urls: [handAdded])
        lib.removeFolder(lib.folders[0].id)
        XCTAssertEqual(lib.items.map(\.name), ["solo.png"], "hand-added photo stays when its folder is unwatched")
    }

    func testLegacyLibraryFileStillLoads() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.json")
        let legacy = [PhotoItem(path: "/tmp/a.jpg"), PhotoItem(path: "/tmp/b.jpg", isEnabled: false)]
        try JSONEncoder().encode(legacy).write(to: file)
        let lib = PhotoLibrary(fileURL: file)
        XCTAssertEqual(lib.items.map(\.path), ["/tmp/a.jpg", "/tmp/b.jpg"])
        XCTAssertTrue(lib.items.allSatisfy(\.isManual))
        XCTAssertEqual(lib.enabledItems.count, 1)
    }
}

final class SelectionTests: XCTestCase {
    private func entries(_ keys: String...) -> [SyncEntry] { keys.map { SyncEntry(key: $0, name: $0, isAsset: true) } }

    func testNewPhotosFollowWholeAlbumsButNotPartialOnes() {
        let lib = PhotoLibrary(fileURL: nil)
        lib.setAlbums([AlbumRef(localID: "W", title: "Whole"), AlbumRef(localID: "P", title: "Partial", autoInclude: false)])
        lib.applySync(listings: ["album:W": entries("w1", "w2"), "album:P": entries("p1", "p2")])
        XCTAssertEqual(lib.selectionState(in: "album:W"), .all(total: 2))
        XCTAssertEqual(lib.selectionState(in: "album:P"), .none)

        lib.setSelected([lib.items.first { $0.assetID == "p1" }!.id], true, in: "album:P")
        XCTAssertEqual(lib.selectionState(in: "album:P"), .partial(selected: 1, total: 2))
        lib.applySync(listings: ["album:W": entries("w1", "w2", "w3"), "album:P": entries("p1", "p2", "p3")])
        XCTAssertEqual(lib.items.first { $0.assetID == "w3" }?.isEnabled, true, "whole album takes new photos")
        XCTAssertEqual(lib.items.first { $0.assetID == "p3" }?.isEnabled, false, "partial album lists them but leaves them out")
        XCTAssertEqual(lib.selectionState(in: "album:P"), .partial(selected: 1, total: 3))
    }

    func testSelectAllDeselectAllInvertAndAutoFlag() {
        let lib = PhotoLibrary(fileURL: nil)
        lib.setAlbums([AlbumRef(localID: "A", title: "A", autoInclude: false)])
        lib.applySync(listings: ["album:A": entries("a", "b", "c", "d")])
        XCTAssertFalse(lib.autoInclude("album:A"))
        lib.selectAll(in: "album:A")
        XCTAssertEqual(lib.selectionState(in: "album:A"), .all(total: 4))
        XCTAssertTrue(lib.autoInclude("album:A"))
        lib.toggle(lib.itemIDs(in: "album:A")[0], in: "album:A")
        XCTAssertEqual(lib.selectionState(in: "album:A"), .partial(selected: 3, total: 4))
        XCTAssertFalse(lib.autoInclude("album:A"), "picking by hand makes it partial")
        lib.invertSelection(in: "album:A")
        XCTAssertEqual(lib.selectionState(in: "album:A"), .partial(selected: 1, total: 4))
        lib.deselectAll(in: "album:A")
        XCTAssertEqual(lib.selectionState(in: "album:A"), .none)
        XCTAssertTrue(lib.enabledItems.isEmpty)
    }

    func testOpeningAnAlbumTracksItAndLeavingUntracksIfNothingPicked() {
        let lib = PhotoLibrary(fileURL: nil)
        lib.trackAlbum(AlbumRef(localID: "X", title: "X"))
        XCTAssertEqual(lib.albums.count, 1)
        XCTAssertFalse(lib.autoInclude("album:X"), "tracking to browse selects nothing")
        lib.applySync(listings: ["album:X": entries("1", "2")])
        XCTAssertEqual(lib.items.count, 2)
        XCTAssertTrue(lib.enabledItems.isEmpty)
        lib.untrackIfUnused("album:X")
        XCTAssertTrue(lib.albums.isEmpty)
        XCTAssertTrue(lib.items.isEmpty)

        lib.trackAlbum(AlbumRef(localID: "Y", title: "Y"))
        lib.applySync(listings: ["album:Y": entries("1")])
        lib.selectAll(in: "album:Y")
        lib.untrackIfUnused("album:Y")
        XCTAssertEqual(lib.albums.count, 1, "an album with picks stays")
    }

    func testSelectionPersistsAndOldAlbumsDefaultToWhole() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("library.json")
        let lib = PhotoLibrary(fileURL: store)
        lib.trackAlbum(AlbumRef(localID: "P", title: "P"))
        lib.applySync(listings: ["album:P": entries("1", "2", "3")])
        lib.setSelected([lib.items[0].id, lib.items[2].id], true, in: "album:P")
        let back = PhotoLibrary(fileURL: store)
        XCTAssertEqual(back.selectionState(in: "album:P"), .partial(selected: 2, total: 3))
        XCTAssertFalse(back.autoInclude("album:P"))

        let old = try JSONDecoder().decode(AlbumRef.self, from: Data(#"{"localID":"Z","title":"Z"}"#.utf8))
        XCTAssertTrue(old.autoInclude)
        let oldFolder = try JSONDecoder().decode(FolderSource.self, from: Data(#"{"path":"/tmp/x"}"#.utf8))
        XCTAssertTrue(oldFolder.autoInclude)
    }

    func testRangeSelectionAndStates() {
        let order = [1, 2, 3, 4, 5, 6]
        XCTAssertEqual(RangeSelection.ids(in: order, from: 2, to: 5), [2, 3, 4, 5])
        XCTAssertEqual(RangeSelection.ids(in: order, from: 5, to: 2), [2, 3, 4, 5])
        XCTAssertEqual(RangeSelection.ids(in: order, from: 3, to: 3), [3])
        XCTAssertEqual(RangeSelection.ids(in: order, from: 99, to: 4), [4])
        XCTAssertEqual(SelectionState(selected: 0, total: 5), .none)
        XCTAssertEqual(SelectionState(selected: 5, total: 5), .all(total: 5))
        XCTAssertEqual(SelectionState(selected: 2, total: 5), .partial(selected: 2, total: 5))
        XCTAssertEqual(SelectionState(selected: 0, total: 0), .none)
    }

    func testManualSourceSelection() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.png"), b = dir.appendingPathComponent("b.png")
        writePNG(a); writePNG(b)
        let lib = PhotoLibrary(fileURL: nil)
        lib.add(urls: [a, b])
        XCTAssertEqual(lib.selectionState(in: PhotoLibrary.manualSource), .all(total: 2))
        lib.deselectAll(in: PhotoLibrary.manualSource)
        XCTAssertEqual(lib.selectionState(in: PhotoLibrary.manualSource), .none)
    }
}
