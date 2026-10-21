import AppKit
import KaleidoCore
import SwiftUI
import UniformTypeIdentifiers

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    /// Marks zero with a clickable tick and snaps to it when the knob comes close (for signed values like swirl).
    var zeroTick = false
    let format: (Double) -> String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double? = nil, zeroTick: Bool = false,
         format: @escaping (Double) -> String) {
        self.title = title; self._value = value; self.range = range; self.step = step; self.zeroTick = zeroTick; self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: $value, in: range, step: step)
            } else if zeroTick {
                Slider(value: Binding(get: { value }, set: { v in
                    value = abs(v) < (range.upperBound - range.lowerBound) * 0.03 ? 0 : v
                }), in: range)
                .overlay(alignment: .bottomLeading) { zeroMark }
            } else {
                Slider(value: $value, in: range)
            }
        }
    }

    /// A small tick under the slider at zero; clicking it sets the value to zero.
    private var zeroMark: some View {
        GeometryReader { g in
            let knob: CGFloat = 10   // the slider's track starts and ends about half a knob in from its edges
            let x = knob + (g.size.width - 2 * knob) * (0 - range.lowerBound) / (range.upperBound - range.lowerBound)
            Button { value = 0 } label: {
                Rectangle().fill(value == 0 ? Color.accentColor : Color.secondary).frame(width: 2, height: 7)
                    .padding(.horizontal, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Set to zero")
            .position(x: x, y: g.size.height + 5)
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
    /// The scene editor's preview adds pattern lines and its own previous / play / next controls.
    var editor = false
    /// The editor's previous / play / next (a scene keeps its own photo, so its editor leaves them out).
    var transport = true
    /// Controls that float in glass over the bottom of the preview (Home's playback bar).
    var controls: AnyView? = nil
    /// Home: draw the pattern lines (when switched on) while Edit scene is open.
    var linesAllowed = false
    /// Full window: just the picture, edge to edge, no controls (Home's click-to-fill, like Portal).
    var immersive = false
    /// A plain click on the picture (dragging still moves the photo).
    var onClick: (() -> Void)? = nil
    @AppStorage("previewShowsOriginal") private var showOriginal = false
    @AppStorage("previewShowsPatternLines") private var showLines = false

    private var picture: some View {
        Group {
            if let renderer = app.renderer {
                PreviewView(renderer: renderer, showOriginal: showOriginal,
                            showOutlines: (editor || linesAllowed) && showLines, onClick: onClick)
            } else {
                Text("Metal is not available on this Mac.").foregroundStyle(.secondary)
            }
        }
    }

    // One view in both modes (only its frame, corners and overlays animate), so going full window never swaps in a
    // fresh, momentarily black preview.
    var body: some View {
        VStack(spacing: 10) {
            picture
            .aspectRatio(immersive ? nil : 16.0 / 9.0, contentMode: immersive ? .fill : .fit)
            .frame(maxWidth: immersive ? .infinity : nil, maxHeight: immersive ? .infinity : nil)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: immersive ? 0 : 22, style: .continuous))
            .help(showOriginal ? "The photo as it is" : "Drag to move the photo inside the mirrors; flick it to let it glide")
            // Liquid Glass: the controls float over the picture instead of sitting in rows around it.
            .overlay(alignment: .top) {
                HStack(spacing: 10) {
                    GlassTabs(selection: $showOriginal, options: [(false, "Kaleidoscope"), (true, "Original")])
                    if editor && !showOriginal {
                        // The segmented control brings its own glass; this sits beside it as a glass toggle.
                        GlassToggle(isOn: $showLines, title: "Pattern lines", icon: "line.3.crossed.swirl.circle", tint: .red)
                            .help("Trace the mirrors and tile edges in red, to see the shape of the pattern itself")
                    }
                }
                .padding(12)
                .opacity(immersive ? 0 : 1)
                .allowsHitTesting(!immersive)
            }
            .overlay(alignment: .bottom) {
                Group {
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
                    } else if let controls {
                        controls
                    }
                }
                .padding(14)
                .opacity(immersive ? 0 : 1)
                .allowsHitTesting(!immersive)
            }
            if editor && transport {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { app.previousPhoto() } label: { Image(systemName: "backward.fill").frame(width: 22) }
                            .buttonStyle(.glass)
                            .help("Previous photo")
                        PlayButton(compact: true).frame(width: 120)
                        Button { app.nextPhotoKeepingLook() } label: { Image(systemName: "forward.fill").frame(width: 22) }
                            .buttonStyle(.glass)
                            .help("Next photo (keeps this pattern)")
                    }
                }
            }
        }
    }
}

