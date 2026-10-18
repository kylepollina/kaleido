#!/bin/bash
# Builds build/Kaleido.app. Pass --install to also copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Kaleido.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Kaleido"

if [ ! -f build/AppIcon.icns ] || [ Resources/icon-source.png -nt build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
    mkdir -p build/AppIcon.iconset
    swift scripts/make-icon.swift build/icon-1024.png
    for size in 16 32 128 256 512; do
        sips -z $size $size build/icon-1024.png --out build/AppIcon.iconset/icon_${size}x${size}.png >/dev/null
        sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out build/AppIcon.iconset/icon_${size}x${size}@2x.png >/dev/null
    done
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kaleido"
# SwiftPM records the deployment target (macOS 14) as the SDK version, which makes AppKit run
# the app in compatibility mode with no Liquid Glass. Record the real SDK it was built with.
vtool -set-build-version macos 14.0 "$(xcrun --show-sdk-version)" -replace \
    -output "$APP/Contents/MacOS/Kaleido" "$APP/Contents/MacOS/Kaleido"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signing normally ties macOS privacy grants (Photos) to this exact build, so every rebuild would
# ask again. A fixed designated requirement keeps the grant across rebuilds.
codesign --force --sign - --requirements '=designated => identifier "local.kaleido.app"' "$APP" >/dev/null

echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    # Quit a running copy first (its desktop windows go away with it), then reopen the new one.
    was_running=false
    if pgrep -x Kaleido >/dev/null; then
        was_running=true
        osascript -e 'quit app "Kaleido"' 2>/dev/null || true
        for _ in $(seq 1 20); do pgrep -x Kaleido >/dev/null || break; sleep 0.25; done
    fi
    rm -rf /Applications/Kaleido.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Kaleido.app"
    if $was_running; then open /Applications/Kaleido.app; echo "Relaunched Kaleido"; fi
fi
