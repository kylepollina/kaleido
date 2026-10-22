# Kaleido

**Your own nature photos as a slowly turning kaleidoscope on your Mac's desktop.**

Kaleido plays an animated background only while the app is open and you have pressed Play, the way Portal
does with landscape videos. It never touches your wallpaper settings. Press Stop or quit, and your normal
wallpaper is simply back.

Native Swift · SwiftUI control window · Metal shader · No accounts, no cloud, photos are never copied or modified

## Features

- **Desktop playback.** One borderless window per display, just above the wallpaper and below desktop icons.
  Mouse clicks pass through. Works across Spaces, multiple displays, and display changes. Play and Stop fade the
  kaleidoscope in over the wallpaper and back out (1.5 s).
- **Scenes.** A scene is a photo with a look (shape, mirrors, swirl, colour...). What's on screen is always a
  scene: a saved one, or a new one Kaleido just put together. "Save scene" keeps it (photo, look and where you
  dragged the photo), and its speed and zoom (Drift / Push / Pull). Changing speed or zoom on a saved scene
  saves itself; the rest needs Save.
- **Play from** (the line under the scene's name in the mini-player): **Discover** plays all your selected photos
  in random order, with saved scenes popping in now and then; **My scenes** plays your saved scenes as a playlist
  (also "Play my scenes" at the top of the Scenes tab); playing an album from Photos is the third mode.
- **Random patterns** (the dice, on by default): every scene that comes up gets an invented pattern, a saved
  scene's photo included (its saved pattern is left alone), so photos that make good patterns keep coming back
  new. Off, saved scenes show their own pattern and other photos keep the one on screen. **Shuffle** (beside it)
  plays My scenes and albums in random order; Discover is always random. Randomize in Edit scene re-rolls the
  pattern on screen once. Invented patterns use only the shapes ticked in Settings (untick Diamonds if it isn't
  for you). Next and Back fade in 3 seconds; Back brings back the scene before, look and all.
- **Bookmark** saves the scene; click it again (lit) to remove the saved scene. Edit scene is a bigger version of
  the mini-player's editing: its Save button, name, speed (with the tortoise) and zoom are the same controls, so a
  change in one shows in the other.
- **The window is the scene**, edge to edge (like Portal), and everything floats over it in Liquid Glass:
  - a mini-player (like Apple Music's): Random patterns, Shuffle, Back / Play (or Space) / Next, the scene's name and what it plays from, Zoom
    (Drift / Push / Pull), Speed, Save scene and Edit scene; each button lights up under the pointer;
  - the sidebar button (top left) opens a panel on the left with Photos, Scenes and Settings tabs (Photos can
    expand to fill the window, for browsing). Scenes lists your scenes as pictures: click to show one, star the
    ones you love (they move to the top and come up more often; new scenes start unstarred), swipe or
    right-click to rename or delete;
  - Edit scene opens a panel on the right with Randomize (top right), the scene's name and Save, Shape with Debug lines (the mirrors traced in red), Motion (speed with the tortoise, zoom) and every
    setting of the scene.

  A click on the scene closes any open panel; with none open it hides every control, and another click (or
  Escape) brings them back. Dragging moves the photo either way.
- **Hands on.** Drag the preview to move the photo inside the mirrors; flick it and it keeps gliding. A
  Kaleidoscope / Original switch shows the photo itself, with "Remove from selected photos" and "Show in library".
- **Eight shapes.** Classic radial mirrors, Hex, Fractal, Square tiles, Mirror grid, a Spiral tunnel (mirror
  tiles laid out in log-polar space, so they shrink towards the centre and slowly flow inward; any number of arms, each mirrored about its centre), Triangle (the
  classic three-mirror toy) and Diamonds (Escher's rhombille tiling, kept flat: each diamond holds its own slowly turning mandala).
- **Outlines.** Any pattern can draw black lines along its mirrors and tile edges (an Outlines switch); they bend
  with swirl and follow dynamic mirrors. Settings > Effects can turn them off everywhere.
- **Keep the screen awake** while playing (Settings > Performance), and a flower in the menu bar. Switching back
  to Kaleido (Cmd-Tab or the Dock) reopens its window if you closed it.
- **Dynamic mirrors.** A pattern can let its mirror count wander slowly between two numbers. A new mirror opens up
  (the wedges make room while an extra one grows from nothing), or one closes; tilings grow denser or sparser. A
  change comes about every 3 minutes, whatever the speed, and takes about 40 seconds to open up. Turn it on in Edit scene.
- **One speed control.** Five stops from turtle to rabbit, like the trackpad speed setting. Click the tortoise for
  super slow motion: every movement at an eighth of the slowest stop, and videos at an eighth of real time.
- **Zoom: Drift, Push, Pull.** Push and Pull are what dragging the preview does, done continuously: the photo keeps
  sliding through the mirrors one way or the other (along the mirrors' own axis, which turns with the pattern).
  Whether that reads as zooming in or out depends on the pattern, hence the neutral names. Drift leaves only the
  look's own slow zoom breathing (set in Edit scene). Changes ease in and out.
- **Hue.** Hue shift turns every colour a fixed amount around the colour wheel. Hue cycling (Off / Slow / Medium /
  Fast) keeps turning them around the wheel from there: at the default speed a lap takes about 10 minutes, 3.5
  minutes or 1 minute.
- **Global switches.** Turn off hue shifts, saturation changes, vignette, swirl, dynamic mirrors or outlines for every scene.
- **macOS Aerials (video).** Every aerial in macOS's list shows up; the ones not on this Mac yet have a Download
  button (Kaleido fetches the video from Apple into its own folder, never macOS's). The slow-motion films macOS downloads for its moving wallpapers and screen
  saver (Yosemite, Iceland, Hong Kong, Palau Jellies...) appear as a built-in card, named from Apple's manifest with
  Apple's own thumbnails. They play through the kaleidoscope like any photo: decoded in hardware at screen size,
  playing in real time as macOS does, looping, muted, and paused whenever
  nothing is drawing. More arrive when you pick them in System Settings > Wallpaper; Kaleido never copies them.
- **macOS Wallpapers.** No photos of your own? A built-in card offers Apple's desktop pictures that are on disk
  (skipping the plain solid colours). Scenic ones like Big Sur or The Lake are only downloaded when you pick them in
  System Settings > Wallpaper; once downloaded they join automatically on the next sync.
- **Album browser.** Right-click an album to hide it (the … menu can show hidden albums again). Your Photos albums (smart, yours, shared), watched folders and hand-added photos show up as
  cards with a cover photo, name, count and a badge (All / N of M). Tick a card's circle to include the whole
  album, or click the card to open it: click photos to toggle them, Shift-click for a range, plus Select All,
  Deselect All and Invert. Nothing is selected until you choose. Choices are remembered.
- **Whole vs partial.** An album you include entirely ("whole album") picks up new photos automatically. If you
  hand-pick photos in it, new photos are listed but left out until you select them.
- **Stays up to date.** While Kaleido is running it rescans chosen albums and folders at launch and about once a
  day (and shortly after Photos reports a change). New photos join the rotation, vanished ones leave. "Sync now"
  does it on demand. Options skip screenshots and small photos; videos are always skipped.
- **Slow by default.** Scenes last 90 seconds and cross-fade over 12, with dissolve, iris, zoom-through and
  segment transitions (or random), for every change; Zoom through is a gentle glide (about 1.6x, at least 6 s).
  Each photo keeps its own position, zoom and swirl while they cross-fade, so a saved scene arrives
  already in place instead of the old one sliding and zooming into it. Photos come in shuffled order (each once
  per round) or in order.
- **Good citizen.** 30 or 60 fps cap, 30 fps in Low Power Mode, optional pause on battery, pauses while the
  display is asleep or the screen is locked, and stops drawing when a window fully covers the desktop.
- **Menu bar item** with Play/Stop, Next photo and New Random Scene. Closing the window keeps playback running.
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
3. Tune the scene with Edit scene, or leave the dice on for new patterns.
4. **Stop** or quit to get your wallpaper back.

Open an album and press **Play album** to play only its selected photos as a slideshow (the mini-player shows
which album, with ✕ to go back to everything). Hover a thumbnail and press ▶︎ to play that photo or video right now, selected or not; it stays until Next or Back. Right-click a thumbnail for "Play now", "Reveal in Finder" and "Remove from library". Saved scenes remember the photo itself, so they still play when its album is unticked; a scene whose photo is gone keeps its look and can take the photo on screen ("Use the photo on screen" in Scenes).

## How it works

- `Sources/KaleidoCore`: settings, looks, scenes, the photo library (bookmarks plus path fallback), the shuffle
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
`Kaleido --stress-render folder [--seconds 600 --per-photo 10]` plays every photo and video in a folder through the
real renderer off screen at 30 fps and logs memory every 30 s, for hunting leaks without touching the desktop.

**Keeping the Mac cool:** the desktop is drawn at Settings > Performance > Desktop sharpness: Balanced (the default)
draws about half the pixels of Full Retina, Light a quarter, and the system scales the picture up smoothly. Low
Power Mode draws Light at 30 fps. Drawing stops whenever the desktop is covered, the display sleeps or the screen
locks.

## Limitations

- Photos albums import at most the 3000 most recent photos each. Photos stay in Photos; Kaleido asks PhotoKit for
  a display-sized copy (iCloud-only photos are downloaded on demand and skipped if that fails).
- Photos access is requested only when you click "Connect Photos…". The build script signs with a fixed
  requirement so the grant survives rebuilds.
- The app is not sandboxed and is ad-hoc signed. Adding folders like Desktop or Documents may trigger a macOS
  privacy prompt.
- Desktop-level windows are hidden by macOS in some modes (full-screen apps, Mission Control animations).
- Stage Manager's "click wallpaper to show desktop" may treat the animation like the wallpaper; untested.