struct PreviewView: NSViewRepresentable {
    let renderer: KaleidoRenderer
    var showOriginal = false
    var showOutlines = false
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> KaleidoView {
        let v = KaleidoView(renderer: renderer, fps: 30)
        updateNSView(v, context: context)
        return v
    }

    func updateNSView(_ nsView: KaleidoView, context: Context) {
        nsView.showOriginal = showOriginal
        nsView.showOutlines = showOutlines
        nsView.onClick = onClick
        nsView.acceptsDrag = !showOriginal   // dragging only makes sense through the mirrors
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

// MARK: Library browser

/// One card on the library home screen: a Photos album, a watched folder, or the hand-added photos.
struct SourceCard: Identifiable {
    enum Group: String, CaseIterable {
        case smart = "Smart albums", user = "My albums", shared = "Shared albums", folders = "Folders", builtIn = "Built-in"
    }
    let id: String
    let title: String
    let group: Group
    let count: Int
    let state: SelectionState
    var album: AlbumInfo?
    var folder: FolderSource?
    var coverAssetID: String?
    var coverItemID: UUID?
    var coverURL: URL?
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
    // Always offered, so there is something to play even without photos of your own.
    let wid = WallpaperScanner.sourceID
    let inUse = lib.wallpapers != nil
    cards.append(SourceCard(id: wid, title: "macOS Wallpapers", group: .builtIn,
                            count: inUse ? lib.itemIDs(in: wid).count : BuiltInWallpapers.available.count,
                            state: inUse ? state(wid) : .none,
                            coverItemID: inUse ? lib.itemIDs(in: wid).first : nil,
                            coverURL: BuiltInWallpapers.available.first.map { URL(fileURLWithPath: $0.key) }))
    // Shown once macOS has downloaded at least one aerial.
    let aid = AerialScanner.sourceID
    let aerialsInUse = lib.aerials != nil
    if aerialsInUse || !BuiltInWallpapers.aerials.isEmpty {
        cards.append(SourceCard(id: aid, title: "macOS Aerials", group: .builtIn,
                                count: aerialsInUse ? lib.itemIDs(in: aid).count : BuiltInWallpapers.aerials.count,
                                state: aerialsInUse ? state(aid) : .none,
                                coverItemID: aerialsInUse ? lib.itemIDs(in: aid).first : nil,
                                coverURL: BuiltInWallpapers.aerials.first.map { URL(fileURLWithPath: $0.key) }))
    }
    return cards
}

/// What the built-in cards can offer before they are switched on (scanned once).
enum BuiltInWallpapers {
    static let available: [SyncEntry] = WallpaperScanner.scan()
    static let aerials: [SyncEntry] = AerialScanner.scan()
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
            let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            return !folders.isEmpty && app.library.add(urls: folders) >= 0
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
                if app.library.items.isEmpty {
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Pick some photos to get started").foregroundStyle(.secondary)
            Text("Open an album, add a folder, or drop photos here. Kaleido only reads them. Albums and folders you include entirely pick up new photos about once a day. No photos of your own? Tick macOS Wallpapers or macOS Aerials (moving video) under Built-in; ones you download in System Settings > Wallpaper show up there too.")
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
            } else if let url = card.coverURL {
                image = await Thumbnails.image(for: url)
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
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(borderColor, lineWidth: card.state == .none ? 1 : 2))
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
    @State private var hovering = false

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
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                if hovering {
                    // Play now: try this one photo or video, selected or not.
                    Button { app.showNow(item.id) } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, Color.black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help("Play this now (stays until Next)")
                }
                if VideoFiles.isVideo(path: item.path) {
                    Image(systemName: "video.fill").font(.caption2).foregroundStyle(.white).shadow(radius: 2)
                }
            }
            .padding(6)
        }
        .onHover { hovering = $0 }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(item.isEnabled ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { click() }
        .help(item.isAsset ? "Photos library" : item.name)
        .contextMenu {
            Button(item.isEnabled ? "Remove from rotation" : "Add to rotation") { app.library.toggle(item.id, in: source) }
            Button("Play now") { app.showNow(item.id) }
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
