import AppKit
import KaleidoCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home", photos = "Photos", presets = "Presets", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house"
        case .photos: return "photo.on.rectangle"
        case .presets: return "sparkles.rectangle.stack"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var section: AppSection? = .home

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 170, max: 200)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if section != .home { PlayButton(compact: true) }
                    Text(app.statusText).font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
            }
        } detail: {
            switch section ?? .home {
            case .home: HomeView(go: { section = $0 })
            case .photos: LibraryPane()
            case .presets: PresetsView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 640, idealHeight: 800)
        .onAppear {
            // The action stays valid after this window closes, so the app delegate can reopen it.
            let open = openWindow
            app.openMainWindow = { open(id: "main") }
        }
    }
}

struct PlayButton: View {
    @EnvironmentObject var app: AppState
    var compact = false

    var body: some View {
        Button {
            app.togglePlay()
        } label: {
            Label(app.isPlaying ? "Stop" : (compact ? "Play" : "Play on Desktop"), systemImage: app.isPlaying ? "stop.fill" : "play.fill")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(app.isPlaying ? .red : .accentColor)
        .keyboardShortcut("p", modifiers: .command)
    }
}

extension AppState {
    var statusText: String {
        if let r = suspensionReason, isPlaying { return "Paused: \(r.lowercased())" }
        if isPlaying { return "Playing on your desktop. Stop or quit to get your wallpaper back." }
        return "Your normal wallpaper is showing."
    }
}

// MARK: Home

struct HomeView: View {
    @EnvironmentObject var app: AppState
    let go: (AppSection) -> Void
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PreviewPane().frame(maxWidth: 760)
                transport
                let n = app.library.enabledItems.count
                if n == 0 {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text("No photos selected yet.")
                        Button("Choose photos…") { go(.photos) }
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button("\(n) photos in rotation") { go(.photos) }.buttonStyle(.link).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Presets").font(.headline)
                        Text("Your hearted presets").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Edit presets…") { go(.presets) }.buttonStyle(.link)
                    }
                    let favorites = app.presets.favorites
                    if favorites.isEmpty {
                        Text("Heart some presets in the Presets section to see them here.").foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(favorites) { p in PresetCard(preset: p) }
                        }
                    }
                }
                .frame(maxWidth: 760)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var transport: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Button { app.previousPhoto() } label: { Image(systemName: "backward.fill").frame(width: 30) }
                    .help("Previous photo")
                PlayButton().frame(width: 200)
                Button { app.nextPhoto() } label: { Image(systemName: "forward.fill").frame(width: 30) }
                    .help("Next photo (and another preset when Shuffle presets is on)")
                Button { app.surpriseMe() } label: { Label("Surprise me", systemImage: "dice") }
                    .help("A new photo with a random look")
            }
            .controlSize(.large)
            HStack(spacing: 28) {
                HStack(spacing: 8) {
                    Text("Speed").foregroundStyle(.secondary)
                    SpeedControl().frame(width: 220)
                }
                Toggle("Shuffle presets", isOn: Binding(
                    get: { app.settings.lookShuffle != .off },
                    set: { app.settings.lookShuffle = $0 ? .sometimes : .off }))
                    .toggleStyle(.switch)
                    .help("Switch between your hearted presets as the photos change. How often is in Settings.")
            }
        }
    }
}

/// The one speed control: five stops from turtle to rabbit, like the trackpad speed setting.
struct SpeedControl: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tortoise.fill").foregroundStyle(.secondary).help("Slowest")
            Slider(value: Binding(get: { Double(app.settings.speedStep) },
                                  set: { app.settings.speedStep = Int($0.rounded()) }),
                   in: 0...Double(Settings.speedMultipliers.count - 1), step: 1)
            Image(systemName: "hare.fill").foregroundStyle(.secondary).help("Fastest")
        }
    }
}

struct PresetCard: View {
    @EnvironmentObject var app: AppState
    let preset: SavedPreset

