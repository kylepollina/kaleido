import AppKit
import KaleidoCore
import SwiftUI

/// The tabs of the floating panel on the left. The scene itself is always the whole window behind it.
enum AppSection: String, CaseIterable, Identifiable {
    case photos = "Photos", scenes = "Scenes", settings = "Settings"
    var id: String { rawValue }
    /// Photos needs room for its album grid; Settings is one column.
    var panelWidth: CGFloat {
        switch self {
        case .photos: return 720
        case .scenes: return 620
        case .settings: return 460
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HomeView()
            .frame(minWidth: 900, idealWidth: 1100, minHeight: 640, idealHeight: 800)
            // No "Kaleido" header: the title and its bar go, and the scene runs up under where they were.
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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

// MARK: Home

/// The whole window is the scene, edge to edge, like Portal. Everything else floats over it in Liquid Glass: the
/// mini-player at the bottom, Photos / Scenes / Settings in a panel on the left (the sidebar button, top left),
/// Edit scene in a panel on the right.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    /// The left panel's tab, or nil while it is closed.
    @State private var panel: AppSection? = AppSection.atLaunch
    /// Edit scene starts closed every time the window opens.
    @State private var editing = CommandLine.arguments.contains("--edit-scene")
    /// A click on the scene fades every control away; another click (or Escape) brings them back.
    @State private var controlsHidden = CommandLine.arguments.contains("--hide-controls")
    /// The Photos tab filling the window.
    @State private var photosExpanded = CommandLine.arguments.contains("--expand-photos")
    /// The photo grid fades out while the panel changes size (re-flowing it every frame looked jittery).
    @State private var resizingPhotos = false

    private func setPhotosExpanded(_ on: Bool) {
        withAnimation(.easeOut(duration: 0.12)) { resizingPhotos = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(Self.panelAnimation) { photosExpanded = on }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeIn(duration: 0.2)) { resizingPhotos = false }
            }
        }
    }
    @AppStorage("previewShowsOriginal") private var showOriginal = false
    @AppStorage("previewShowsPatternLines") private var showLines = false

    static let panelAnimation = Animation.smooth(duration: 0.4)

    private func closePanels() {
        withAnimation(Self.panelAnimation) { editing = false; panel = nil }
    }

    /// A plain click on the scene (dragging still moves the photo): the first one closes any open panel, otherwise
    /// it hides or brings back the controls.
    private func sceneClicked() {
        if editing || panel != nil { closePanels() }
        else { withAnimation(Self.panelAnimation) { controlsHidden.toggle() } }
    }

