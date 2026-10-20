# Kaleido

**Your own nature photos as a slowly turning kaleidoscope on your Mac's desktop.**

Kaleido plays an animated background only while the app is open and you have pressed Play, the way Portal
does with landscape videos. It never touches your wallpaper settings. Press Stop or quit, and your normal
wallpaper is simply back.

Native Swift · SwiftUI control window · Metal shader · No accounts, no cloud, photos are never copied or modified

## Features

- **Desktop playback.** One borderless window per display, just above the wallpaper and below desktop icons.
  Mouse clicks pass through. Works across Spaces, multiple displays, and display changes.
- **Scenes.** A scene is a photo with a look (shape, mirrors, swirl, colour...). What's on screen is always a
  scene: a saved one, or a new one Kaleido just put together. "Save scene" keeps it (photo, look and where you
  dragged the photo).
- **Surprise me** (a toggle, on by default): as scenes change, Kaleido mixes your saved scenes with new ones it
  invents. Off, it plays through your saved scenes (or, with none saved, your photos with the look on screen).
  Invented looks use only the shapes ticked in Settings (untick Diamonds if it isn't for you). Next and Back fade
  in 3 seconds; Back brings back the scene before, look and all.
- **Home** is the scene, as big as the window allows, with one glass mini-player over it (like Apple Music's):
  Surprise me, Back / Play (or Space) / Next, the scene's name, Zoom, Speed, Save scene and Edit scene. Edit scene
  floats over the right side with Randomize and every setting of the scene. Click the scene to fill the whole
  window with it (sidebar, toolbar and controls step aside, like Portal); click again or press Escape to come
  back. Dragging still moves the photo either way.
- **Sections.** Home, Photos (the album browser), Scenes and Settings. Patterns (saved looks, below) are hidden
  for now; the code is still there.
- **Built-in patterns.** Mandala, Shifting Mandala, Ink Mandala, Whirlpool, Prism, Fractal Bloom, Hex Garden, Square
  Tiles, Hall of Mirrors, Triangle Toy, Diamonds and Spiral Tunnel: at least one per shape.
- **Pattern editor.** Pick the shape from a grid of drawn buttons. Swirl has a zero mark (and snaps to it) and can sway back and forth, Hue shift shows a before/after colour strip, Outlines
  is a switch, Hue cycling is Off / Slow / Medium / Fast, and Saturation runs 50–150% with a boost that lifts dull
  colours without clipping bright ones. Reset puts a built-in pattern back to its original (or one you
  made back to how you created it). Hearted patterns appear on Home and are the ones new scenes pick from.
- **Save or throw away.** In the pattern and scene editors every change shows at once, on the preview and the
  desktop, but is kept only when you press Save (⌘S). Revert, or leaving the editor, puts the saved version back.
- **Hands on.** Drag the preview to move the photo inside the mirrors; flick it and it keeps gliding. A
  Kaleidoscope / Original switch shows the photo itself, with "Remove from selected photos" and "Show in library".
- **Eight shapes.** Classic radial mirrors, Hex, Fractal, Square tiles, Mirror grid, a Spiral tunnel (mirror
  tiles laid out in log-polar space, so they shrink towards the centre and slowly flow inward; any number of arms, each mirrored about its centre), Triangle (the
  classic three-mirror toy) and Diamonds (Escher's rhombille tiling, kept flat: each diamond holds its own slowly turning mandala).
- **Outlines.** Any pattern can draw black lines along its mirrors and tile edges (an Outlines switch); they bend
  with swirl and follow dynamic mirrors. Settings > Effects can turn them off everywhere.
- **Pattern lines.** In the pattern editor, a toggle traces every mirror and tile edge in red over the dimmed
  photo, so you can see the shape of the pattern itself. The editor preview has its own previous / play / next.
- **Keep the screen awake** while playing (Settings > Performance), and a flower in the menu bar. Switching back
  to Kaleido (Cmd-Tab or the Dock) reopens its window if you closed it.
- **Dynamic mirrors.** A pattern can let its mirror count wander slowly between two numbers. A new mirror opens up
  (the wedges make room while an extra one grows from nothing), or one closes; tilings grow denser or sparser. A
  change comes about every 3 minutes, whatever the speed, and takes about 40 seconds to open up. See the "Shifting Mandala" pattern.
- **One speed control.** Five stops from turtle to rabbit, like the trackpad speed setting.
- **Zoom: Still, Push, Pull.** Push and Pull are what dragging the preview does, done continuously: the photo keeps
  sliding through the mirrors one way or the other (along the mirrors' own axis, which turns with the pattern).
  Whether that reads as zooming in or out depends on the pattern, hence the neutral names. Still leaves only the
  look's own slow zoom breathing (set in Edit scene). Changes ease in and out.
- **Global switches.** Turn off hue shifts, saturation changes, vignette, swirl, dynamic mirrors or outlines for every pattern.
- **macOS Aerials (video).** The slow-motion aerial films macOS downloads for its moving wallpapers and screen
  saver (Yosemite, Iceland, Hong Kong, Palau Jellies...) appear as a built-in card, named from Apple's manifest with
  Apple's own thumbnails. They play through the kaleidoscope like any photo: decoded in hardware at screen size,
  the 240 fps footage slowed to about 30 frames a second (an 8x slow motion), looping, muted, and paused whenever
  nothing is drawing. More arrive when you pick them in System Settings > Wallpaper; Kaleido never copies them.
- **macOS Wallpapers.** No photos of your own? A built-in card offers Apple's desktop pictures that are on disk
  (skipping the plain solid colours). Scenic ones like Big Sur or The Lake are only downloaded when you pick them in
  System Settings > Wallpaper; once downloaded they join automatically on the next sync.
- **Album browser.** Your Photos albums (smart, yours, shared), watched folders and hand-added photos show up as
  cards with a cover photo, name, count and a badge (All / N of M). Tick a card's circle to include the whole
  album, or click the card to open it: click photos to toggle them, Shift-click for a range, plus Select All,
  Deselect All and Invert. Nothing is selected until you choose. Choices are remembered.
- **Whole vs partial.** An album you include entirely ("whole album") picks up new photos automatically. If you
  hand-pick photos in it, new photos are listed but left out until you select them.
- **Stays up to date.** While Kaleido is running it rescans chosen albums and folders at launch and about once a
  day (and shortly after Photos reports a change). New photos join the rotation, vanished ones leave. "Sync now"
  does it on demand. Options skip screenshots and small photos; videos are always skipped.
- **Slow by default.** Scenes last 90 seconds and cross-fade over 12, with dissolve, iris, zoom-through and
  segment transitions (or random). Photos come in shuffled order (each once per round) or in order.
- **Good citizen.** 30 or 60 fps cap, 30 fps in Low Power Mode, optional pause on battery, pauses while the
  display is asleep or the screen is locked, and stops drawing when a window fully covers the desktop.
- **Menu bar item** with Play/Stop, Next photo and Surprise me. Closing the window keeps playback running.
- A live preview in the control window shows what the desktop will look like.

## Install

Requires macOS 26 or later (it uses Liquid Glass) and Xcode (or the Swift toolchain).

```sh
cd ~/Projects/kaleido
./scripts/build.sh            # builds build/Kaleido.app
./scripts/install.sh          # builds and installs to /Applications (quits and relaunches a running copy)
open build/Kaleido.app
```

Run the tests with `swift test`.

## Using it

1. Click **Add Folder…** or **Add Photos…** (or drop files on the window).
2. Press **Play on Desktop** (⌘P). Move to an empty desktop, or use Mission Control's show-desktop, to see it.
3. Tune the look in the sidebar, or try a pattern or Surprise me.
4. **Stop** or quit to get your wallpaper back.

Hover a thumbnail and press ▶︎ to play that photo or video right now, selected or not; it stays until Next or Back. Right-click a thumbnail for "Play now", "Reveal in Finder" and "Remove from library". Saved scenes remember the photo itself, so they still play when its album is unticked; a scene whose photo is gone keeps its look and can take the photo on screen ("Use the photo on screen" in Scenes).

## How it works

- `Sources/KaleidoCore`: settings, patterns, scenes, the photo library (bookmarks plus path fallback), the shuffle
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
