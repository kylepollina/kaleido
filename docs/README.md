# Kaleido landing page

A one-page static site: `index.html` (inline CSS, one tiny inline script, Google Fonts only) plus `images/`. No build step.

**Preview locally:** open `docs/index.html` in a browser, or run `cd docs && python3 -m http.server 8000` and visit http://localhost:8000.

## The hero video

`images/desktop-loop*.mp4` is a 40-second screen recording of Kaleido on the desktop, scaled to 1280×832 at 30 fps.
Its last 3 seconds cross-fade into its first 3 (a plain fade, so the menu bar and Dock, the same in both, stay put),
so `loop` never shows a seam. Two encodes: AV1
(`libsvtav1 -crf 38`, about 3.6 MB) for browsers that play it, H.264 (`libx264 -crf 27 -preset veryslow`, about
5.3 MB) for the rest; `desktop-poster.jpg` is its first frame. With "Reduce motion" on, the poster shows instead.

## The comparison carousel

Each example is `compare-NAME-original.webp` (a window screenshot of Original, cropped to the photo) on top of
`compare-NAME.mp4` / `-av1.mp4` (a window recording of Kaleido playing it, cropped to the same rectangle, scaled to
1280×804, last 3 seconds cross-faded into the first like the hero video), with `compare-NAME-poster.jpg` as its first
frame. Window recordings at 2236×1710 crop with `crop=2008:1261:114:168`; window screenshots at 2000×1530 with
`crop=1796:1128:102:150`. To add one, copy a `.slide` in `index.html`; the dots fill in by themselves.

## Publishing

GitHub Pages serves this folder from `main` (Settings → Pages → Deploy from a branch → `main` / `/docs`) at
getkaleido.app, so every push to `main` that changes it goes live. `CNAME` holds the domain, and `.nojekyll` makes
Pages serve the files as they are.

## When a download exists

The hero and the `#download` section just say "Coming soon". Add the real download link to both once a signed build
exists.
