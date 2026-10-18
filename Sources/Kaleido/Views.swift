import AppKit
import KaleidoCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            ControlsPane()
                .frame(width: 340)
            Divider()
            VStack(spacing: 0) {
                PreviewPane()
                    .padding([.horizontal, .top], 16)
                LibraryPane()
            }
        }
        .frame(minWidth: 960, minHeight: 680)
    }
}

// MARK: Controls

struct ControlsPane: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Button {
                    app.togglePlay()
                } label: {
                    Label(app.isPlaying ? "Stop" : "Play on Desktop", systemImage: app.isPlaying ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(app.isPlaying ? .red : .accentColor)
                .keyboardShortcut("p", modifiers: .command)
                Text(statusText).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)

            Form {
                Section("Photos") {
                    Toggle("Shuffle", isOn: $app.settings.shuffle)
                    ScaledSliderRow("Seconds per photo", value: $app.settings.secondsPerPhoto, scale: .log(15, 900)) { $0 < 90 ? "\(Int($0)) s" : String(format: "%.1f min", $0 / 60) }
                    Picker("Transition", selection: $app.settings.transition) {
                        ForEach(TransitionStyle.allCases) { Text($0.label).tag($0) }
                    }
                    ScaledSliderRow("Transition length", value: $app.settings.transitionSeconds, scale: .log(2, 30)) { String(format: "%.0f s", $0) }
                }

                Section {
                    HStack {
                        Menu("Presets") {
                            ForEach(Preset.all) { p in Button(p.name) { app.apply(p) } }
                        }
                        Button { app.surpriseMe() } label: { Label("Surprise me", systemImage: "dice") }
                    }
                    Picker("Mirror mode", selection: $app.settings.look.mode) {
                        ForEach(MirrorMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    let isHex = app.settings.look.mode == .hex
                    SliderRow(isHex ? "Tile density" : "Mirrors", value: intBinding(\.segments), range: 2...24, step: 1) { "\(Int($0))" }
                    ScaledSliderRow("Motion", value: $app.settings.look.motion, scale: .zeroLog(min: 0.05, max: 2)) {
                        $0 == 0 ? "Still" : ($0 < 0.5 ? "Barely moving" : ($0 <= 1.05 ? "Gentle" : "Livelier"))
                    }
                    SliderRow("Zoom", value: $app.settings.look.zoom, range: 0.4...3) { String(format: "%.2f×", $0) }
                    SliderRow("Drift amount", value: $app.settings.look.drift, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                    SliderRow("Swirl", value: $app.settings.look.twist, range: -1...1) { String(format: "%.2f", $0) }
                    DisclosureGroup("Advanced motion") {
                        ScaledSliderRow("Rotation", value: $app.settings.look.rotationSpeed, scale: .signedLog(min: 0.005, max: 0.6)) { Self.turnText($0) }
                        ScaledSliderRow("Drift speed", value: $app.settings.look.driftSpeed, scale: .zeroLog(min: 0.01, max: 0.5)) { $0 == 0 ? "off" : String(format: "lap in %.0f min", 1 / ($0 * 0.173 * 0.25) * 2 * .pi / 60) }
                        SliderRow("Zoom breathing", value: $app.settings.look.breathing, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                    }
                } header: { Text("Kaleidoscope") }

                Section("Color") {
                    SliderRow("Blur", value: $app.settings.look.blur, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                    SliderRow("Hue shift", value: $app.settings.look.hueShift, range: 0...360, step: 1) { "\(Int($0))°" }
                    ScaledSliderRow("Hue cycling", value: $app.settings.look.hueSpeed, scale: .zeroLog(min: 0.01, max: 0.6)) { $0 == 0 ? "off" : String(format: "cycle in %.0f min", 360 / $0 / 60) }
                    SliderRow("Saturation", value: $app.settings.look.saturation, range: 0...2) { String(format: "%.0f%%", $0 * 100) }
                    SliderRow("Vignette", value: $app.settings.look.vignette, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                }

                Section("Performance") {
                    Picker("Frame rate", selection: $app.settings.frameRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Pause on battery", isOn: $app.settings.pauseOnBattery)
                    Toggle("30 fps in Low Power Mode", isOn: $app.settings.limitInLowPowerMode)
                    Toggle("Start playing when Kaleido opens", isOn: $app.settings.playOnLaunch)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var statusText: String {
        if let r = app.suspensionReason, app.isPlaying { return "Paused: \(r.lowercased())" }
        if app.isPlaying { return "Playing. Stop or quit Kaleido to get your wallpaper back." }
        return "Your normal wallpaper is showing."
    }

    static func turnText(_ v: Double) -> String {
        if abs(v) < 0.0005 { return "still" }
        let mins = 360 / abs(v) / 60
        return (v < 0 ? "← " : "") + (mins >= 120 ? String(format: "turn in %.1f h", mins / 60) : String(format: "turn in %.0f min", mins))
    }

    private func intBinding(_ keyPath: WritableKeyPath<Look, Int>) -> Binding<Double> {
        Binding(get: { Double(app.settings.look[keyPath: keyPath]) },
                set: { app.settings.look[keyPath: keyPath] = Int($0.rounded()) })
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let format: (Double) -> String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double? = nil, format: @escaping (Double) -> String) {
        self.title = title; self._value = value; self.range = range; self.step = step; self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            if let step { Slider(value: $value, in: range, step: step) } else { Slider(value: $value, in: range) }
        }
    }
}

struct ScaledSliderRow: View {
    let title: String
    @Binding var value: Double
    let scale: SliderScale
    let format: (Double) -> String

    init(_ title: String, value: Binding<Double>, scale: SliderScale, format: @escaping (Double) -> String) {
        self.title = title; self._value = value; self.scale = scale; self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { scale.position(for: value) }, set: { value = scale.value(at: $0) }), in: 0...1)
        }
    }
}

// MARK: Preview

struct PreviewPane: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let renderer = app.renderer {
                PreviewView(renderer: renderer)
            } else {
                Text("Metal is not available on this Mac.").foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button { app.nextPhoto() } label: { Label("Next photo", systemImage: "forward.fill") }
                Button { app.surpriseMe() } label: { Label("Surprise me", systemImage: "dice") }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.black.opacity(0.55))
            .padding(10)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxHeight: 300)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }
}

struct PreviewView: NSViewRepresentable {
    let renderer: KaleidoRenderer
    func makeNSView(context: Context) -> KaleidoView { KaleidoView(renderer: renderer, fps: 30) }
    func updateNSView(_ nsView: KaleidoView, context: Context) {}
}

// MARK: Library browser

/// One card on the library home screen: a Photos album, a watched folder, or the hand-added photos.
struct SourceCard: Identifiable {
    enum Group: String, CaseIterable { case smart = "Smart albums", user = "My albums", shared = "Shared albums", folders = "Folders and files" }
    let id: String
    let title: String
    let group: Group
    let count: Int
    let state: SelectionState
    var album: AlbumInfo?
    var folder: FolderSource?
    var coverAssetID: String?
    var coverItemID: UUID?
    var isManual: Bool { id == PhotoLibrary.manualSource }
}

@MainActor
func makeCards(_ app: AppState) -> [SourceCard] {
    let lib = app.library
    func state(_ id: String) -> SelectionState { lib.selectionState(in: id) }
    func total(_ id: String, fallback: Int) -> Int {
        let n = lib.itemIDs(in: id).count
        return lib.albums.contains { $0.id == id } && n > 0 ? n : fallback
    }
    var cards: [SourceCard] = []
    for a in app.photos.albums {
        let g: SourceCard.Group = a.group == .smart ? .smart : (a.group == .user ? .user : .shared)
        let tracked = lib.albums.contains { $0.id == a.id }
        let st = tracked ? state(a.id) : .none
        cards.append(SourceCard(id: a.id, title: a.title, group: g, count: total(a.id, fallback: a.count), state: st, album: a,
                                coverAssetID: a.coverAssetID, coverItemID: nil))
    }
    for f in lib.folders {
        cards.append(SourceCard(id: f.id, title: f.name, group: .folders, count: lib.itemIDs(in: f.id).count, state: state(f.id),
                                folder: f, coverItemID: lib.itemIDs(in: f.id).first))
    }
    let manual = lib.itemIDs(in: PhotoLibrary.manualSource)
    if !manual.isEmpty {
        cards.append(SourceCard(id: PhotoLibrary.manualSource, title: "Photos added one by one", group: .folders, count: manual.count,
                                state: state(PhotoLibrary.manualSource), coverItemID: manual.first))
    }
    return cards
}

struct LibraryPane: View {
    @EnvironmentObject var app: AppState
    @State private var openID: String?

    var body: some View {
        let enabled = app.library.enabledItems.count
        let total = app.library.items.count
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo library").font(.headline)
                    Text(total == 0 ? "Nothing selected yet" : "\(enabled) of \(total) photos in rotation")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if app.isSyncing { ProgressView().controlSize(.small) }
                Text(syncLine).font(.caption).foregroundStyle(.secondary)
                Button("Sync now") { app.syncNow() }.controlSize(.small).disabled(app.isSyncing)
                Button("Add Photos…") { choose(directories: false) }
                Button("Add Folder…") { choose(directories: true) }
                Menu {
                    Button("Skip screenshots") {
                        app.library.filters.excludeScreenshots.toggle()
                    }
                    .modifier(CheckedModifier(on: app.library.filters.excludeScreenshots))
                    Picker("Smallest photo", selection: Binding(get: { app.library.filters.minLongEdge }, set: { app.library.filters.minLongEdge = $0 })) {
                        Text("Any size").tag(0); Text("1600 px").tag(1600); Text("2400 px").tag(2400); Text("3200 px").tag(3200)
                    }
                    Divider()
                    Button("Remove missing files") { app.library.removeMissing() }
                    Button("Bring back removed photos (\(app.library.dismissedCount))") { app.library.resetDismissed(); app.syncNow() }
                        .disabled(app.library.dismissedCount == 0)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            if let openID, let card = makeCards(app).first(where: { $0.id == openID }) {
                AlbumDetailView(card: card) {
                    app.library.untrackIfUnused(openID)
                    self.openID = nil
                }
            } else {
                LibraryHomeView(open: { card in app.open(card); openID = card.id })
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            app.library.add(urls: urls) > 0
        }
    }

    private var syncLine: String {
        if app.isSyncing { return "Syncing…" }
        guard let d = app.library.lastSync else { return "Not synced yet" }
        if Date().timeIntervalSince(d) < 10 { return "Synced just now" }
        return "Last synced " + RelativeDateTimeFormatter().localizedString(for: d, relativeTo: Date())
    }

    private func choose(directories: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = directories
        panel.canChooseFiles = !directories
        panel.allowedContentTypes = directories ? [] : [.image]
        panel.prompt = "Add"
        if panel.runModal() == .OK { app.library.add(urls: panel.urls) }
    }
}

struct CheckedModifier: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { content.overlay(alignment: .trailing) { if on { Image(systemName: "checkmark") } } }
}

struct LibraryHomeView: View {
    @EnvironmentObject var app: AppState
    let open: (SourceCard) -> Void
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 14)]

    var body: some View {
        let cards = makeCards(app)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                photosBanner
                ForEach(SourceCard.Group.allCases, id: \.rawValue) { group in
                    let list = cards.filter { $0.group == group }
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(list) { card in AlbumCardView(card: card, open: { open(card) }) }
                            }
                        }
                    }
                }
                if cards.isEmpty && app.photos.isAuthorized {
                    emptyHint
                } else if cards.isEmpty {
                    emptyHint
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    @ViewBuilder private var photosBanner: some View {
        switch app.photos.status {
        case .notDetermined:
            banner("Show your Photos albums here", "Kaleido only reads the albums you pick. Nothing is copied or changed.", "Connect Photos…") { app.connectPhotos() }
        case .denied, .restricted:
            banner("Photos access is off", "Turn it on in System Settings > Privacy & Security > Photos.", "Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
            }
        case .limited:
            Text("Kaleido can see only the photos you allowed in System Settings (limited access).").font(.caption).foregroundStyle(.orange)
        default: EmptyView()
        }
    }

    private func banner(_ title: String, _ detail: String, _ button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.stack").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.callout.weight(.medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button(button, action: action)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Pick some photos to get started").foregroundStyle(.secondary)
            Text("Open an album, add a folder, or drop photos here. Kaleido only reads them. Albums and folders you include entirely pick up new photos about once a day.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity).padding(.top, 30)
    }
}

