import AppKit
import KaleidoCore
import SwiftUI

// MARK: Scenes

struct ScenesView: View {
    @EnvironmentObject var app: AppState
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 260)
            Divider()
            if let s = app.scenes.scene(selection) {
                SceneEditor(scene: s)
            } else {
                VStack(spacing: 10) {
                    Text(app.scenes.scenes.isEmpty
                         ? "No scenes yet. A scene keeps one photo with its look and where it sits in the mirrors."
                         : "Pick a scene to show and edit it.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Save what's on screen as a scene") { selection = app.saveScene() }
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            app.isEditingPresets = true
            if selection == nil { selection = app.activeSceneID ?? app.scenes.scenes.first?.id }
            if let id = selection { app.beginEditing(scene: id) }
        }
        .onDisappear {
            app.discardDraft()
            app.isEditingPresets = false
        }
        .onChange(of: selection) { _, id in if let id { app.beginEditing(scene: id) } else { app.discardDraft() } }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(app.scenes.scenes) { s in
                    HStack(spacing: 8) {
                        Button { app.scenes.toggleFavorite(s.id) } label: {
                            Image(systemName: s.isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(s.isFavorite ? Color.pink : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(s.isFavorite ? "Shown on Home" : "Heart to show it on Home")
                        SceneThumbnail(id: s.id).frame(width: 64, height: 36).clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.name).lineLimit(1)
                            Text(app.isSceneAvailable(s) ? s.look.summary : "Photo missing")
                                .font(.caption).foregroundStyle(app.isSceneAvailable(s) ? Color.secondary : Color.orange).lineLimit(1)
                        }
                    }
                    .tag(s.id)
                }
            }
            Divider()
            HStack(spacing: 4) {
                Button { selection = app.saveScene() } label: { Image(systemName: "plus") }
                    .help("New scene from what's on screen")
                Button { if let s = selection, let id = app.scenes.duplicate(s) { selection = id } } label: { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate")
                    .disabled(selection == nil)
                Button {
                    if let s = selection { app.deleteScene(s); selection = nil }
                } label: { Image(systemName: "minus") }
                    .help("Delete")
                    .disabled(selection == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }
}

struct SceneEditor: View {
    @EnvironmentObject var app: AppState
    let scene: SavedScene

    var body: some View {
        VStack(spacing: 0) {
            PreviewPane(editor: true, transport: false).frame(maxWidth: 480).padding(16)
            if !app.isSceneAvailable(scene) {
                Text("This scene's photo is no longer in your library.").foregroundStyle(.orange).padding(.bottom, 8)
            }
            if let draft = app.draft, draft.target == .scene(scene.id) {
                Form {
                    Section {
                        DraftHeader(draft: draft) { EmptyView() }
                    } footer: {
                        Text("Drag the preview to move the photo inside the mirrors; Save keeps where it sits.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LookControls(look: draft.look, edit: app.edit)
                }
                .formStyle(.grouped)
            }
        }
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
