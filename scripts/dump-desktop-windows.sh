#!/bin/bash
# Lists every window at or below the desktop-icon level (wallpaper, Kaleido, Portal and similar apps) from the
# live window server: owner, level, bounds, alpha, sharing state, on-screen flag, front-to-back order.
# Usage: scripts/dump-desktop-windows.sh [output-file]
out="${1:-/dev/stdout}"
swift - > "$out" <<'SWIFT'
import CoreGraphics
let icons = Int(CGWindowLevelForKey(.desktopIconWindow))
print("desktop level \(CGWindowLevelForKey(.desktopWindow)), icon level \(icons)")
var order = 0
for w in CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as! [[String: Any]] {
    order += 1
    let layer = w["kCGWindowLayer"] as? Int ?? 0
    guard layer <= icons else { continue }
    let b = w["kCGWindowBounds"] as? [String: Any] ?? [:]
    print("#\(order) layer \(layer) owner \(w["kCGWindowOwnerName"] ?? "?") name '\(w["kCGWindowName"] ?? "")' id \(w["kCGWindowNumber"] ?? 0) frame \(b["X"] ?? 0),\(b["Y"] ?? 0) \(b["Width"] ?? 0)x\(b["Height"] ?? 0) alpha \(w["kCGWindowAlpha"] ?? 1) sharing \(w["kCGWindowSharingState"] ?? "?") onscreen \(w["kCGWindowIsOnscreen"] ?? false)")
}
SWIFT
