#!/bin/bash
# Build → relaunch → screenshot the Winamp window(s) for UI iteration.
# Usage: ./scripts/shoot.sh [--no-build]
#   Captures each on-screen Winamp window by window ID (works even when occluded)
#   to /tmp/winamp_shot*.png. Prints the paths so an agent can read them.
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="Debug"

if [[ "$1" != "--no-build" ]]; then
    xcodebuild -project "${PROJECT_DIR}/Winamp.xcodeproj" -scheme Winamp \
        -configuration "${CONFIG}" build >/tmp/winamp_build.log 2>&1 \
        || { echo "❌ build failed — see /tmp/winamp_build.log"; tail -20 /tmp/winamp_build.log; exit 1; }
fi

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Winamp-*/Build/Products/${CONFIG}/Winamp.app \
    -maxdepth 0 2>/dev/null | head -n 1)

# Relaunch fresh so the screenshot reflects the new build.
osascript -e 'tell application "Winamp" to quit' >/dev/null 2>&1 || true
pkill -x Winamp >/dev/null 2>&1 || true
sleep 0.5
open "$APP_PATH"
sleep 2.5

# Enumerate Winamp's on-screen windows (layer 0 = normal) and capture each by ID.
IDS=$(swift - <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String ?? "").contains("Winamp") {
    if (w[kCGWindowLayer as String] as? Int ?? 0) == 0 {
        print(w[kCGWindowNumber as String] as? Int ?? -1)
    }
}
SWIFT
)

i=0
for id in $IDS; do
    out="/tmp/winamp_shot${i}.png"
    screencapture -x -o -l"$id" "$out" && echo "📸 $out"
    i=$((i + 1))
done
if [[ $i -eq 0 ]]; then echo "⚠️  no Winamp windows found on screen"; fi