    var body: some View {
        ZStack {
            picture.ignoresSafeArea()
            GeometryReader { geo in
                let room = geo.size.width
                let right: CGFloat = editing ? Self.editWidth : 0
                let left: CGFloat = panel.map { panelWidth($0, room: room, right: right) } ?? 0
                let gaps: CGFloat = (left > 0 ? 12 : 0) + (right > 0 ? 12 : 0)
                let middle: CGFloat = room - left - right - gaps
                // Room for the mini-player between the panels: it sits there, centred. Otherwise it spans the
                // bottom and the panels stop above it, so nothing is ever cut off.
                let playerBetween = middle >= playerWidth
                ZStack {
                    HStack(alignment: .top, spacing: 0) {
                        if let panel {
                            sidePanel(panel, width: left)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        Spacer(minLength: 0)
                        if editing {
                            editPanel.transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .padding(.bottom, playerBetween ? 0 : Self.playerHeight + 12)
                    VStack(spacing: 10) {
                        if middle >= 260 {
                            GlassTabs(selection: $showOriginal, options: [(false, "Kaleidoscope"), (true, "Original")])
                                .help("Kaleidoscope, or the photo itself as it is (drag the scene to move the photo inside the mirrors)")
                                .padding(.leading, left > 0 ? left + 12 : 0)
                                .padding(.trailing, right > 0 ? right + 12 : 0)
                        }
                        Spacer(minLength: 0)
                        Group {
                            if app.library.enabledItems.isEmpty { photosRow.frame(maxWidth: 560) }
                            bottomControls.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { playerWidth = $0 }
                        }
                        .padding(.leading, playerBetween && left > 0 ? left + 12 : 0)
                        .padding(.trailing, playerBetween && right > 0 ? right + 12 : 0)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)   // never wider than the window
            }
            .padding(12)
            .opacity(controlsHidden ? 0 : 1)
            .allowsHitTesting(!controlsHidden)
        }
        .background {
            // Escape: controls back if hidden, otherwise close the open panels.
            Button("Close") {
                if controlsHidden { withAnimation(Self.panelAnimation) { controlsHidden = false } } else { closePanels() }
            }
            .keyboardShortcut(.cancelAction)
            .hidden()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(Self.panelAnimation) { panel = panel == nil ? .photos : nil }
                } label: {
                    Label("Sidebar", systemImage: "sidebar.left")
                }
                .help(panel == nil ? "Photos, Scenes and Settings" : "Close the sidebar")
            }
        }
        .toolbar(controlsHidden ? .hidden : .visible, for: .windowToolbar)
        // Expanded Photos takes the whole window, so Edit scene opening shrinks it back (and vice versa).
        .onChange(of: editing) { _, on in if on, photosExpanded { setPhotosExpanded(false) } }
        .onChange(of: photosExpanded) { _, on in if on, editing { withAnimation(Self.panelAnimation) { editing = false } } }
    }

    private var picture: some View {
        Group {
            if let renderer = app.renderer {
                PreviewView(renderer: renderer, showOriginal: showOriginal,
                            showOutlines: editing && showLines, onClick: sceneClicked)
                    // No .help here: an AppKit view's tooltip covers the whole window and would hide every button's.
            } else {
                Text("Metal is not available on this Mac.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    @ViewBuilder private var bottomControls: some View {
        if showOriginal {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { app.removeCurrentFromRotation() } label: { Label("Remove from selected photos", systemImage: "minus.circle") }
                        .help("Take this photo out of the rotation and move on to the next one")
                    Button { app.revealCurrentPhoto() } label: { Label("Show in library", systemImage: "photo") }
                        .help("Open it in Finder, or in Photos for photos from your Photos library")
                }
                .buttonStyle(.glass)
            }
        } else {
            transport
        }
    }

    /// The mini-player's measured width, kept clear between the panels.
    @State private var playerWidth: CGFloat = 720
    private static let playerHeight: CGFloat = 50
    private static let editWidth: CGFloat = 360

    /// The left panel's own width when the window has room for it beside the mini-player, narrower (down to
    /// 360) when it doesn't, and the whole window when Photos is expanded.
    private func panelWidth(_ s: AppSection, room: CGFloat, right: CGFloat) -> CGFloat {
        let beside = right > 0 ? right + 12 : 0
        if s == .photos && photosExpanded { return room - beside }
        return min(s.panelWidth, max(360, room - beside - playerWidth - 12), room - beside)
    }

    /// Photos, Scenes and Settings, one glass panel with its tabs on top.
    private func sidePanel(_ s: AppSection, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            GlassTabs(selection: Binding(get: { s }, set: { v in withAnimation(Self.panelAnimation) { panel = v } }),
                      options: AppSection.allCases.map { ($0, $0.rawValue) })
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    if s == .photos {
                        // Photos can take the whole window, for browsing; the scene still shows around it.
                        Button { setPhotosExpanded(!photosExpanded) } label: {
                            Image(systemName: photosExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .hoverHighlight(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(photosExpanded ? "Back to a side panel" : "Fill the window, to browse your photos")
                    }
                }
                .padding(10)
            Group {
                switch s {
                case .photos: LibraryPane()
                case .scenes: ScenesView()
                case .settings: SettingsView()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(resizingPhotos ? 0 : 1)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Edit scene: every setting of the scene on screen.
    private var editPanel: some View {
        Form {
            Section {
                HStack {
                    sceneRow
                    Spacer()
                    Button { app.randomizeScene() } label: { Label("Randomize", systemImage: "dice") }
                        .buttonStyle(.glass)
                        .help("A random pattern and settings for this photo")
                }
                Toggle("Debug lines", isOn: $showLines)
                    .help("Traces the pattern's mirrors and tile edges in red on the scene while this panel is open")
                if !app.library.enabledItems.isEmpty { photosRow }
            }
            LookControls(look: app.settings.look, edit: app.tweakScene)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: Self.editWidth)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// One glass capsule, like Apple Music's mini player: Surprise me · Back · Play · Next · the scene · Save · Edit.
    private var transport: some View {
        let saved = app.scenes.scene(app.activeSceneID)
        return HStack(spacing: 4) {
            PlayerIcon(name: "dice", active: app.settings.surprise, tint: .pink) { app.settings.surprise.toggle() }
                .help(app.settings.surprise
                      ? "Surprise me is on: as scenes change, mostly new ones Kaleido makes up, sometimes your saved scenes"
                      : "Surprise me is off: plays through your saved scenes (or, with none saved, your photos with this look)")
            PlayerIcon(name: "backward.fill", size: 19) { app.previousPhoto() }
                .help("The scene before")
            PlayerIcon(name: app.isPlaying ? "stop.fill" : "play.fill", size: 26) { app.togglePlay() }
                .keyboardShortcut("p", modifiers: .command)
                .help(app.isPlaying ? "Stop: your normal wallpaper comes back (Space)" : "Play on the desktop (Space)")
            PlayerIcon(name: "forward.fill", size: 19) { app.nextPhoto() }
                .help("Next scene")
            // Where a music player shows the song: which scene this is, and whether it is on the desktop.
            VStack(alignment: .leading, spacing: 1) {
                Text(saved?.name ?? (app.sceneTweaked ? "Your scene" : "New scene"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let album = app.albumSlideshow {
                    // Playing one album: say which, with a way back to everything.
                    HStack(spacing: 4) {
                        Image(systemName: "photo.stack").font(.system(size: 10))
                        Text(album.title).lineLimit(1)
                        Button { app.stopAlbumSlideshow() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .help("Stop playing this album: back to all your selected photos")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(app.isPlaying ? (app.suspensionReason.map { "Paused: \($0.lowercased())" } ?? "On your desktop") : "Preview only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 140, alignment: .leading)
            .padding(.horizontal, 8)
            playerDivider
            zoomMenu
            // Speed sits where a music player puts its volume slider.
            HStack(spacing: 6) {
                // The tortoise toggles super slow motion: an eighth of the slowest stop, videos too.
                let slow = app.settings.superSlow
                Button { app.settings.superSlow.toggle() } label: {
                    Image(systemName: "tortoise.fill")
                        .font(.system(size: slow ? 13 : 12, weight: .semibold))
                        .foregroundStyle(slow ? Color.green : Color.secondary)
                        .frame(width: 26, height: 26)
                        .background { if slow { Circle().fill(Color.green.opacity(0.18)) } }
                        .hoverHighlight(Circle())
                }
                .buttonStyle(.plain)
                .help(slow ? "Super slow motion is on: click to go back to the slider's speed"
                           : "Super slow motion: movement at an eighth of the slowest speed, videos at an eighth of real time")
                Slider(value: Binding(get: { Double(app.settings.speedStep) },
                                      set: { app.settings.speedStep = Int($0.rounded()); app.settings.superSlow = false }),
                       in: 0...Double(Settings.speedMultipliers.count - 1), step: 1)
                    .controlSize(.small)
                    .frame(width: 96)
                    .opacity(slow ? 0.4 : 1)
                    .help("Speed: how fast everything moves (moving it ends super slow motion)")
                Image(systemName: "hare.fill").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            playerDivider
            PlayerIcon(name: saved == nil ? "bookmark" : "bookmark.fill", active: saved != nil, tint: .accentColor) {
                if saved == nil { app.saveScene() }
            }
            .help(saved == nil ? "Save scene: keep this photo with these settings and where the photo sits" : "This is one of your saved scenes")
            PlayerIcon(name: "slider.horizontal.3", active: editing, tint: .accentColor) {
                withAnimation(Self.panelAnimation) { editing.toggle() }
            }
            .help("Edit scene: the pattern and every setting of this scene")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private var playerDivider: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 22).padding(.horizontal, 4)
    }

    /// Zoom as the current mode's icon and name, with a small menu of Drift / Push / Pull.
    private var zoomMenu: some View {
        Menu {
            Picker("Zoom", selection: $app.settings.zoomMotion) {
                ForEach(ZoomMotion.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: app.settings.zoomMotion.icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(app.settings.zoomMotion.label)
                    .font(.callout.weight(.medium))
            }
            .frame(width: 84, height: 38)   // wide enough for "Drift", "Push" and "Pull" so nothing shifts
            .hoverHighlight(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Zoom: \(app.settings.zoomMotion.label). Drift wanders slowly; Push and Pull keep sliding the photo through the mirrors one way or the other.")
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
                Button("Choose photos…") { withAnimation(Self.panelAnimation) { panel = .photos } }
                Button("Use macOS wallpapers") { app.library.setWallpapers(true) }
                    .help("Play Apple's desktop pictures until you pick your own")
            } else {
                Text("\(n) photos in rotation").foregroundStyle(.secondary)
                Spacer()
                Button("Choose photos…") { withAnimation(Self.panelAnimation) { panel = .photos } }.buttonStyle(.link)
            }
        }
    }
}


extension ZoomMotion {
    /// Drift: a breeze. Push: arrows pointing in. Pull: arrows pointing out.
    var icon: String {
        switch self {
        case .drift: return "wind"
        case .push: return "arrow.down.right.and.arrow.up.left"
        case .pull: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// A plain icon button for the mini-player capsule. An "active" toggle gets a tinted icon on a soft tinted disc, like
/// Shuffle in Apple Music.
struct PlayerIcon: View {
    let name: String
    var size: CGFloat = 16
    var active = false
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? tint : Color.primary)
                .frame(width: 38, height: 38)
                .background { if active { Circle().fill(tint.opacity(0.18)) } }
                .hoverHighlight(Circle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// A soft disc (or capsule) under the pointer, like the hover on toolbar buttons, so plain icons read as
    /// clickable. Liquid Glass's own `.interactive()` reacts only on glass shapes, and glass inside the glass
    /// capsule looks doubled, so the mini-player draws its own.
    func hoverHighlight<S: Shape>(_ shape: S) -> some View { modifier(HoverHighlight(shape: shape)) }
}

private struct HoverHighlight<S: Shape>: ViewModifier {
    let shape: S
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content
            .background { shape.fill(Color.primary.opacity(hovering && enabled ? 0.1 : 0)) }
            .contentShape(shape)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

/// A whole number you can type, step with the arrows beside it, or nudge with the Up and Down keys while typing.
struct CountField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 56)
                    .onKeyPress(.upArrow) { step(1); return .handled }
                    .onKeyPress(.downArrow) { step(-1); return .handled }
                Stepper(title, value: $value, in: range).labelsHidden()
            }
        }
    }

    private func step(_ d: Int) { value = min(max(value + d, range.lowerBound), range.upperBound) }
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

extension Look {
    var summary: String { "\(mode.label), \(mode.countLabel.lowercased()) \(segments)" }
}

/// Hue cycling's Off / Slow / Medium / Fast. Equatable on what it shows, so dragging another slider (every step
/// rebuilds the look controls) leaves the segmented control alone instead of making it twitch.
struct HueCyclingPicker: View, Equatable {
    let step: Int
    let enabled: Bool
    let set: (Int) -> Void

    static func == (a: Self, b: Self) -> Bool { a.step == b.step && a.enabled == b.enabled }

    var body: some View {
        Picker("Hue cycling", selection: Binding(get: { step }, set: set)) {
            Text("Off").tag(0)
            Text("Slow").tag(1)
            Text("Medium").tag(2)
            Text("Fast").tag(3)
        }
        .pickerStyle(.segmented)
        .disabled(!enabled)
        .help("Slowly cycles the colours around the colour wheel")
    }
}

/// The look controls in Edit scene. `edit` says where a change goes.
struct LookControls: View {
    @EnvironmentObject var app: AppState
    let look: Look
    let edit: ((inout Look) -> Void) -> Void

    var body: some View {
        Group {
                Section("Shape") {
                    PatternPicker(selection: bind(\.mode))
                    CountField(title: look.mode.countLabel,
                               value: Binding(get: { look.segments }, set: { v in edit { $0.segments = v } }),
                               range: Look.segmentRange)
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
                    // How big the photo looks inside the mirrors. (Movement is the mini-player's Zoom; the look's
                    // breathing and drift amounts stay at their defaults and are no longer shown.)
                    SliderRow("Scale", value: bind(\.zoom), range: 0.4...3) { String(format: "%.2f×", $0) }
                        .help("How big the photo looks inside the mirrors: higher shows a small detail, lower shows more of the photo")
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
                    HueCyclingPicker(step: Look.hueCycleSteps.firstIndex(of: Look.hueCycleSteps.min {
                                         abs($0 - look.hueSpeed) < abs($1 - look.hueSpeed) }!)!,
                                     enabled: app.settings.allowHueChanges,
                                     set: { i in edit { $0.hueSpeed = Look.hueCycleSteps[i] } })
                        .equatable()
                    SliderRow("Saturation", value: bind(\.saturation), range: 0.5...1.5) { String(format: "%.0f%%", $0 * 100) }
                        .disabled(!app.settings.allowSaturationChanges)
                    SliderRow("Vignette", value: bind(\.vignette), range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                        .disabled(!app.settings.allowVignette)
                } header: {
                    Text("Color")
                } footer: {
                    Text("Effects switched off in Settings stay off for every scene.").font(.caption).foregroundStyle(.secondary)
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
                Picker("Desktop sharpness", selection: $app.settings.sharpness) {
                    ForEach(Sharpness.allCases) { Text($0.label).tag($0) }
                }
                .help("Fewer pixels keep the Mac cooler; the system scales the picture up smoothly. Balanced draws about half the pixels of Full, Light a quarter.")
                Toggle("Lighter in Low Power Mode (30 fps, Light sharpness)", isOn: $app.settings.limitInLowPowerMode)
                Toggle("Start playing when Kaleido opens", isOn: $app.settings.playOnLaunch)
            }
        }
        .formStyle(.grouped)
    }
}

extension AppSection {
    /// `--section scenes` (etc.) opens the window with that panel open; handy for checking a screen.
    static var atLaunch: AppSection? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--section"), i + 1 < args.count else { return nil }
        return AppSection.allCases.first { $0.rawValue.lowercased() == args[i + 1].lowercased() }
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
