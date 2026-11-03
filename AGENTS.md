# Notes for coding agents

Kaleido is a native macOS app (SwiftUI + Metal, macOS 26, Liquid Glass) that shows the user's photos and videos as
slowly turning kaleidoscopes on the desktop while it plays, like the Portal app. README.md is a short pitch plus
install steps (it mirrors the site in `docs/`); this file is how to work on it.

## Ground rules

- Never write to the user's wallpaper settings, System Settings, other apps, or macOS's own folders (e.g.
  `~/Library/Application Support/com.apple.wallpaper` is read only; Kaleido's aerial downloads go to its own data
  folder). Only read the photos the user picked.
- Commit and push every finished change on `main` (private repo kylepollina/kaleido).
- Keep user-facing reports short. Don't run lots of display tests; one screenshot to check a layout is plenty.

## Build, test, install

```sh
swift build                 # quick compile check
swift test                  # KaleidoCore unit tests (about 60)
./scripts/build.sh          # build/Kaleido.app (release, signed)
./scripts/install.sh        # build, install to /Applications, quit and relaunch a running copy
./scripts/release.sh        # build/Kaleido-<version>.dmg; see the script's header for signing and notarizing
```

The shader in `Sources/Kaleido/Shaders.swift` compiles at runtime, so `swift build` does not check it. After a
shader change render a frame: `Kaleido --snapshot out.png --photo a.heic [--photo2 b.heic --mix 0.5 --transition zoom]`.

## Testing without touching the user's setup

- Run test copies with `KALEIDO_DATA_DIR=<scratch dir>` so the user's settings, scenes and library are untouched.
  Handy flags: `--section photos|scenes|settings`, `--edit-scene`, `--expand-photos`, `--hide-controls`;
  `KALEIDO_SHOW_TIPS=1` shows every mini-player tip at once; `KALEIDO_DEBUG=1` logs frame pacing.
- Window screenshots: find the window id with CGWindowListCopyWindowInfo for the test copy's pid, then
  `screencapture -x -o -l <id>`. The user runs Stage Manager: a background window captures as a skewed thumbnail,
  so bring the test copy's process frontmost (System Events) for a second first.
- `Kaleido --stress-render <folder> --seconds N --per-photo N` plays a folder through the real renderer off screen
  and logs memory; sample `ps -o %cpu=` alongside to compare CPU.
- The running app rewrites `~/Library/Application Support/Kaleido/settings.json`; quit it before editing that file.
- The shell aliases `ls`, `mv` and `rm`; use `find`, `/bin/mv`, `/bin/rm` in scripts.

## Things that bite

- `GPUUniforms` (Renderer.swift) must match the shader's `Uniforms` field for field (currently 22 floats, then 9
  int32s). Add fields in the same place in both.
- The scene is a full-window AppKit view (`KaleidoView`) under all the SwiftUI controls. Standard `.help` tooltips
  never show over it: use the `.tip("…")` modifier (Sections.swift). Don't put `.help` on the scene itself.
- Window dragging: the strip under the hidden title bar is handled in `KaleidoView.mouseDown` (performDrag).
- Home layout (Sections.swift `HomeView`): panels and the mini-player are sized from the window with a GeometryReader;
  the mini-player's width is measured, and when panels plus player don't fit, the player spans the bottom and the
  panels stop above it. Keep the ZStack framed to the window so nothing overflows.
- During a cross-fade each photo has its own pan, zoom and swirl (`panB*`, `zoomB`, `twistB`), so scene changes
  don't slide or zoom. Shared uniforms for both photos caused the old "zooms a ton" bug.
- Video: AVPlayer + AVPlayerItemVideoOutput into a mipmapped texture; real-time playback, an eighth of real time in
  super slow motion. Apple's aerials are 5-minute 240 fps clips.
- Scenes remember the photo itself (`photoKey`), so they survive an album being unticked.
- Saved "patterns" (presets) were removed on purpose; the user preferred the app without them.
