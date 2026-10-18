# Kaleido

**Your own nature photos as a slowly turning kaleidoscope on your Mac's desktop.**

Kaleido plays an animated background only while the app is open and you have pressed Play, the way Portal
does with landscape videos. It never touches your wallpaper settings. Press Stop or quit, and your normal
wallpaper is simply back.

Native Swift · SwiftUI control window · Metal shader · No accounts, no cloud, photos are never copied or modified

## Features

- **Desktop playback.** One borderless window per display, just above the wallpaper and below desktop icons.
  Mouse clicks pass through. Works across Spaces, multiple displays, and display changes.
- **Four sections.** Home (preview, Play, previous/next, Surprise me, speed, your hearted presets), Photos (the
  album browser), Presets (edit, create, duplicate, heart and reset presets) and Settings (slideshow, preset
  shuffling, effect switches, performance).
- **Presets.** Edits apply live and are saved. Reset puts a built-in preset back to its original (or a preset you
  made back to how you created it). Hearted presets appear on Home and are the ones Shuffle presets moves between.
- **Hands on.** Drag the preview to move the photo inside the mirrors; flick it and it keeps gliding. A
  Kaleidoscope / Original switch shows the photo itself.
- **One speed control.** Five stops from turtle to rabbit, like the trackpad speed setting.
- **Mixed-up looks.** The slideshow can switch preset looks now and then or with every photo; Next brings a new
  photo and a new look, Surprise me a new photo and a random look. Looks change in step with the cross-fade.
- **Global switches.** Turn off hue shifts, saturation changes, blur, vignette or swirl for every look.
- **Album browser.** Your Photos albums (smart, yours, shared), watched folders and hand-added photos show up as
  cards with a cover photo, name, count and a badge (All / N of M). Tick a card's circle to include the whole
  album, or click the card to open it: click photos to toggle them, Shift-click for a range, plus Select All,
  Deselect All and Invert. Nothing is selected until you choose. Choices are remembered.
- **Whole vs partial.** An album you include entirely ("whole album") picks up new photos automatically. If you
  hand-pick photos in it, new photos are listed but left out until you select them.
- **Stays up to date.** While Kaleido is running it rescans chosen albums and folders at launch and about once a
  day (and shortly after Photos reports a change). New photos join the rotation, vanished ones leave. "Sync now"
  does it on demand. Options skip screenshots and small photos; videos are always skipped.
- **Three mirror modes.** Classic radial (2 to 24 mirrors), tiled hex, and a fractal fold. Mirrors are
  reflections of each other, so there are no seams.
- **Barely moving by default.** The default look is the "Slow Mandala": a full turn takes well over an hour, the
  zoom breathes once every ten minutes, cross-fades last 12 seconds. A master **Motion** slider runs from Still
  to Gentle (and a little livelier), with per-parameter speeds under "Advanced motion". Speed sliders are
  logarithmic, so the slow end has fine control. Also zoom, swirl, blur, hue shift, saturation and vignette.
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

**How frames reach the screen:** Metal renders into IOSurfaces that are shown through plain Core Animation
layers. (A CAMetalLayer window showed nothing on the notched built-in display, even though frames were
presented, so Kaleido avoids CAMetalLayer for the desktop windows.)

**Troubleshooting displays:** `Kaleido --autoplay --dump-windows [file]` writes a report of every display and
desktop-level window and quits; `scripts/dump-desktop-windows.sh` lists desktop-level windows of all apps.
 Debug > Display Diagnostics… lists every screen, its desktop window, level,
visibility and frame counts; Debug > Rebuild Desktop Windows (or the menu bar item) re-creates them.

Developer helpers: `KALEIDO_DEBUG=1` prints frame pacing every 5 s. `Kaleido --snapshot out.png --photo a.jpg
[--mode hex --segments 6 --time 10 --size 1920x1080]` renders one frame offscreen with the real shader.

## Limitations

- Photos albums import at most the 3000 most recent photos each. Photos stay in Photos; Kaleido asks PhotoKit for
  a display-sized copy (iCloud-only photos are downloaded on demand and skipped if that fails).
- Photos access is requested only when you click "Connect Photos…". The build script signs with a fixed
  requirement so the grant survives rebuilds.
- The app is not sandboxed and is ad-hoc signed. Adding folders like Desktop or Documents may trigger a macOS
  privacy prompt.
- Desktop-level windows are hidden by macOS in some modes (full-screen apps, Mission Control animations).
- Stage Manager's "click wallpaper to show desktop" may treat the animation like the wallpaper; untested.
