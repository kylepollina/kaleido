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

/// Where scenes come from as they change (an album playing is a third mode, chosen in Photos, that isn't saved).
public enum PlaySource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// All the selected photos, with saved scenes popping in now and then, always in random order.
    case discover
    /// The saved scenes as a playlist, in the Scenes list's order or shuffled.
    case scenes
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .discover: return "Discover"
        case .scenes: return "My scenes"
        }
    }

    public init(from decoder: Decoder) throws {
        self = PlaySource(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .discover
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
    /// 6 = speed and zoom belong to each scene's look. 5 = scene shuffling. 4 = speed is a 5-stop global control and looks carry no speed of their own.
    /// 3 = barely-moving ranges, 2 = calm ranges. Older files (no version) had much faster ranges and are
    /// migrated on load.
    public static let currentVersion = 6

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
    /// What `Look.superSlow` plays at.
    public static let superSlowMultiplier = 0.25
    public static let superSlowVideoRate: Float = 0.125
    /// Desktop drawing resolution (the preview always draws sharp).
    public var sharpness: Sharpness = .balanced
    /// Random patterns (the dice in the mini-player): every scene that comes up gets an invented pattern, a saved
    /// scene's photo included (the saved pattern is left as it is). Off: saved scenes show their own pattern and
    /// other photos keep the one on screen. Stored under its old name, "surprise".
    public var surprise = true
    /// Where scenes come from: Discover or My scenes.
    public var playSource: PlaySource = .discover
    public var sceneShuffle: SceneShuffle = .mixed
    /// Shapes invented patterns may not use (e.g. Diamonds, if you don't like it).
    public var excludedShapes: [MirrorMode] = []
    public var inventedShapes: Set<MirrorMode> { Set(MirrorMode.allCases).subtracting(excludedShapes) }
    /// Albums and sources hidden from Photos (right-click > Hide), by source id. Hidden only from view: their
    /// selected photos still play.
    public var hiddenAlbums: [String] = []
    /// Photos lists hidden albums too (dimmed), to bring one back.
    public var showHiddenAlbums = false
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

    /// The multiplier on every movement for a look: its own speed stop, or the tortoise's fixed crawl.
    public func speedMultiplier(for l: Look) -> Double {
        l.superSlow ? Settings.superSlowMultiplier : Settings.speedMultipliers[min(max(l.speedStep, 0), Settings.speedMultipliers.count - 1)]
    }

    /// The look the renderer should actually use: the chosen look with the global switches and speed applied.
    public func effectiveLook(_ l: Look) -> Look {
        var r = l
        if !allowHueChanges { r.hueShift = 0; r.hueSpeed = 0 }
        if !allowSaturationChanges { r.saturation = 1 }
        if !allowVignette { r.vignette = 0 }
        if !allowSwirl { r.twist = 0 }
        if !allowDynamicMirrors { r.dynamicMirrors = false }
        if !allowOutlines { r.outline = 0 }
        if l.zoomMotion != .drift { r.breathing = 0 }
        r.motion = l.motion * speedMultiplier(for: l)
        return r
    }

    private enum LegacyKeys: String, CodingKey { case speedStep, zoomMotion }

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
        surprise = try c.decodeIfPresent(Bool.self, forKey: .surprise) ?? d.surprise
        playSource = (try? c.decodeIfPresent(PlaySource.self, forKey: .playSource)) ?? d.playSource
        sharpness = (try? c.decodeIfPresent(Sharpness.self, forKey: .sharpness)) ?? d.sharpness
        sceneShuffle = (try? c.decodeIfPresent(SceneShuffle.self, forKey: .sceneShuffle)) ?? d.sceneShuffle
        excludedShapes = (try? c.decodeIfPresent([MirrorMode].self, forKey: .excludedShapes)) ?? []
        hiddenAlbums = (try? c.decodeIfPresent([String].self, forKey: .hiddenAlbums)) ?? []
        showHiddenAlbums = (try? c.decodeIfPresent(Bool.self, forKey: .showHiddenAlbums)) ?? false
        allowHueChanges = try c.decodeIfPresent(Bool.self, forKey: .allowHueChanges) ?? true
        allowSaturationChanges = try c.decodeIfPresent(Bool.self, forKey: .allowSaturationChanges) ?? true
        allowVignette = try c.decodeIfPresent(Bool.self, forKey: .allowVignette) ?? true
        allowSwirl = try c.decodeIfPresent(Bool.self, forKey: .allowSwirl) ?? true
        allowDynamicMirrors = try c.decodeIfPresent(Bool.self, forKey: .allowDynamicMirrors) ?? true
        allowOutlines = try c.decodeIfPresent(Bool.self, forKey: .allowOutlines) ?? true
        if fileVersion < 6 {
            // Speed and zoom used to be global; they now live in the look (and so in each scene).
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let step = try? legacy.decodeIfPresent(Int.self, forKey: .speedStep) { look.speedStep = step }
            if let zoom = try? legacy.decodeIfPresent(ZoomMotion.self, forKey: .zoomMotion) { look.zoomMotion = zoom }
        }
        if fileVersion < 5 {
            // Pattern shuffling became scene shuffling: keep showing new photos.
            sceneShuffle = .new
        }
        if fileVersion < 4 {
            // Speed moved from each look's "Motion" slider to the global 5-stop control.
            look.motion = 1
            look.speedStep = d.look.speedStep
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
    /// Aerial videos Kaleido downloaded itself (macOS's own aerials folder is only read).
    public static var aerialDownloads: URL { dataDirectory.appendingPathComponent("Aerials", isDirectory: true) }
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