struct CoverImage: View {
    @EnvironmentObject var app: AppState
    let card: SourceCard
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.5))
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: card.folder != nil || card.isManual ? "folder" : "photo").font(.title).foregroundStyle(.tertiary) }
        }
        .task(id: card.coverAssetID ?? card.coverItemID?.uuidString ?? card.id) {
            if let a = card.coverAssetID { image = await Thumbnails.image(forAsset: a) }
            else if let id = card.coverItemID, let item = app.library.item(id) {
                if let a = item.assetID { image = await Thumbnails.image(forAsset: a) }
                else if let url = app.library.resolveURL(for: id) { image = await Thumbnails.image(for: url) }
            }
        }
    }
}

struct AlbumCardView: View {
    @EnvironmentObject var app: AppState
    let card: SourceCard
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay { CoverImage(card: card) }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(borderColor, lineWidth: card.state == .none ? 1 : 2))
                    .overlay(alignment: .bottomTrailing) { badge.padding(8) }
                Button { app.toggleWhole(card) } label: {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(card.state == .none ? Color.white.opacity(0.9) : Color.white, card.state == .none ? Color.black.opacity(0.35) : Color.accentColor)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .padding(8)
                .help(card.state == .none ? "Include the whole album" : "Remove the whole album from the rotation")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(card.title).font(.callout.weight(.medium)).lineLimit(1)
                Text("\(card.count) photos").font(.caption).foregroundStyle(.secondary)
            }
        }
        .scaleEffect(hover ? 1.015 : 1)
        .animation(.easeOut(duration: 0.12), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .contextMenu {
            Button("Open") { open() }
            Button(card.state == .none ? "Include whole album" : "Remove from rotation") { app.toggleWhole(card) }
            if let f = card.folder { Button("Stop watching folder", role: .destructive) { app.library.removeFolder(f.id) } }
        }
    }

    private var icon: String {
        switch card.state { case .none: return "circle"; case .partial: return "minus.circle.fill"; case .all: return "checkmark.circle.fill" }
    }
    private var borderColor: Color { card.state == .none ? Color.primary.opacity(0.1) : Color.accentColor.opacity(0.8) }

    @ViewBuilder private var badge: some View {
        switch card.state {
        case .none: EmptyView()
        case .all: pill("All")
        case .partial(let n, let m): pill("\(n) of \(m)")
        }
    }
    private func pill(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
    }
}

