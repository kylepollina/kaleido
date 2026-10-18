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
        s.look.hueSpeed = 7.5
        s.secondsPerPhoto = 42
        s.shuffle = false
        s.transition = .iris
        s.frameRate = 60
        JSONFile.save(s, to: file)
        XCTAssertEqual(JSONFile.load(Settings.self, from: file), s)
    }

    func testMissingKeysUseDefaultsAndValuesAreClamped() throws {
        let json = #"{"secondsPerPhoto": 0.1, "look": {"segments": 500, "mode": "fractal"}, "frameRate": 45}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.secondsPerPhoto, 2)
        XCTAssertEqual(s.look.segments, 24)
        XCTAssertEqual(s.look.mode, .fractal)
        XCTAssertEqual(s.frameRate, 30)
        XCTAssertEqual(s.look.zoom, Look().zoom)
        XCTAssertTrue(s.shuffle)
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
