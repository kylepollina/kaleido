import Foundation

/// What comes on screen next. A scene is a photo with a pattern; saved scenes are ones you kept, new scenes are
/// a fresh photo with an invented pattern (or the one on screen, with Surprise me off).
public enum SceneShuffle: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, saved, mixed, new
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .off: return "Off (stay on this scene)"
        case .saved: return "Saved scenes"
        case .mixed: return "Saved and new scenes"
        case .new: return "New scenes only"
        }
    }

    /// How often a saved scene comes up when saved and new scenes are mixed.
    public static let savedShareWhenMixed = 0.15

    /// Whether the next scene is one of the saved (hearted) ones.
    public func nextIsSaved(savedCount: Int, roll: Double) -> Bool {
        guard savedCount > 0 else { return false }
        switch self {
        case .saved: return true
        case .mixed: return roll < Self.savedShareWhenMixed
        case .off, .new: return false
        }
    }
}

/// How the view zooms, for every scene. Infinite zooms loop seamlessly (each doubling cross-fades into the next).
/// Push and Pull keep sliding the photo through the mirrors one way or the other. Whether that reads as zooming in
/// or out depends on the pattern, hence the neutral names. Drift leaves only the look's own drift and gentle zoom breathing.
public enum ZoomMotion: String, Codable, CaseIterable, Identifiable, Sendable {
    case drift, push, pull
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .drift: return "Drift"
        case .push: return "Push"
        case .pull: return "Pull"
        }
    }
    /// +1 push, -1 pull, 0 neither.
    public var direction: Int {
        switch self {
        case .push: return 1
        case .pull: return -1
        case .drift: return 0
        }
    }

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "push", "zoomIn": self = .push
        case "pull", "zoomOut": self = .pull
        default: self = .drift   // "drift", the old "still" and "breathe", or anything unknown
        }
    }
}

/// How many pixels the desktop is drawn at. Fewer pixels, scaled up smoothly by the system, keep the Mac cooler;
/// soft, slow photos lose very little.
public enum Sharpness: String, Codable, CaseIterable, Identifiable, Sendable {
    case full, balanced, light
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .full: return "Full (Retina)"
        case .balanced: return "Balanced"
        case .light: return "Light (coolest)"
        }
    }
    /// Fraction of the display's Retina pixel density to draw at.
    public var fraction: Double {
        switch self {
        case .full: return 1
        case .balanced: return 0.75
        case .light: return 0.5
        }
    }
}

public struct Settings: Codable, Equatable, Sendable {
    /// 5 = scene shuffling. 4 = speed is a 5-stop global control and looks carry no speed of their own.
    /// 3 = barely-moving ranges, 2 = calm ranges. Older files (no version) had much faster ranges and are
    /// migrated on load.
    public static let currentVersion = 5

    /// The five stops of the speed slider (turtle to rabbit), as multipliers on every motion speed.
    /// Rabbit is eight times the turtle. Even steps on a log scale in between.
    public static let speedMultipliers: [Double] = [2, 3.36, 5.66, 9.51, 16]
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
    /// While playing, stop the display from going to sleep on its own (a screensaver-style keep-awake).
    public var keepScreenAwake = false
    /// 0...4, an index into `speedMultipliers`.
    public var speedStep = Settings.defaultSpeedStep
    /// Movement, on top of any look: how the view zooms.
    public var zoomMotion: ZoomMotion = .drift
    /// Desktop drawing resolution (the preview always draws sharp).
    public var sharpness: Sharpness = .balanced
    /// Surprise me: as scenes change, mix saved scenes with brand-new ones (a photo with an invented pattern).
    /// Off: play through the saved scenes (or, with none saved, the photos with the pattern on screen).
    public var surprise = true
    /// The scene shuffle Surprise me stands for. New scenes get an invented pattern when it is on, and keep the
    /// pattern on screen when it is off.
    public var effectiveSceneShuffle: SceneShuffle { surprise ? .mixed : .saved }
    public var sceneShuffle: SceneShuffle = .mixed
    /// Shapes invented patterns may not use (e.g. Diamonds, if you don't like it).
    public var excludedShapes: [MirrorMode] = []
    public var inventedShapes: Set<MirrorMode> { Set(MirrorMode.allCases).subtracting(excludedShapes) }
    // Global switches that win over any look, scene or Surprise me.
    public var allowHueChanges = true
    public var allowSaturationChanges = true
    public var allowVignette = true
    public var allowSwirl = true
    public var allowDynamicMirrors = true
    public var allowOutlines = true

    /// The Settings > Effects switches as one value, to notice when any of them changes.
    public var effectSwitches: [Bool] {
        [allowHueChanges, allowSaturationChanges, allowVignette, allowSwirl, allowDynamicMirrors, allowOutlines]
    }

    public init() {}

    public var speedMultiplier: Double { Settings.speedMultipliers[min(max(speedStep, 0), Settings.speedMultipliers.count - 1)] }

    /// The look the renderer should actually use: the chosen look with the global switches and speed applied.
    public func effectiveLook(_ l: Look) -> Look {
        var r = l
        if !allowHueChanges { r.hueShift = 0; r.hueSpeed = 0 }
        if !allowSaturationChanges { r.saturation = 1 }
        if !allowVignette { r.vignette = 0 }
        if !allowSwirl { r.twist = 0 }
        if !allowDynamicMirrors { r.dynamicMirrors = false }
        if !allowOutlines { r.outline = 0 }
        if zoomMotion != .drift { r.breathing = 0 }
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
        keepScreenAwake = try c.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? d.keepScreenAwake
        speedStep = try c.decodeIfPresent(Int.self, forKey: .speedStep) ?? d.speedStep
        zoomMotion = (try? c.decodeIfPresent(ZoomMotion.self, forKey: .zoomMotion)) ?? d.zoomMotion
        surprise = try c.decodeIfPresent(Bool.self, forKey: .surprise) ?? d.surprise
        sharpness = (try? c.decodeIfPresent(Sharpness.self, forKey: .sharpness)) ?? d.sharpness
        sceneShuffle = (try? c.decodeIfPresent(SceneShuffle.self, forKey: .sceneShuffle)) ?? d.sceneShuffle
        excludedShapes = (try? c.decodeIfPresent([MirrorMode].self, forKey: .excludedShapes)) ?? []
        allowHueChanges = try c.decodeIfPresent(Bool.self, forKey: .allowHueChanges) ?? true
        allowSaturationChanges = try c.decodeIfPresent(Bool.self, forKey: .allowSaturationChanges) ?? true
        allowVignette = try c.decodeIfPresent(Bool.self, forKey: .allowVignette) ?? true
        allowSwirl = try c.decodeIfPresent(Bool.self, forKey: .allowSwirl) ?? true
        allowDynamicMirrors = try c.decodeIfPresent(Bool.self, forKey: .allowDynamicMirrors) ?? true
        allowOutlines = try c.decodeIfPresent(Bool.self, forKey: .allowOutlines) ?? true
        if fileVersion < 5 {
            // Pattern shuffling became scene shuffling: keep showing new photos.
            sceneShuffle = .new
        }
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

    /// Desktop drawing resolution, as a fraction of Retina: Low Power Mode (when limited) always draws Light.
    public func effectiveSharpness(lowPowerMode: Bool) -> Double {
        (limitInLowPowerMode && lowPowerMode) ? Sharpness.light.fraction : sharpness.fraction
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
    public static var scenesFile: URL { dataDirectory.appendingPathComponent("scenes.json") }
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
