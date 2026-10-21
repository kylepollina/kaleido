import Combine
import Foundation
import KaleidoCore
import SwiftUI

/// Downloads macOS aerials that aren't on this Mac yet, from Apple's own servers (the addresses in macOS's aerials
/// list), into Kaleido's folder. macOS's aerials folder is never written to.
@MainActor
final class AerialDownloads: ObservableObject {
    /// Progress (0...1) of each download under way, by aerial id.
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var failed: Set<String> = []
    /// Called when a video has landed, so the library picks it up.
    var onFinished: (() -> Void)?
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var watchers: [String: AnyCancellable] = [:]

    func isDownloading(_ id: String) -> Bool { progress[id] != nil }

    func start(_ entry: AerialScanner.CatalogEntry) {
        guard tasks[entry.id] == nil else { return }
        failed.remove(entry.id)
        progress[entry.id] = 0
        let id = entry.id
        let task = URLSession.shared.downloadTask(with: entry.remote) { [weak self] tmp, response, error in
            // Move the file before this callback returns (the temporary file is deleted after).
            var landed = false
            if let tmp, error == nil, (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 {
                let dir = Paths.aerialDownloads
                let dest = dir.appendingPathComponent("\(id).mov")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: dest)
                landed = (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil
            }
            let cancelled = (error as? URLError)?.code == .cancelled
            Task { @MainActor in self?.finish(id, landed: landed, cancelled: cancelled) }
        }
        watchers[id] = task.progress.publisher(for: \.fractionCompleted)
            .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] f in MainActor.assumeIsolated { if self?.tasks[id] != nil { self?.progress[id] = f } } }
        tasks[id] = task
        task.resume()
    }

    func cancel(_ id: String) { tasks[id]?.cancel() }

    private func finish(_ id: String, landed: Bool, cancelled: Bool) {
        tasks[id] = nil
        watchers[id] = nil
        progress[id] = nil
        if landed { onFinished?() } else if !cancelled { failed.insert(id) }
    }
}

/// The aerials Apple offers that aren't on this Mac yet, each with a Download button (like System Settings >
/// Wallpaper). Downloaded ones join the album above as soon as they land.
struct AerialCatalogSection: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var downloads: AerialDownloads
    @State private var entries: [AerialScanner.CatalogEntry] = []
    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 10)]

    var body: some View {
        let missing = entries.filter { !$0.isDownloaded }
        VStack(alignment: .leading, spacing: 8) {
            if !missing.isEmpty {
                Text("Not downloaded (\(missing.count))").font(.headline)
                Text("Each is a 4K video of a few hundred MB, downloaded from Apple into Kaleido's own folder.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(missing) { tile($0) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .task(id: app.library.itemIDs(in: AerialScanner.sourceID).count) {
            entries = await Task.detached(priority: .utility) {
                AerialScanner.catalog(downloads: Paths.aerialDownloads)
            }.value
        }
    }

    private func tile(_ e: AerialScanner.CatalogEntry) -> some View {
        let p = downloads.progress[e.id]
        return VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Rectangle().fill(.black.opacity(0.3))
                if let local = e.localThumbnail, let img = NSImage(contentsOf: local) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else if let remote = e.previewImage {
                    AsyncImage(url: remote) { $0.resizable().scaledToFill() } placeholder: { ProgressView().controlSize(.small) }
                }
                Color.black.opacity(0.25)
                Button {
                    if p != nil { downloads.cancel(e.id) } else { downloads.start(e) }
                } label: {
                    Group {
                        if let p {
                            ZStack {
                                Circle().stroke(.white.opacity(0.3), lineWidth: 3)
                                Circle().trim(from: 0, to: max(p, 0.02)).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Image(systemName: "stop.fill").font(.system(size: 10))
                            }
                            .frame(width: 30, height: 30)
                        } else {
                            Image(systemName: downloads.failed.contains(e.id) ? "exclamationmark.arrow.circlepath" : "arrow.down.circle.fill")
                                .font(.system(size: 28))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p != nil ? "Stop downloading" : downloads.failed.contains(e.id) ? "The download failed; try again" : "Download \(e.name)")
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(e.name).font(.callout).lineLimit(1)
            Text(p.map { "Downloading… \(Int($0 * 100))%" } ?? "Not downloaded").font(.caption).foregroundStyle(.secondary)
        }
    }
}
