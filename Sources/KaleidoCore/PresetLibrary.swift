import Combine
import Foundation

/// A preset the user can edit. Built-in presets start out hearted; hearted presets are the ones shown on
/// Home and used when the slideshow shuffles presets.
public struct SavedPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var look: Look
    public var isFavorite: Bool
    /// What Reset goes back to: the factory look for built-ins, the look it was created with otherwise.
    public var originalLook: Look
    public var originalName: String
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, look: Look, isFavorite: Bool = true, isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.look = look; self.isFavorite = isFavorite
        self.originalLook = look; self.originalName = name; self.isBuiltIn = isBuiltIn
    }

    public var isModified: Bool { look != originalLook || name != originalName }
}

public final class PresetLibrary: ObservableObject {
    @Published public private(set) var presets: [SavedPreset] = []
    private let fileURL: URL?

    /// Pass nil for an in-memory library (tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let saved = JSONFile.load([SavedPreset].self, from: fileURL), !saved.isEmpty {
            presets = saved
            // Built-ins added in later versions show up for existing users too.
            let have = Set(saved.filter(\.isBuiltIn).map(\.originalName))
            for p in Preset.all where !have.contains(p.name) {
                presets.append(SavedPreset(name: p.name, look: p.look, isBuiltIn: true))
            }
        } else {
            presets = Preset.all.map { SavedPreset(name: $0.name, look: $0.look, isBuiltIn: true) }
        }
    }

    public var favorites: [SavedPreset] { presets.filter(\.isFavorite) }
    public func preset(_ id: UUID?) -> SavedPreset? { presets.first { $0.id == id } }

    public func update(_ id: UUID, look: Look) {
        guard let i = index(id), presets[i].look != look else { return }
        presets[i].look = look
        save()
    }

    public func rename(_ id: UUID, to name: String) {
        guard let i = index(id) else { return }
        presets[i].name = name
        save()
    }

    public func toggleFavorite(_ id: UUID) {
        guard let i = index(id) else { return }
        presets[i].isFavorite.toggle()
        save()
    }

    /// Back to the factory look (built-ins) or the look the preset was created with.
    public func reset(_ id: UUID) {
        guard let i = index(id) else { return }
        presets[i].look = presets[i].originalLook
        presets[i].name = presets[i].originalName
        save()
    }

    /// Adds a new preset (hearted) and returns its id.
    @discardableResult
    public func add(name: String, look: Look) -> UUID {
        let p = SavedPreset(name: uniqueName(name), look: look)
        presets.append(p)
        save()
        return p.id
    }

    @discardableResult
    public func duplicate(_ id: UUID) -> UUID? {
        guard let p = preset(id) else { return nil }
        return add(name: p.name + " copy", look: p.look)
    }

    /// Only presets the user made can be deleted; built-ins can be un-hearted instead.
    public func delete(_ id: UUID) {
        guard let p = preset(id), !p.isBuiltIn else { return }
        presets.removeAll { $0.id == id }
        save()
    }

    /// A hearted preset other than `current`, for shuffling. Falls back to all presets when none are hearted.
    public func randomFavorite<G: RandomNumberGenerator>(excluding current: UUID?, using g: inout G) -> SavedPreset? {
        let pool = favorites.isEmpty ? presets : favorites
        let choices = pool.filter { $0.id != current }
        return (choices.isEmpty ? pool : choices).randomElement(using: &g)
    }

    public func randomFavorite(excluding current: UUID?) -> SavedPreset? {
        var g = SystemRandomNumberGenerator()
        return randomFavorite(excluding: current, using: &g)
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(presets.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func index(_ id: UUID) -> Int? { presets.firstIndex { $0.id == id } }

    private func save() {
        if let fileURL { JSONFile.save(presets, to: fileURL) }
    }
}
