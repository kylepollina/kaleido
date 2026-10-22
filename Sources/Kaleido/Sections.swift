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
                            // The panel grows to the right, so the arrows run along the up-right / down-left diagonal.
                            Image(systemName: photosExpanded ? "arrow.down.left.and.arrow.up.right" : "arrow.up.right.and.arrow.down.left")
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
        .glossy(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Edit scene: every setting of the scene on screen. Randomize sits top right, outside the sections; then the
    /// scene's name and Save, the shape, speed and zoom, and the colours.
    private var editPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { app.randomizeScene() } label: { Label("Randomize", systemImage: "dice") }
                    .buttonStyle(.glass)
                    .help("Invent a new random pattern for this photo (the photo, speed and zoom stay)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            Form {
                Section {
                    TextField("Scene name", text: $sceneName, prompt: Text("Scene name"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .onSubmit { if let id = app.activeSceneID { app.renameScene(id, to: sceneName) } }
                    // Like the mini-player's bookmark: filled and tinted while this scene is saved as it is.
                    let saved = app.activeSceneID != nil
                    Button {
                        _ = app.saveScene(named: sceneName)
                        if let s = app.scenes.scene(app.activeSceneID) { sceneName = s.name }
                    } label: {
                        Label(saved ? "Saved" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(saved ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(saved)
                    .help(saved ? "Saved scene" : "Keep this photo with these settings as a saved scene")
                }
                ShapeControls(look: app.settings.look, edit: app.tweakScene, showLines: $showLines)
                Section("Motion") {
                    LabeledContent("Speed") { SpeedSlider(sliderWidth: 130) }
                    GlassTabs(selection: zoomBinding,
                              options: ZoomMotion.allCases.map { ($0, $0.label) },
                              icons: ZoomMotion.allCases.map(\.icon))
                        .frame(maxWidth: .infinity)
                        .help("Zoom: Drift, or Push / Pull the photo slowly through the mirrors")
                }
                ColorControls(look: app.settings.look, edit: app.tweakScene)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .onAppear { syncSceneName() }
            .onChange(of: app.activeSceneID) { _, _ in syncSceneName() }
        }
        .frame(width: Self.editWidth)
        .frame(maxHeight: .infinity)
        .glossy(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @State private var sceneName = ""

    /// The name field follows the saved scene on screen; a new or edited scene keeps what was typed.
    private func syncSceneName() {
        if let s = app.scenes.scene(app.activeSceneID) { sceneName = s.name }
        else if !app.sceneTweaked { sceneName = "" }
    }

    private var zoomBinding: Binding<ZoomMotion> {
        Binding(get: { app.settings.look.zoomMotion }, set: { app.setSceneMotion(zoomMotion: $0) })
    }

    /// One glass capsule, like Apple Music's mini player: Random patterns · Shuffle · Back · Play · Next · the scene · Save · Edit.
    private var transport: some View {
        let saved = app.scenes.scene(app.activeSceneID)
        return HStack(spacing: 4) {
            // Two toggles, like Shuffle and Repeat in Music: invented patterns, and random order.
            PlayerIcon(name: "dice", active: app.settings.surprise, tint: .pink) { app.settings.surprise.toggle() }
                .tip(app.settings.surprise ? "Random patterns: on (every scene gets an invented pattern)"
                                           : "Random patterns: off (saved scenes keep their own pattern)")
            let discover = app.albumSlideshow == nil && app.settings.playSource == .discover
            PlayerIcon(name: "shuffle", active: discover || app.settings.shuffle, tint: .accentColor) { app.settings.shuffle.toggle() }
                .disabled(discover)
                .opacity(discover ? 0.5 : 1)
                .tip(discover ? "Shuffle: Discover always plays in random order"
                              : (app.settings.shuffle ? "Shuffle: on" : "Shuffle: off (in order)"))
            PlayerIcon(name: "backward.fill", size: 19) { app.previousPhoto() }
                .tip("Previous scene")
            PlayerIcon(name: app.isPlaying ? "stop.fill" : "play.fill", size: 26) { app.togglePlay() }
                .keyboardShortcut("p", modifiers: .command)
                .tip(app.isPlaying ? "Stop (Space)" : "Play on the desktop (Space)")
            PlayerIcon(name: "forward.fill", size: 19) { app.nextPhoto() }
                .tip("Next scene")
            // Where a music player shows the song: which scene this is, and what it is playing from.
            VStack(alignment: .leading, spacing: 1) {
                Text(saved?.name ?? (app.sceneTweaked ? "Your scene" : "New scene"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                modeMenu
            }
            .frame(width: 140, alignment: .leading)
            .padding(.horizontal, 8)
            playerDivider
            zoomMenu
            // Speed sits where a music player puts its volume slider.
            SpeedSlider(sliderWidth: 96)
            .padding(.horizontal, 6)
            playerDivider
            PlayerIcon(name: saved == nil ? "bookmark" : "bookmark.fill", active: saved != nil, tint: .accentColor) {
                if let saved { app.deleteScene(saved.id) } else { app.saveScene() }
            }
            .tip(saved == nil ? "Save scene" : "Saved scene (click to remove it)")
            PlayerIcon(name: "slider.horizontal.3", active: editing, tint: .accentColor) {
                withAnimation(Self.panelAnimation) { editing.toggle() }
            }
            .tip("Edit scene")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glossy(Capsule())
    }

    /// What it is playing from (Discover, My scenes, or an album) as a small menu, and whether the desktop is paused.
    private var modeMenu: some View {
        let album = app.albumSlideshow
        let title = album.map { "Album: \($0.title)" } ?? app.settings.playSource.label
        let icon = album != nil ? "photo.stack" : app.settings.playSource.icon
        return Menu {
            ForEach(PlaySource.allCases) { source in
                Toggle(isOn: Binding(get: { album == nil && app.settings.playSource == source },
                                     set: { _ in app.setPlaySource(source) })) {
                    Label(source.label, systemImage: source.icon)
                }
                .disabled(source == .scenes && !app.hasPlayableScenes)
            }
            if let album {
                Divider()
                Button("Stop playing \(album.title)") { app.stopAlbumSlideshow() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(app.isPlaying ? (app.suspensionReason.map { _ in "\(title) · paused" } ?? title) : title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .tip("Play from: Discover (all your photos, saved scenes now and then) or My scenes")
    }

    private var playerDivider: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 22).padding(.horizontal, 4)
    }

    /// Zoom as the current mode's icon and name, with a small menu of Drift / Push / Pull.
    private var zoomMenu: some View {
        Menu {
            Picker("Zoom", selection: zoomBinding) {
                ForEach(ZoomMotion.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: app.settings.look.zoomMotion.icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(app.settings.look.zoomMotion.label)
                    .font(.callout.weight(.medium))
            }
            .frame(width: 84, height: 38)   // wide enough for "Drift", "Push" and "Pull" so nothing shifts
            .hoverHighlight(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .tip("Zoom: Drift, Push or Pull")
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


extension PlaySource {
    var icon: String {
        switch self {
        case .discover: return "sparkles"
        case .scenes: return "bookmark.fill"
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

extension View {
    /// A tooltip drawn by SwiftUI itself, above the control after a short hover. The mini-player floats over the
    /// scene's AppKit view, which swallows standard `.help` tooltips there.
    func tip(_ text: String) -> some View { modifier(HoverTip(text: text)) }
}

private struct HoverTip: ViewModifier {
    let text: String
    /// KALEIDO_SHOW_TIPS=1 shows every tip at once, for checking how they look.
    @State private var shown = ProcessInfo.processInfo.environment["KALEIDO_SHOW_TIPS"] == "1"
    @State private var pending: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pending?.cancel()
                if inside {
                    let show = DispatchWorkItem { withAnimation(.easeOut(duration: 0.15)) { shown = true } }
                    pending = show
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: show)
                } else {
                    withAnimation(.easeIn(duration: 0.1)) { shown = false }
                }
            }
            .simultaneousGesture(TapGesture().onEnded { pending?.cancel(); shown = false })
            // A zero-height strip along the control's top edge; the tip hangs above it, centred, one line.
            .overlay(alignment: .top) {
                Color.clear.frame(height: 0)
                    .overlay(alignment: .bottom) {
                        if shown {
                            Text(text)
                                .font(.caption)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .glassEffect(.regular, in: Capsule())
                                .padding(.bottom, 14)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
            }
    }
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
    /// An SF Symbol before each title (optional).
    var icons: [String] = []
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                let selected = selection == value
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = value }
                } label: {
                    Label {
                        Text(title)
                    } icon: {
                        if i < icons.count { Image(systemName: icons[i]) }
                    }
                        .labelStyle(GlassTabLabelStyle(hasIcon: i < icons.count))
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

private struct GlassTabLabelStyle: LabelStyle {
    let hasIcon: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            if hasIcon { configuration.icon }
            configuration.title
        }
    }
}

/// The scene's speed: five stops from turtle to rabbit, like the trackpad speed setting (saved scenes keep it). The
/// tortoise toggles super slow motion: an eighth of the slowest stop, videos too. Mini-player and Edit scene alike.
struct SpeedSlider: View {
    @EnvironmentObject var app: AppState
    var sliderWidth: CGFloat = 96

    var body: some View {
        let slow = app.settings.superSlow
        HStack(spacing: 6) {
            Button { app.settings.superSlow.toggle() } label: {
                Image(systemName: "tortoise.fill")
                    .font(.system(size: slow ? 13 : 12, weight: .semibold))
                    .foregroundStyle(slow ? Color.green : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background { if slow { Circle().fill(Color.green.opacity(0.18)) } }
                    .hoverHighlight(Circle())
            }
            .buttonStyle(.plain)
            .tip(slow ? "Super slow motion: on" : "Super slow motion")
            Slider(value: Binding(get: { Double(app.settings.look.speedStep) },
                                  set: { app.setSceneMotion(speedStep: Int($0.rounded())); app.settings.superSlow = false }),
                   in: 0...Double(Settings.speedMultipliers.count - 1), step: 1)
                .controlSize(.small)
                .frame(width: sliderWidth)
                .opacity(slow ? 0.4 : 1)
                .tip("Speed")
            Image(systemName: "hare.fill").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

extension Look {
    var summary: String { "\(mode.label), \(mode.countLabel.lowercased()) \(segments)" }
}

/// Edit scene's Shape section (with the debug-lines toggle under the shapes).
struct ShapeControls: View {
    @EnvironmentObject var app: AppState
    let look: Look
    let edit: ((inout Look) -> Void) -> Void
    @Binding var showLines: Bool

    var body: some View {
        Section("Shape") {
            PatternPicker(selection: bind(\.mode))
            Toggle("Debug lines", isOn: $showLines)
                .help("Traces the pattern's mirrors and tile edges in red on the scene while this panel is open")
            CountField(title: look.mode.countLabel,
                       value: Binding(get: { look.segments }, set: { v in edit { $0.segments = v } }),
                       range: Look.segmentRange)
            Toggle("Dynamic mirrors", isOn: bind(\.dynamicMirrors))
                .disabled(!app.settings.allowDynamicMirrors)
                .help("Slowly changes how many mirrors there are")
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
            // How big the photo looks inside the mirrors; 1.00× sits in the middle of the slider with a tick.
            ScaledSliderRow("Scale", value: bind(\.zoom), scale: .centeredLog(min: 0.4, mid: 1, max: 3), tick: 1) {
                String(format: "%.2f×", $0)
            }
            .help("How big the photo looks inside the mirrors: higher shows a small detail, lower shows more of the photo")
            SliderRow("Swirl", value: bind(\.twist), range: -1...1, zeroTick: true) { $0 == 0 ? "none" : String(format: "%+.2f", $0) }
                .disabled(!app.settings.allowSwirl)
            Toggle("Sway", isOn: bind(\.swayingSwirl))
                .disabled(!app.settings.allowSwirl || look.twist == 0)
                .help("Swings the swirl slowly back and forth: from this much, through straight, to the same amount the other way and back")
            Toggle("Outlines", isOn: Binding(get: { look.outline > 0 },
                                             set: { on in edit { $0.outline = on ? Look.outlineSteps[1] : 0 } }))
                .disabled(!app.settings.allowOutlines)
                .help("Thin black lines along every mirror and tile edge")
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<Look, T>) -> Binding<T> {
        Binding(get: { look[keyPath: keyPath] }, set: { v in edit { $0[keyPath: keyPath] = v } })
    }
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
        .help("Keeps turning the colours around the colour wheel (faster with the scene's Speed)")
    }
}

/// Edit scene's Color section. Hue shift picks the colours (a fixed turn of the colour wheel); Hue cycling keeps
/// turning them around the wheel from there, as fast as its slider says.
struct ColorControls: View {
    @EnvironmentObject var app: AppState
    let look: Look
    let edit: ((inout Look) -> Void) -> Void

    var body: some View {
        Section {
            SliderRow("Hue shift", value: bind(\.hueShift), range: 0...360, zeroTick: true) { $0 < 0.5 ? "none" : "\(Int($0))°" }
                .disabled(!app.settings.allowHueChanges)
                .help("Turns every colour a fixed amount around the colour wheel")
            HueShiftStrip(degrees: look.hueShift)
                .opacity(app.settings.allowHueChanges ? 1 : 0.4)
                .help("Top: the original colours. Bottom: what each one becomes with this hue shift.")
            HueCyclingPicker(step: Look.hueCycleStep(look.hueSpeed), enabled: app.settings.allowHueChanges,
                             set: { i in edit { $0.hueSpeed = Look.hueCycleSteps[i] } })
                .equatable()
            SliderRow("Saturation", value: bind(\.saturation), range: 0.5...1.5) { String(format: "%.0f%%", $0 * 100) }
                .disabled(!app.settings.allowSaturationChanges)
            SliderRow("Vignette", value: bind(\.vignette), range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                .disabled(!app.settings.allowVignette)
        } header: {
            Text("Color")
        } footer: {
            Text("Hue shift sets where the colours start; hue cycling keeps them turning from there. Effects switched off in Settings stay off for every scene.")
                .font(.caption).foregroundStyle(.secondary)
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
                Toggle("Random patterns", isOn: $app.settings.surprise)
                    .help("Every scene that comes up gets an invented pattern, saved scenes' photos too (the dice in the mini-player)")
                Toggle("Shuffle My scenes and albums", isOn: $app.settings.shuffle)
                    .help("Discover always plays in random order")
                ScaledSliderRow("Time per scene", value: $app.settings.secondsPerPhoto, scale: .log(15, 900)) {
                    $0 < 90 ? "\(Int($0)) s" : String(format: "%.1f min", $0 / 60)
                }
                Picker("Transition", selection: $app.settings.transition) {
                    ForEach(TransitionStyle.allCases) { Text($0.label).tag($0) }
                }
                ScaledSliderRow("Transition length", value: $app.settings.transitionSeconds, scale: .log(2, 30)) { String(format: "%.0f s", $0) }
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
                Text("Random patterns and Randomize only use the shapes ticked here.")
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
                Text("Switch an effect off and no pattern, scene or random scene will use it; your photos keep their own colors.")
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

extension View {
    /// Liquid Glass with extra gloss: a soft sheen over the top of the pane and a bright rim that fades along the
    /// edge, like light catching glass.
    func glossy<S: InsettableShape>(_ shape: S) -> some View {
        self
            .glassEffect(.regular, in: shape)
            .overlay {
                shape
                    .fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.02), .clear],
                                         startPoint: .top, endPoint: .center))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05), .white.opacity(0.22)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }
}