    var body: some View {
        let active = app.settings.activePresetID == preset.id
        Button { app.apply(preset) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(preset.look.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(active ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

extension Look {
    var summary: String { "\(mode.label), \(mode.countLabel.lowercased()) \(segments)" }
}

// MARK: Presets

struct PresetsView: View {
    @EnvironmentObject var app: AppState
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 240)
            Divider()
            if let id = selection ?? app.settings.activePresetID, let preset = app.presets.preset(id) {
                PresetEditor(preset: preset)
            } else {
                VStack(spacing: 10) {
                    Text("Pick a preset to edit it.").foregroundStyle(.secondary)
                    if app.settings.activePresetID == nil {
                        Button("Save the current look as a preset") { selection = app.saveCurrentAsPreset() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            app.isEditingPresets = true
            if selection == nil { selection = app.settings.activePresetID ?? app.presets.presets.first?.id }
        }
        .onDisappear { app.isEditingPresets = false }
        .onChange(of: selection) { _, id in if let p = app.presets.preset(id) { app.apply(p) } }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(app.presets.presets) { p in
                    HStack {
                        Button { app.presets.toggleFavorite(p.id) } label: {
                            Image(systemName: p.isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(p.isFavorite ? Color.pink : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(p.isFavorite ? "Shown on Home and used when shuffling" : "Heart to show it on Home and shuffle it")
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.name).lineLimit(1)
                            Text(p.isModified ? "Edited" : p.look.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(p.id)
                }
            }
            Divider()
            HStack(spacing: 4) {
                Button { selection = app.saveCurrentAsPreset() } label: { Image(systemName: "plus") }
                    .help("New preset from what's playing")
                Button { if let s = selection, let id = app.presets.duplicate(s) { selection = id } } label: { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate")
                    .disabled(selection == nil)
                Button {
                    if let s = selection { app.presets.delete(s); selection = app.presets.presets.first?.id }
                } label: { Image(systemName: "minus") }
                    .help("Delete (built-in presets can only be un-hearted)")
                    .disabled(app.presets.preset(selection)?.isBuiltIn ?? true)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }
}

struct PresetEditor: View {
    @EnvironmentObject var app: AppState
    let preset: SavedPreset

    var body: some View {
        VStack(spacing: 0) {
            PreviewPane(editor: true).frame(maxWidth: 480).padding(16)
            Form {
                Section {
                    TextField("Name", text: Binding(get: { preset.name }, set: { app.presets.rename(preset.id, to: $0) }))
                    HStack {
                        Toggle("Heart (show on Home, use when shuffling)", isOn: Binding(
                            get: { preset.isFavorite }, set: { _ in app.presets.toggleFavorite(preset.id) }))
                        Spacer()
                        Button("Reset") { app.resetPreset(preset.id) }
                            .disabled(!preset.isModified)
                            .help(preset.isBuiltIn ? "Back to the original preset" : "Back to how it was when you created it")
                    }
                }
                Section("Shape") {
                    Picker("Mirror mode", selection: bind(\.mode)) {
                        ForEach(MirrorMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    SliderRow(preset.look.mode.countLabel,
                              value: Binding(get: { Double(preset.look.segments) }, set: { v in app.edit(preset.id) { $0.segments = Int(v.rounded()) } }),
                              range: 2...24, step: 1) { "\(Int($0))" }
                    if preset.look.mode == .cubes {
                        Picker("Faces", selection: bind(\.checkerFaces)) {
                            Text("Checker").tag(true)
                            Text("Mirror").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .help("Checker: each diamond direction shows a different part of the photo. Mirror: every diamond is the same.")
                    }
                    Toggle("Dynamic mirrors (slowly change how many)", isOn: bind(\.dynamicMirrors))
                        .disabled(!app.settings.allowDynamicMirrors)
                    if preset.look.dynamicMirrors {
                        LabeledContent("Between") {
                            HStack {
                                Stepper("\(preset.look.mirrorsMin)", value: Binding(get: { preset.look.mirrorsMin },
                                                                                   set: { v in app.edit(preset.id) { $0.mirrorsMin = min(v, $0.mirrorsMax) } }),
                                        in: Look.segmentRange)
                                Text("and")
                                Stepper("\(preset.look.mirrorsMax)", value: Binding(get: { preset.look.mirrorsMax },
                                                                                   set: { v in app.edit(preset.id) { $0.mirrorsMax = max(v, $0.mirrorsMin) } }),
                                        in: Look.segmentRange)
                            }
                            .monospacedDigit()
                        }
                    }
                    SliderRow("Zoom", value: bind(\.zoom), range: 0.4...3) { String(format: "%.2f×", $0) }
                    SliderRow("Zoom breathing", value: bind(\.breathing), range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                    SliderRow("Drift amount", value: bind(\.drift), range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                    SliderRow("Swirl", value: bind(\.twist), range: -1...1) { String(format: "%.2f", $0) }
                        .disabled(!app.settings.allowSwirl)
                    Picker("Outlines", selection: bind(\.outline)) {
                        Text("Off").tag(0.0)
                        Text("Medium").tag(0.5)
                        Text("Large").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!app.settings.allowOutlines)
                    .help("Black lines along every mirror and tile edge")
                }
                Section {
                    SliderRow("Hue shift", value: bind(\.hueShift), range: 0...360, step: 1) { "\(Int($0))°" }
                        .disabled(!app.settings.allowHueChanges)
                    ScaledSliderRow("Hue cycling", value: bind(\.hueSpeed), scale: .zeroLog(min: 0.01, max: 0.6)) {
                        $0 == 0 ? "off" : String(format: "cycle in %.0f min", 360 / $0 / 60)
                    }
                    .disabled(!app.settings.allowHueChanges)
                    SliderRow("Saturation", value: bind(\.saturation), range: 0...2) { String(format: "%.0f%%", $0 * 100) }
                        .disabled(!app.settings.allowSaturationChanges)
                    SliderRow("Vignette", value: bind(\.vignette), range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                        .disabled(!app.settings.allowVignette)
                } header: {
                    Text("Color")
                } footer: {
                    Text("Effects switched off in Settings stay off for every preset.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<Look, T>) -> Binding<T> {
        Binding(get: { preset.look[keyPath: keyPath] }, set: { v in app.edit(preset.id) { $0[keyPath: keyPath] = v } })
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            Section("Slideshow") {
                Toggle("Shuffle photos", isOn: $app.settings.shuffle)
                ScaledSliderRow("Time per photo", value: $app.settings.secondsPerPhoto, scale: .log(15, 900)) {
                    $0 < 90 ? "\(Int($0)) s" : String(format: "%.1f min", $0 / 60)
                }
                Picker("Transition", selection: $app.settings.transition) {
                    ForEach(TransitionStyle.allCases) { Text($0.label).tag($0) }
                }
                ScaledSliderRow("Transition length", value: $app.settings.transitionSeconds, scale: .log(2, 30)) { String(format: "%.0f s", $0) }
                LabeledContent("Speed") { SpeedControl().frame(maxWidth: 260) }
            }

            Section {
                Picker("Switch to another hearted preset", selection: $app.settings.lookShuffle) {
                    ForEach(LookShuffle.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Shuffle presets")
            } footer: {
                Text("While playing, Kaleido moves between your hearted presets as photos change. The Next button also brings a new preset unless this is Off.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Hue shifts and color cycling", isOn: $app.settings.allowHueChanges)
                Toggle("Saturation changes", isOn: $app.settings.allowSaturationChanges)
                Toggle("Vignette", isOn: $app.settings.allowVignette)
                Toggle("Swirl", isOn: $app.settings.allowSwirl)
                Toggle("Dynamic mirrors", isOn: $app.settings.allowDynamicMirrors)
                Toggle("Outlines", isOn: $app.settings.allowOutlines)
            } header: {
                Text("Effects")
            } footer: {
                Text("Switch an effect off and no preset or Surprise me will use it; your photos keep their own colors.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Performance") {
                Picker("Frame rate", selection: $app.settings.frameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                Toggle("Keep the screen awake while playing", isOn: $app.settings.keepScreenAwake)
                Toggle("Pause on battery", isOn: $app.settings.pauseOnBattery)
                Toggle("30 fps in Low Power Mode", isOn: $app.settings.limitInLowPowerMode)
                Toggle("Start playing when Kaleido opens", isOn: $app.settings.playOnLaunch)
            }
        }
        .formStyle(.grouped)
    }
}
