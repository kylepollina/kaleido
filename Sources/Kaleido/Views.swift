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

// MARK: Library

struct LibraryPane: View {
    @EnvironmentObject var app: AppState
    @State private var filter = "all"
    @State private var showSources = true
    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 10)]

    private var shown: [PhotoItem] {
        switch filter {
        case "all": return app.library.items
        case "manual": return app.library.items.filter(\.isManual)
        default: return app.library.items.filter { $0.sources.contains(filter) }
        }
    }

    var body: some View {
        let items = app.library.items
        let enabled = app.library.enabledItems.count
        let noSources = items.isEmpty && app.library.albums.isEmpty && app.library.folders.isEmpty
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo library").font(.headline)
                    Text(items.isEmpty ? "Nothing selected yet" : "\(enabled) of \(items.count) in rotation")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if app.isSyncing { ProgressView().controlSize(.small) }
                Button("Add Photos…") { choose(directories: false) }
                Button("Add Folder…") { choose(directories: true) }
                Menu {
                    Button("Sync now") { app.syncNow() }
                    Divider()
                    Button("Use all") { app.library.setEnabled(true) }
                    Button("Use none") { app.library.setEnabled(false) }
                    Divider()
                    Button("Remove unused photos") {
                        app.library.remove(ids: Set(items.filter { !$0.isEnabled }.map(\.id)))
                    }
                    Button("Remove missing files") { app.library.removeMissing() }
                    Button("Bring back removed photos (\(app.library.dismissedCount))") { app.library.resetDismissed(); app.syncNow() }
                        .disabled(app.library.dismissedCount == 0)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            DisclosureGroup(isExpanded: $showSources) {
                SourcesView()
            } label: {
                HStack {
                    Text("Sources").font(.subheadline.weight(.medium))
                    Spacer()
                    Text(syncLine).font(.caption).foregroundStyle(.secondary)
                    Button("Sync now") { app.syncNow() }.controlSize(.small).disabled(app.isSyncing)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            if !items.isEmpty {
                HStack {
                    Picker("Show", selection: $filter) {
                        Text("All photos").tag("all")
                        Text("Added by hand").tag("manual")
                        ForEach(app.library.albums) { Text("Album: \($0.title)").tag($0.id) }
                        ForEach(app.library.folders) { Text("Folder: \($0.name)").tag($0.id) }
                    }
                    .labelsHidden().fixedSize()
                    Text("\(shown.count) shown").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.bottom, 6)
            }

            ScrollView {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(.tertiary)
                        Text(noSources ? "Pick some photos to get started" : "No photos yet").foregroundStyle(.secondary)
                        Text(noSources
                             ? "Tick albums from your Photos library above, add a folder, or drop photos and folders here. Kaleido only reads them; your files are never copied or changed, and new photos in chosen albums and folders are picked up about once a day."
                             : "Waiting for the first sync, or the chosen albums are empty under the current filters.")
                            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 30)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(shown) { item in PhotoTile(item: item) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
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

struct SourcesView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            photosSection
            if !app.library.folders.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watched folders").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(app.library.folders) { f in
                        HStack {
                            Image(systemName: "folder")
                            Text(f.name)
                            Text(f.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                            Spacer()
                            Button { app.library.removeFolder(f.id) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).help("Stop watching this folder and remove its photos")
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder private var photosSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Photos library").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            switch app.photos.status {
            case .notDetermined:
                HStack {
                    Text("Pull photos straight from your Photos albums. Kaleido only reads them.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Connect Photos…") { app.connectPhotos() }
                }
            case .denied, .restricted:
                HStack {
                    Text("Photos access is off for Kaleido. Turn it on in System Settings > Privacy & Security > Photos.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
                    }
                }
            default:
                albumList
            }
        }
    }

    private var albumList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if app.photos.status == .limited {
                Text("Kaleido can see only the photos you allowed in System Settings (limited access).").font(.caption).foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach([AlbumInfo.Group.smart, .user, .shared], id: \.rawValue) { group in
                        let list = app.photos.albums.filter { $0.group == group }
                        if !list.isEmpty {
                            Text(group.rawValue).font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
                            ForEach(list) { album in
                                Toggle(isOn: Binding(
                                    get: { app.library.albums.contains { $0.localID == album.localID } },
                                    set: { app.setAlbum(album, included: $0) })) {
                                    HStack { Text(album.title); Text("\(album.count)").foregroundStyle(.secondary).monospacedDigit() }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    if app.photos.albums.isEmpty { Text("No albums found.").foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            HStack(spacing: 16) {
                Toggle("Skip screenshots", isOn: Binding(get: { app.library.filters.excludeScreenshots }, set: { app.library.filters.excludeScreenshots = $0 }))
                Picker("Smallest photo", selection: Binding(get: { app.library.filters.minLongEdge }, set: { app.library.filters.minLongEdge = $0 })) {
                    Text("Any size").tag(0)
                    Text("1600 px").tag(1600)
                    Text("2400 px").tag(2400)
                    Text("3200 px").tag(3200)
                }
                .fixedSize()
                Text("Videos are always skipped.").font(.caption).foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
    }
}

struct PhotoTile: View {
    @EnvironmentObject var app: AppState
    let item: PhotoItem
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
                .opacity(item.isEnabled ? 1 : 0.35)
                .saturation(item.isEnabled ? 1 : 0.2)
            Image(systemName: item.isEnabled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(item.isEnabled ? Color.white : Color.white.opacity(0.8), item.isEnabled ? Color.accentColor : Color.black.opacity(0.35))
                .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(item.isEnabled ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { app.library.toggle(item.id) }
        .help(item.isAsset ? "Photos library" : item.name)
        .contextMenu {
            Button(item.isEnabled ? "Remove from rotation" : "Add to rotation") { app.library.toggle(item.id) }
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
