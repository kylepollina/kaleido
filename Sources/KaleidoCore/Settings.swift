import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var look = Look()
    public var secondsPerPhoto: Double = 20
    public var shuffle = true
    public var transition: TransitionStyle = .random
    public var transitionSeconds: Double = 2.5
    /// 30 or 60.
    public var frameRate: Int = 30
    public var pauseOnBattery = false
    /// Drops to 30 fps and stops the 60 fps option while macOS Low Power Mode is on.
    public var limitInLowPowerMode = true
    public var playOnLaunch = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        look = try c.decodeIfPresent(Look.self, forKey: .look) ?? d.look
        secondsPerPhoto = try c.decodeIfPresent(Double.self, forKey: .secondsPerPhoto) ?? d.secondsPerPhoto
        shuffle = try c.decodeIfPresent(Bool.self, forKey: .shuffle) ?? d.shuffle
        transition = try c.decodeIfPresent(TransitionStyle.self, forKey: .transition) ?? d.transition
        transitionSeconds = try c.decodeIfPresent(Double.self, forKey: .transitionSeconds) ?? d.transitionSeconds
        frameRate = try c.decodeIfPresent(Int.self, forKey: .frameRate) ?? d.frameRate
        pauseOnBattery = try c.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? d.pauseOnBattery
        limitInLowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .limitInLowPowerMode) ?? d.limitInLowPowerMode
        playOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .playOnLaunch) ?? d.playOnLaunch
        clamp()
    }

    public mutating func clamp() {
        secondsPerPhoto = min(max(secondsPerPhoto, 2), 3600)
        transitionSeconds = min(max(transitionSeconds, 0.2), 10)
        frameRate = frameRate >= 60 ? 60 : 30
        look.clamp()
    }

    /// The rate to actually render at, given system conditions.
    public func effectiveFrameRate(lowPowerMode: Bool) -> Int {
        (limitInLowPowerMode && lowPowerMode) ? 30 : frameRate
    }
}

/// Where app data lives. `KALEIDO_DATA_DIR` overrides it so test runs never touch the real library.
public enum Paths {
    public static var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["KALEIDO_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kaleido", isDirectory: true)
    }
    public static var settingsFile: URL { dataDirectory.appendingPathComponent("settings.json") }
    public static var libraryFile: URL { dataDirectory.appendingPathComponent("library.json") }
}

public enum JSONFile {
    /// Returns nil when the file is missing or unreadable; a corrupt file is moved aside so it is not lost.
    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("Kaleido: could not save \(url.lastPathComponent): \(error)")
        }
    }
}
