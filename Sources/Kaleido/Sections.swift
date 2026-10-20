import AppKit
import KaleidoCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home", photos = "Photos", presets = "Patterns", scenes = "Scenes", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house"
        case .photos: return "photo.on.rectangle"
        case .presets: return "sparkles.rectangle.stack"
        case .scenes: return "photo.artframe"
        case .settings: return "gearshape"
        }
    }
    /// Patterns (presets) are hidden for now; the section still exists and `--section patterns` opens it.
    static let visible: [AppSection] = [.home, .photos, .scenes, .settings]
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var section: AppSection? = AppSection.atLaunch

    var body: some View {
        NavigationSplitView {
            List(AppSection.visible, selection: $section) { s in
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
            case .scenes: ScenesView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 640, idealHeight: 800)
        .onAppear {
            // The action stays valid after this window closes, so the app delegate can reopen it.
            let open = openWindow
            app.openMainWindow = { open(id: "main") }
            // SwiftUI sometimes opens this window at a tiny size on first launch; never let it be smaller than
            // the layout needs.
            DispatchQueue.main.async {
                for w in NSApp.windows where w.title == "Kaleido" && w.styleMask.contains(.titled) {
                    w.contentMinSize = NSSize(width: 900, height: 640)
                    if w.frame.width < 900 || w.frame.height < 640 {
                        w.setContentSize(NSSize(width: 1100, height: 800))
                        w.center()
                    }
                }
            }
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
        .buttonStyle(.glassProminent)
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

/// Home is the editor for the scene on screen: pick a pattern to load its settings, adjust them, save the scene.
/// Changes here never touch the pattern itself (that's the Patterns section).
struct HomeView: View {
    @EnvironmentObject var app: AppState
    let go: (AppSection) -> Void
    /// Edit scene starts closed every time the window opens.
    @State private var editing = false

    var body: some View {
        VStack(spacing: 16) {
            // The scene is the hero; its playback controls float over it in glass.
            PreviewPane(controls: AnyView(transport)).frame(maxWidth: 980)
            motion
            if app.library.enabledItems.isEmpty { photosRow.frame(maxWidth: 620) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Edit scene floats over the right side in a glass panel, so nothing underneath moves. (Not an
        // .inspector: inside the window's split view one fed the preview's 16:9 sizing back into the split
        // view's minimum sizes until AppKit gave up, a crash.)
        .overlay(alignment: .trailing) {
            if editing {
                Form {
                    Section {
                        HStack {
                            sceneRow
                            Spacer()
                            Button { app.randomizeScene() } label: { Label("Randomize", systemImage: "dice") }
                                .buttonStyle(.glass)
                                .help("A random pattern and settings for this photo")
                            // The panel covers the Edit scene button, so it closes from here (or with Escape).
                            Button { withAnimation(.easeInOut(duration: 0.25)) { editing = false } } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.glass)
                            .keyboardShortcut(.cancelAction)
                            .help("Close Edit scene")
                        }
                        if !app.library.enabledItems.isEmpty { photosRow }
                    }
                    LookControls(look: app.settings.look, edit: app.tweakScene)
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(width: 360)
                .frame(maxHeight: .infinity)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(12)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onAppear { if CommandLine.arguments.contains("--edit-scene") { editing = true } }
    }

    /// Back · Play · Next · Surprise me · Save scene · Edit scene, as one floating glass bar.
    private var transport: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button { app.previousPhoto() } label: { Image(systemName: "backward.fill").frame(width: 20) }
                    .buttonStyle(.glass)
                    .help("The scene before")
                PlayButton().frame(width: 170)
                Button { app.nextPhoto() } label: { Image(systemName: "forward.fill").frame(width: 20) }
                    .buttonStyle(.glass)
                    .help("Next scene")
                GlassToggle(isOn: $app.settings.surprise, title: "Surprise me", icon: "dice", tint: .purple)
                    .help(app.settings.surprise
                          ? "On: as scenes change, Kaleido mixes your saved scenes with new ones it makes up"
                          : "Off: plays through your saved scenes (or, with none saved, your photos with this look)")
                let saved = app.scenes.scene(app.activeSceneID) != nil
                Button { app.saveScene() } label: { Label(saved ? "Saved" : "Save scene", systemImage: saved ? "bookmark.fill" : "bookmark") }
                    .buttonStyle(.glass)
                    .disabled(saved)
                    .help(saved ? "This is one of your saved scenes" : "Keep this photo with these settings and where the photo sits")
                GlassToggle(isOn: $editing.animation(.easeInOut(duration: 0.25)), title: "Edit scene", icon: "slider.horizontal.3", tint: .accentColor)
                    .help("Show the pattern and every setting of this scene")
            }
            .controlSize(.large)
        }
    }

    /// Speed and Zoom, in one glass capsule under the scene.
    private var motion: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Text("Speed").foregroundStyle(.secondary)
                SpeedControl().frame(width: 200)
            }
            Divider().frame(height: 18)
            HStack(spacing: 8) {
                Text("Zoom").foregroundStyle(.secondary)
                Picker("Zoom", selection: $app.settings.zoomMotion) {
                    ForEach(ZoomMotion.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Push or pull: the photo keeps sliding through the mirrors one way or the other. Drift: only the look's own slow wandering and breathing.")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    /// Which scene this is.
    private var sceneRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let s = app.scenes.scene(app.activeSceneID) {
                Label(s.name, systemImage: "bookmark.fill")
            } else {
                Text(app.sceneTweaked ? "Your scene (not saved yet)" : "New scene")
            }
            if app.sceneTweaked {
                Text("Shuffle waits on this scene until you press Next or save it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var photosRow: some View {
        let n = app.library.enabledItems.count
        return HStack {
            if n == 0 {
                Image(systemName: "photo.badge.plus")
                Text("No photos selected yet.")
                Spacer()
                Button("Choose photos…") { go(.photos) }
                Button("Use macOS wallpapers") { app.library.setWallpapers(true) }
                    .help("Play Apple's desktop pictures until you pick your own")
            } else {
                Text("\(n) photos in rotation").foregroundStyle(.secondary)
                Spacer()
                Button("Choose photos…") { go(.photos) }.buttonStyle(.link)
            }
        }
    }
}


/// A Liquid Glass tab bar: the choices sit in one frosted glass capsule and the selected one rides on a tinted pill
/// that slides between them. Readable over any photo, unlike a plain segmented control.
struct GlassTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                let selected = selection == value
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = value }
                } label: {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                Capsule().fill(Color.accentColor).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

/// An on/off button in Liquid Glass: tinted glass when on, clear glass when off.
struct GlassToggle: View {
    @Binding var isOn: Bool
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        let button = Button { isOn.toggle() } label: { Label(title, systemImage: icon) }
        if isOn {
            button.buttonStyle(.glassProminent).tint(tint)
        } else {
            button.buttonStyle(.glass)
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

/// A hearted pattern on Home: click to put it on the photo showing.
struct PatternCard: View {
    @EnvironmentObject var app: AppState
    let preset: SavedPreset

    var body: some View {
        let active = app.settings.activePresetID == preset.id
        Button { app.choosePattern(preset) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(preset.look.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(active ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Put \(preset.name) on this photo")
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
                    Text("Pick a pattern to edit it.").foregroundStyle(.secondary)
                    if app.settings.activePresetID == nil {
                        Button("Save the pattern on screen") { selection = app.saveCurrentPattern() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            app.isEditingPresets = true
            if selection == nil { selection = app.settings.activePresetID ?? app.presets.presets.first?.id }
            if let id = selection { app.beginEditing(preset: id) }
        }
        .onDisappear {
            app.discardDraft()
            app.isEditingPresets = false
        }
        .onChange(of: selection) { _, id in if let id { app.beginEditing(preset: id) } else { app.discardDraft() } }
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
                Button { selection = app.saveCurrentPattern() } label: { Image(systemName: "plus") }
                    .help("New pattern from what's on screen")
                Button { if let s = selection, let id = app.presets.duplicate(s) { selection = id } } label: { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate")
                    .disabled(selection == nil)
                Button {
                    if let s = selection { app.presets.delete(s); selection = app.presets.presets.first?.id }
                } label: { Image(systemName: "minus") }
                    .help("Delete (built-in patterns can only be un-hearted)")
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
            if let draft = app.draft, draft.target == .preset(preset.id) {
                Form {
                    Section {
                        DraftHeader(draft: draft) {
                            Button("Reset") { app.resetDraftToOriginal() }
                                .disabled(draft.look == preset.originalLook && draft.name == preset.originalName)
                                .help(preset.isBuiltIn ? "Back to the original pattern (then Save to keep it)"
                                                       : "Back to how it was when you created it (then Save to keep it)")
                        }
                    }
                    LookControls(look: draft.look, edit: app.edit)
                }
                .formStyle(.grouped)
            }
        }
    }
}

/// Name, an "unsaved changes" note, and Revert / Save for whatever the editor has open.
struct DraftHeader<Extra: View>: View {
    @EnvironmentObject var app: AppState
    let draft: EditDraft
    @ViewBuilder var extra: Extra

    var body: some View {
        TextField("Name", text: Binding(get: { draft.name }, set: { app.renameDraft($0) }))
        HStack {
            if draft.hasChanges {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .help("You see the changes now; they are kept only if you press Save")
            }
            Spacer()
            extra
            Button("Revert") { app.revertDraft() }
                .disabled(!draft.hasChanges)
                .help("Throw away the changes since the last save")
            Button("Save") { app.saveDraft() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.glassProminent)
                .disabled(!draft.hasChanges)
        }
    }
}

/// The look controls shared by Home and the pattern and scene editors. `edit` says where a change goes.
struct LookControls: View {
    @EnvironmentObject var app: AppState
    let look: Look
    let edit: ((inout Look) -> Void) -> Void

    var body: some View {
        Group {
                Section("Shape") {
                    PatternPicker(selection: bind(\.mode))
                    SliderRow(look.mode.countLabel,
                              value: Binding(get: { Double(look.segments) }, set: { v in edit { $0.segments = Int(v.rounded()) } }),
                              range: 2...24, step: 1) { "\(Int($0))" }
                    Toggle("Dynamic mirrors (slowly change how many)", isOn: bind(\.dynamicMirrors))
                        .disabled(!app.settings.allowDynamicMirrors)
                    if look.dynamicMirrors {
                        LabeledContent("Between") {
                            HStack {
                                Stepper("\(look.mirrorsMin)", value: Binding(get: { look.mirrorsMin },
                                                                                   set: { v in edit { $0.mirrorsMin = min(v, $0.mirrorsMax) } }),
                                        in: Look.segmentRange)
                                Text("and")
                                Stepper("\(look.mirrorsMax)", value: Binding(get: { look.mirrorsMax },
                                                                                   set: { v in edit { $0.mirrorsMax = max(v, $0.mirrorsMin) } }),
                                        in: Look.segmentRange)
                            }
                            .monospacedDigit()
                        }
                    }
                    SliderRow("Zoom", value: bind(\.zoom), range: 0.4...3) { String(format: "%.2f×", $0) }
                    SliderRow("Zoom breathing", value: bind(\.breathing), range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                    SliderRow("Drift amount", value: bind(\.drift), range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                    SliderRow("Swirl", value: bind(\.twist), range: -1...1, zeroTick: true) { $0 == 0 ? "none" : String(format: "%+.2f", $0) }
                        .disabled(!app.settings.allowSwirl)
                    Toggle("Sway (swing the swirl slowly back and forth)", isOn: bind(\.swayingSwirl))
                        .disabled(!app.settings.allowSwirl || look.twist == 0)
                        .help("Swings from this much swirl, through straight, to the same amount the other way and back")
                    Toggle("Outlines", isOn: Binding(get: { look.outline > 0 },
                                                     set: { on in edit { $0.outline = on ? Look.outlineSteps[1] : 0 } }))
                        .disabled(!app.settings.allowOutlines)
                        .help("Thin black lines along every mirror and tile edge")
                }
                Section {
                    SliderRow("Hue shift", value: bind(\.hueShift), range: 0...360, zeroTick: true) { $0 < 0.5 ? "none" : "\(Int($0))°" }
                        .disabled(!app.settings.allowHueChanges)
                    HueShiftStrip(degrees: look.hueShift)
                        .opacity(app.settings.allowHueChanges ? 1 : 0.4)
                        .help("Top: the original colours. Bottom: what each one becomes with this hue shift.")
                    Picker("Hue cycling", selection: Binding(
                        get: { Look.hueCycleSteps.min { abs($0 - look.hueSpeed) < abs($1 - look.hueSpeed) }! },
                        set: { v in edit { $0.hueSpeed = v } })) {
                        Text("Off").tag(Look.hueCycleSteps[0])
                        Text("Slow").tag(Look.hueCycleSteps[1])
                        Text("Medium").tag(Look.hueCycleSteps[2])
                        Text("Fast").tag(Look.hueCycleSteps[3])
                    }
                    .pickerStyle(.segmented)
                    .disabled(!app.settings.allowHueChanges)
                    .help("Slowly cycles the colours around the colour wheel")
                    SliderRow("Saturation", value: bind(\.saturation), range: 0.5...1.5) { String(format: "%.0f%%", $0 * 100) }
                        .disabled(!app.settings.allowSaturationChanges)
                    SliderRow("Vignette", value: bind(\.vignette), range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                        .disabled(!app.settings.allowVignette)
                } header: {
                    Text("Color")
                } footer: {
                    Text("Effects switched off in Settings stay off for every pattern and scene.").font(.caption).foregroundStyle(.secondary)
                }
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<Look, T>) -> Binding<T> {
        Binding(get: { look[keyPath: keyPath] }, set: { v in edit { $0[keyPath: keyPath] = v } })
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            Section("Scenes") {
                Toggle("Surprise me (mix in new scenes Kaleido makes up)", isOn: $app.settings.surprise)
                Toggle("Shuffle photo order", isOn: $app.settings.shuffle)
                ScaledSliderRow("Time per scene", value: $app.settings.secondsPerPhoto, scale: .log(15, 900)) {
                    $0 < 90 ? "\(Int($0)) s" : String(format: "%.1f min", $0 / 60)
                }
                Picker("Transition", selection: $app.settings.transition) {
                    ForEach(TransitionStyle.allCases) { Text($0.label).tag($0) }
                }
                ScaledSliderRow("Transition length", value: $app.settings.transitionSeconds, scale: .log(2, 30)) { String(format: "%.0f s", $0) }
                LabeledContent("Speed") { SpeedControl().frame(maxWidth: 260) }
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(MirrorMode.allCases) { mode in
                        Toggle(mode.label, isOn: Binding(
                            get: { !app.settings.excludedShapes.contains(mode) },
                            set: { on in
                                app.settings.excludedShapes.removeAll { $0 == mode }
                                if !on { app.settings.excludedShapes.append(mode) }
                            }))
                            .toggleStyle(.checkbox)
                            // Keep at least one shape.
                            .disabled(app.settings.inventedShapes == [mode])
                    }
                }
            } header: {
                Text("Invented patterns")
            } footer: {
                Text("Surprise me and new scenes with invented patterns only use the shapes ticked here.")
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
                Text("Switch an effect off and no pattern, scene or Surprise me will use it; your photos keep their own colors.")
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

extension AppSection {
    /// `--section presets` (etc.) opens the window on that section; handy for checking a screen.
    static var atLaunch: AppSection {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--section"), i + 1 < args.count else { return .home }
        return AppSection.allCases.first { $0.rawValue.lowercased() == args[i + 1].lowercased() } ?? .home
    }
}

/// Shows what Hue shift does: the colour wheel as it is (top) and where each colour ends up (bottom).
struct HueShiftStrip: View {
    let degrees: Double

    var body: some View {
        VStack(spacing: 2) {
            strip(offset: 0)
            strip(offset: degrees / 360)
        }
        .frame(height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func strip(offset: Double) -> some View {
        let stops = (0...12).map { i -> Color in
            let h = (Double(i) / 12 + offset).truncatingRemainder(dividingBy: 1)
            return Color(hue: h, saturation: 0.75, brightness: 0.95)
        }
        return LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
    }
}
