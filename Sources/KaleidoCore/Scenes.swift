import Combine
import Foundation

/// A scene: one photo frozen together with a look and where the photo sat inside the mirrors. Unlike a preset it
/// keeps its own copy of the look, so editing a preset later never changes a scene.
public struct SavedScene: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// The photo's id in the photo library.
    public var photoID: UUID
    public var look: Look
    /// How far the photo was dragged inside the mirrors (photo space).
    public var panX: Double
    public var panY: Double
    public var isFavorite: Bool
    public var created: Date

    public init(id: UUID = UUID(), name: String, photoID: UUID, look: Look, panX: Double = 0, panY: Double = 0,
                isFavorite: Bool = true, created: Date = Date()) {
        self.id = id; self.name = name; self.photoID = photoID; self.look = look
        self.panX = panX; self.panY = panY; self.isFavorite = isFavorite; self.created = created
    }
}

public final class SceneLibrary: ObservableObject {
    @Published public private(set) var scenes: [SavedScene] = []
    private let fileURL: URL?

    /// Pass nil for an in-memory library (tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let saved = JSONFile.load([SavedScene].self, from: fileURL) { scenes = saved }
    }

    public var favorites: [SavedScene] { scenes.filter(\.isFavorite) }
    public func scene(_ id: UUID?) -> SavedScene? { scenes.first { $0.id == id } }

    /// Adds a scene (hearted) and returns its id.
    @discardableResult
    public func add(name: String, photoID: UUID, look: Look, panX: Double = 0, panY: Double = 0) -> UUID {
        let s = SavedScene(name: uniqueName(name), photoID: photoID, look: look, panX: panX, panY: panY)
        scenes.append(s)
        save()
        return s.id
    }

    public func update(_ id: UUID, name: String, look: Look, pan: (Double, Double)?) {
        guard let i = index(id) else { return }
        scenes[i].name = name
        scenes[i].look = look
        if let pan { scenes[i].panX = pan.0; scenes[i].panY = pan.1 }
        save()
    }

    public func toggleFavorite(_ id: UUID) {
        guard let i = index(id) else { return }
        scenes[i].isFavorite.toggle()
        save()
    }

    @discardableResult
    public func duplicate(_ id: UUID) -> UUID? {
        guard let s = scene(id) else { return nil }
        return add(name: s.name + " copy", photoID: s.photoID, look: s.look, panX: s.panX, panY: s.panY)
    }

    public func delete(_ id: UUID) {
        scenes.removeAll { $0.id == id }
        save()
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(scenes.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func index(_ id: UUID) -> Int? { scenes.firstIndex { $0.id == id } }

    private func save() {
        if let fileURL { JSONFile.save(scenes, to: fileURL) }
    }
}

/// Unsaved edits to a preset or a scene. They show on screen right away, but nothing is written until Save;
/// leaving the editor throws them away.
public struct EditDraft: Equatable, Sendable {
    public enum Target: Equatable, Sendable { case preset(UUID), scene(UUID) }
    public let target: Target
    public var name: String
    public var look: Look
    public let savedName: String
    public let savedLook: Look
    /// The photo was dragged inside the mirrors (scenes keep where the photo sits).
    public var moved = false

    public init(target: Target, name: String, look: Look) {
        self.target = target
        self.name = name; self.look = look
        savedName = name; savedLook = look
    }

    public var hasChanges: Bool { name != savedName || look != savedLook || moved }
}