struct AlbumDetailView: View {
    @EnvironmentObject var app: AppState
    let card: SourceCard
    let back: () -> Void
    @State private var anchor: UUID?
    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 10)]

    var body: some View {
        let ids = app.library.itemIDs(in: card.id)
        let lib = app.library
        let selected = ids.filter { lib.item($0)?.isEnabled == true }.count
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { back() } label: { Label("Library", systemImage: "chevron.left") }
                Text(card.title).font(.title3.weight(.semibold)).lineLimit(1)
                Text("\(selected) of \(ids.count) selected").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Select All") { lib.selectAll(in: card.id) }
                Button("Deselect All") { lib.deselectAll(in: card.id) }
                Button("Invert") { lib.invertSelection(in: card.id) }
            }
            .padding(.horizontal, 16).padding(.bottom, 6)
            if card.album != nil || card.folder != nil {
                HStack {
                    Toggle(isOn: Binding(get: { lib.autoInclude(card.id) },
                                         set: { $0 ? lib.selectAll(in: card.id) : lib.setAutoInclude(card.id, false) })) {
                        Text(card.folder != nil ? "Whole folder: include new photos automatically" : "Whole album: include new photos automatically")
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    Text("Click a photo to toggle it. Shift-click selects a range.").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            ScrollView {
                if ids.isEmpty {
                    VStack(spacing: 8) {
                        if app.isSyncing { ProgressView() }
                        Text(app.isSyncing ? "Loading photos…" : "No photos here under the current filters.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 50)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ids, id: \.self) { id in
                            if let item = lib.item(id) {
                                PhotoTile(item: item, source: card.id, order: ids, anchor: $anchor)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
        }
    }
}

struct PhotoTile: View {
    @EnvironmentObject var app: AppState
    let item: PhotoItem
    let source: String
    let order: [UUID]
    @Binding var anchor: UUID?
    @State private var image: NSImage?
    @State private var missing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle().fill(.quaternary.opacity(0.5))
                .overlay {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else if missing {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
                .frame(height: 96)
                .clipped()
                .opacity(item.isEnabled ? 1 : 0.4)
                .saturation(item.isEnabled ? 1 : 0.2)
            Image(systemName: item.isEnabled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(item.isEnabled ? Color.white : Color.white.opacity(0.8), item.isEnabled ? Color.accentColor : Color.black.opacity(0.35))
                .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(item.isEnabled ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { click() }
        .help(item.isAsset ? "Photos library" : item.name)
        .contextMenu {
            Button(item.isEnabled ? "Remove from rotation" : "Add to rotation") { app.library.toggle(item.id, in: source) }
            Button("Show now") { app.showNow(item.id) }
            if !item.isAsset {
                Button("Reveal in Finder") {
                    if let url = app.library.resolveURL(for: item.id) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
            Divider()
            Button("Remove from library", role: .destructive) { app.library.remove(ids: [item.id]) }
        }
        .task(id: item.id) {
            if let assetID = item.assetID {
                image = await Thumbnails.image(forAsset: assetID)
            } else if let url = app.library.resolveURL(for: item.id) {
                image = await Thumbnails.image(for: url)
            }
            missing = image == nil
        }
    }

    private func click() {
        let shift = NSEvent.modifierFlags.contains(.shift)
        if shift, let a = anchor, a != item.id {
            // Shift-click sets the whole range to the state the clicked photo is about to take.
            app.library.setSelected(RangeSelection.ids(in: order, from: a, to: item.id), !item.isEnabled, in: source)
        } else {
            app.library.toggle(item.id, in: source)   // plain and Cmd-click: one photo at a time
        }
        anchor = item.id
    }
}

// MARK: Menu bar

struct MenuBarContent: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(app.isPlaying ? "Stop" : "Play on Desktop") { app.togglePlay() }
        Button("Next Photo") { app.nextPhoto() }.disabled(!app.isPlaying)
        Button("Surprise Me") { app.surpriseMe() }
        Button("Refresh Desktop Windows") { app.rebuildDesktop() }.disabled(!app.isPlaying)
        Divider()
        Button("Show Kaleido Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Kaleido") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
