# Kaleido

<p align="center"><img src="site/images/desktop-poster.jpg" alt="Kaleido playing a rose photo as a kaleidoscope on a Mac desktop" width="820"></p>

<h2 align="center"><em>Reimagine</em> your photos</h2>

<p align="center">For macOS 26 · Native Swift and Metal · No accounts, no cloud</p>

Kaleido turns your photos, and macOS's own slow-motion aerial films, into slowly turning kaleidoscopes that play
on your Mac's desktop. It never touches your wallpaper settings: press Stop or quit, and your normal wallpaper is
simply back. The landing page lives in [`site/`](site/).

## Bring life to your photos

| Original | Kaleido |
| --- | --- |
| <img src="site/images/compare-dahlia-original.webp" alt="A pink dahlia" width="400"> | <img src="site/images/compare-dahlia-poster.jpg" alt="The dahlia as a kaleidoscope" width="400"> |
| <img src="site/images/compare-grevillea-original.webp" alt="A red and yellow grevillea" width="400"> | <img src="site/images/compare-grevillea-poster.jpg" alt="The grevillea as a kaleidoscope" width="400"> |

## And macOS's aerial films

The slow-motion aerials behind macOS's own screen savers play too, as moving kaleidoscopes.

| Original | Kaleido |
| --- | --- |
| <img src="site/images/aerial-seafloor-original.webp" alt="The sea floor aerial" width="400"> | <img src="site/images/aerial-seafloor-kaleido.webp" alt="The sea floor as a kaleidoscope" width="400"> |
| <img src="site/images/aerial-kelp-original.webp" alt="The kelp forest aerial" width="400"> | <img src="site/images/aerial-kelp-kaleido.webp" alt="The kelp forest as a kaleidoscope" width="400"> |

## Features

**Your desktop, alive.** Press Play and the kaleidoscope fills your desktop, slowly turning behind your icons and
windows. Press Stop and your usual wallpaper is back.

<img src="site/images/feature-desktop.webp" alt="A Mac desktop with a flower kaleidoscope behind the menu bar and Dock" width="820">

**A new toy to play with.** Flip through scenes, click and drag, flick it to watch it glide.

**Shape every pattern.** Have fun playing with the pattern editor. Many knobs and dials to tune. Or keep things
random :)

<img src="site/images/feature-editor.webp" alt="The pattern editor beside a kaleidoscope with its mirrors traced in red" width="820">

**Pick what plays.** Browse and choose your photos, built-in sets and smart albums to play.

<img src="site/images/feature-photos.webp" alt="The Photos browser" width="820">

**Keep the ones you love.** Bookmark a scene to save the photo with its pattern. Star your favorites, then play
your scenes as a playlist.

<img src="site/images/feature-scenes.webp" alt="The Scenes list" width="820">

## Install

Requires macOS 26 or later (it uses Liquid Glass) and Xcode (or the Swift toolchain).

```sh
cd ~/Projects/kaleido
./scripts/build.sh            # builds build/Kaleido.app
./scripts/install.sh          # builds and installs to /Applications (quits and relaunches a running copy)
open build/Kaleido.app
```

Run the tests with `swift test`.
