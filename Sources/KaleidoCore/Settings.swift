import Foundation

/// Whether the slideshow switches between hearted presets, and how often.
public enum LookShuffle: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, sometimes, everyPhoto
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .off: return "Off"
        case .sometimes: return "Every 4 photos"
        case .everyPhoto: return "Every photo"
        }
    }
    /// Photos between look changes during automatic playback (nil = never).
    public var interval: Int? {
        switch self {
        case .off: return nil
        case .sometimes: return 4
        case .everyPhoto: return 1
        }
    }
}

public struct Settings: Codable, Equatable, Sendable {
    /// 4 = speed is a 5-stop global control and looks carry no speed of their own. 3 = barely-moving ranges,
    /// 2 = calm ranges. Older files (no version) had much faster ranges and are migrated on load.
    public static let currentVersion = 4

    /// The five stops of the speed slider (turtle to rabbit), as multipliers on every motion speed.
    public static let speedMultipliers: [Double] = [0.25, 0.5, 1, 2, 4]
    public static let defaultSpeedStep = 2
    public var version = Settings.currentVersion
    public var look = Look()
    public var secondsPerPhoto: Double = 90
    public var shuffle = true
    public var transition: TransitionStyle = .random
    public var transitionSeconds: Double = 12
    /// 30 or 60.
    public var frameRate: Int = 30
    public var pauseOnBattery = false
    /// Drops to 30 fps and stops the 60 fps option while macOS Low Power Mode is on.
    public var limitInLowPowerMode = true
    public var playOnLaunch = false
    /// 0...4, an index into `speedMultipliers`.
    public var speedStep = Settings.defaultSpeedStep
    public var lookShuffle: LookShuffle = .sometimes
    /// The preset `look` came from (nil after Surprise me, which makes an unsaved look).
    public var activePresetID: UUID?
    // Global switches that win over any look, preset or Surprise me.
    public var allowHueChanges = true
    public var allowSaturationChanges = true
    public var allowBlur = true
    public var allowVignette = true
    public var allowSwirl = true

    public init() {}

    public var speedMultiplier: Double { Settings.speedMultipliers[min(max(speedStep, 0), Settings.speedMultipliers.count - 1)] }

    /// The look the renderer should actually use: the chosen look with the global switches and speed applied.
    public func effectiveLook(_ l: Look) -> Look {
        var r = l
        if !allowHueChanges { r.hueShift = 0; r.hueSpeed = 0 }
        if !allowSaturationChanges { r.saturation = 1 }
        if !allowBlur { r.blur = 0 }
        if !allowVignette { r.vignette = 0 }
        if !allowSwirl { r.twist = 0 }
        r.motion = l.motion * speedMultiplier
        return r
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        let fileVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        look = try c.decodeIfPresent(Look.self, forKey: .look) ?? d.look
        secondsPerPhoto = try c.decodeIfPresent(Double.self, forKey: .secondsPerPhoto) ?? d.secondsPerPhoto
        shuffle = try c.decodeIfPresent(Bool.self, forKey: .shuffle) ?? d.shuffle
        transition = try c.decodeIfPresent(TransitionStyle.self, forKey: .transition) ?? d.transition
        transitionSeconds = try c.decodeIfPresent(Double.self, forKey: .transitionSeconds) ?? d.transitionSeconds
        frameRate = try c.decodeIfPresent(Int.self, forKey: .frameRate) ?? d.frameRate
        pauseOnBattery = try c.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? d.pauseOnBattery
        limitInLowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .limitInLowPowerMode) ?? d.limitInLowPowerMode
        playOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .playOnLaunch) ?? d.playOnLaunch
        speedStep = try c.decodeIfPresent(Int.self, forKey: .speedStep) ?? d.speedStep
        lookShuffle = (try? c.decodeIfPresent(LookShuffle.self, forKey: .lookShuffle)) ?? d.lookShuffle
        activePresetID = try? c.decodeIfPresent(UUID.self, forKey: .activePresetID)
        allowHueChanges = try c.decodeIfPresent(Bool.self, forKey: .allowHueChanges) ?? true
        allowSaturationChanges = try c.decodeIfPresent(Bool.self, forKey: .allowSaturationChanges) ?? true
        allowBlur = try c.decodeIfPresent(Bool.self, forKey: .allowBlur) ?? true
        allowVignette = try c.decodeIfPresent(Bool.self, forKey: .allowVignette) ?? true
        allowSwirl = try c.decodeIfPresent(Bool.self, forKey: .allowSwirl) ?? true
        if fileVersion < 4 {
            // Speed moved from each look's "Motion" slider to the global 5-stop control.
            look.motion = 1
            speedStep = d.speedStep
        }
        if fileVersion < 3 {
            // The old ranges were far too lively. Reset every speed-like value to the calm defaults and keep
            // the rest of the user's choices (mode, mirrors, colors, shuffle, frame rate...).
            look.rotationSpeed = d.look.rotationSpeed
            look.driftSpeed = d.look.driftSpeed
            look.hueSpeed = 0
            look.twist = 0
            look.motion = 1
            look.breathing = d.look.breathing
            transitionSeconds = d.transitionSeconds
            if secondsPerPhoto <= 45 { secondsPerPhoto = d.secondsPerPhoto }
        }
        version = Settings.currentVersion
        clamp()
    }

    public mutating func clamp() {
        secondsPerPhoto = min(max(secondsPerPhoto, 10), 3600)
        transitionSeconds = min(max(transitionSeconds, 2), 30)
        frameRate = frameRate >= 60 ? 60 : 30
        speedStep = min(max(speedStep, 0), Settings.speedMultipliers.count - 1)
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
    public static var presetsFile: URL { dataDirectory.appendingPathComponent("presets.json") }
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
