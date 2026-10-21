import AppKit
import KaleidoCore
import SwiftUI

// MARK: Scenes

/// Your saved scenes as a list of pictures, starred ones on top: click one to show it, star your favourites (they
/// come up more often), swipe (or right-click) to rename or delete. Changing a scene's look happens in Edit scene, on screen.
struct ScenesView: View {
    @EnvironmentObject var app: AppState
    @State private var renaming: UUID?
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if app.scenes.scenes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.artframe").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("No scenes yet. A scene keeps one photo with its look and where it sits in the mirrors.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(app.scenes.starredFirst) { s in row(s) }
                }
                .listStyle(.plain)
            }
            Button { _ = app.saveScene() } label: {
                Label("Save the scene on screen", systemImage: "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(12)
            .help("Keep this photo with these settings and where the photo sits")
        }
    }

    private func row(_ s: SavedScene) -> some View {
        let available = app.isSceneAvailable(s)
        let active = app.activeSceneID == s.id
        return HStack(spacing: 12) {
            SceneThumbnail(id: s.id)
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(active ? Color.accentColor : .clear, lineWidth: 2)
                }
            VStack(alignment: .leading, spacing: 2) {
                if renaming == s.id {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit { finishRenaming() }
                        .onExitCommand { renaming = nil }
                } else {
                    Text(s.name).font(.body.weight(active ? .semibold : .regular)).lineLimit(1)
                }
                Text(available ? s.look.summary : "Photo missing")
                    .font(.caption)
                    .foregroundStyle(available ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { withAnimation { app.scenes.toggleFavorite(s.id) } } label: {
                Image(systemName: s.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(s.isFavorite ? Color.yellow : Color.secondary)
                    .frame(width: 28, height: 28)
                    .hoverHighlight(Circle())
            }
            .buttonStyle(.plain)
            .help(s.isFavorite ? "Starred: at the top, and comes up more often as scenes change" : "Star it: to the top, and it comes up more often")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if renaming != s.id { app.showScene(s) } }
        .opacity(available ? 1 : 0.7)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { app.deleteScene(s.id) } label: { Label("Delete", systemImage: "trash") }
            Button { startRenaming(s) } label: { Label("Rename", systemImage: "pencil") }
                .tint(.blue)
        }
        .swipeActions(edge: .leading) {
            Button { withAnimation { app.scenes.toggleFavorite(s.id) } } label: {
                Label(s.isFavorite ? "Unstar" : "Star", systemImage: s.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
        .contextMenu {
            Button("Show") { app.showScene(s) }.disabled(!available)
            Button("Rename…") { startRenaming(s) }
            Button(s.isFavorite ? "Unstar" : "Star") { withAnimation { app.scenes.toggleFavorite(s.id) } }
            Button("Duplicate") { _ = app.scenes.duplicate(s.id) }
            if !available {
                Button("Use the photo on screen") { app.usePhotoOnScreen(for: s.id) }
            }
            Divider()
            Button("Delete", role: .destructive) { app.deleteScene(s.id) }
        }
    }

    private func startRenaming(_ s: SavedScene) {
        newName = s.name
        renaming = s.id
        DispatchQueue.main.async { nameFocused = true }
    }

    private func finishRenaming() {
        if let id = renaming { app.renameScene(id, to: newName) }
        renaming = nil
    }
}

/// The picture taken when the scene was saved.
struct SceneThumbnail: View {
    @EnvironmentObject var app: AppState
    let id: UUID
    @State private var image: NSImage?

    var body: some View {
        Rectangle().fill(.black)
            .overlay {
                if let image { Image(nsImage: image).resizable().scaledToFill() }
                else { Image(systemName: "photo.artframe").foregroundStyle(.secondary) }
            }
            .clipped()
            .task(id: app.sceneThumbVersion) { image = NSImage(contentsOf: AppState.sceneThumbnailURL(id)) }
    }
}
