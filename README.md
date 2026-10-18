# Kaleido

**Your own nature photos as a slowly turning kaleidoscope on your Mac's desktop.**

Kaleido plays an animated background only while the app is open and you have pressed Play, the way Portal
does with landscape videos. It never touches your wallpaper settings. Press Stop or quit, and your normal
wallpaper is simply back.

Native Swift · SwiftUI control window · Metal shader · No accounts, no cloud, photos are never copied or modified

## Features

- **Desktop playback.** One borderless window per display, just above the wallpaper and below desktop icons.
  Mouse clicks pass through. Works across Spaces, multiple displays, and display changes.
- **Your photos, your picks.** Add photos or whole folders (JPEG, PNG, HEIC, TIFF, GIF, WebP and more), or
  drag them onto the window. Click a thumbnail to include or exclude it. Choices are remembered between launches.
- **Three mirror modes.** Classic radial (2 to 24 mirrors), tiled hex, and a fractal fold. Mirrors are
  reflections of each other, so there are no seams.
- **Always moving.** The mirrors rotate, the photo drifts and turns inside them, and hue can cycle slowly.
  Controls for rotation speed, zoom, drift, swirl, blur, hue shift, saturation and vignette. Changes glide.
- **Presets and "Surprise me"** for a random, good-looking look.
- **Shuffle** (every photo once per round, never the same twice in a row) or in order, with a seconds-per-photo
  setting and six transitions (dissolve, iris, swirl wipe, zoom through, segment ripple, spin) or random.
- **Good citizen.** 30 or 60 fps cap, 30 fps in Low Power Mode, optional pause on battery, pauses while the
  display is asleep or the screen is locked, and stops drawing when a window fully covers the desktop.
- **Menu bar item** with Play/Stop, Next photo and Surprise me. Closing the window keeps playback running.
- A live preview in the control window shows what the desktop will look like.

## Install

Requires macOS 14 or later and Xcode (or the Swift toolchain).

```sh
cd ~/Projects/kaleido
./scripts/build.sh            # builds build/Kaleido.app
./scripts/build.sh --install  # also copies it to /Applications
open build/Kaleido.app
```

Run the tests with `swift test`.

## Using it

1. Click **Add Folder…** or **Add Photos…** (or drop files on the window).
2. Press **Play on Desktop** (⌘P). Move to an empty desktop, or use Mission Control's show-desktop, to see it.
3. Tune the look in the sidebar, or try a preset or Surprise me.
4. **Stop** or quit to get your wallpaper back.

Right-click a thumbnail for "Show now", "Reveal in Finder" and "Remove from library".

## How it works

- `Sources/KaleidoCore`: settings, looks and presets, the photo library (bookmarks plus path fallback), the shuffle
  queue. No UI, fully unit tested.
- `Sources/Kaleido/Shaders.swift`: one fragment shader. It rotates and twists the screen, folds it into a mirrored
  wedge (radial), a hex-lattice cell (tiled) or iterated abs-folds (fractal), then samples the photo with a mirrored
  repeat sampler at an explicitly computed mip level, so seams never show. Transitions render both photos through
  the same mirrors and blend per transition style.
- `Renderer.swift`: photos are decoded off the main thread with ImageIO, orientation-corrected, downsampled to at
  most 2560 px, and uploaded as mipmapped textures (about 30 MB each, three alive at most). One renderer drives every
  display's view, so the animation stays in step.
- `Desktop.swift`: the windows, at `CGWindowLevelForKey(.desktopWindow) + 1`, rebuilt when displays change.
- Settings live in `~/Library/Application Support/Kaleido/` (set `KALEIDO_DATA_DIR` to use another folder).

Developer helpers: `KALEIDO_DEBUG=1` prints frame pacing every 5 s. `Kaleido --snapshot out.png --photo a.jpg
[--mode hex --segments 6 --time 10 --size 1920x1080]` renders one frame offscreen with the real shader.

## Limitations

- Photos from the Photos app are not imported directly. Export them, or add the folder you keep them in.
- The app is not sandboxed and is ad-hoc signed. Adding folders like Desktop or Documents may trigger a macOS
  privacy prompt.
- Folders are imported once; new files added to a folder later are not picked up automatically.
- Desktop-level windows are hidden by macOS in some modes (full-screen apps, Mission Control animations).
- Stage Manager's "click wallpaper to show desktop" may treat the animation like the wallpaper; untested.
