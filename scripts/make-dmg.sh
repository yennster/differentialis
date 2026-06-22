#!/usr/bin/env bash
#
# Build a drag-to-Applications .dmg for Differentialis.
#
# Usage: scripts/make-dmg.sh <path-to-.app> <output.dmg> [volume-name]
#
# Prefers `create-dmg` for a nicely laid-out window with an Applications drop
# target; falls back to a plain `hdiutil` image (which still contains the
# Applications symlink, so drag-to-install always works) if create-dmg is
# unavailable or its cosmetic AppleScript step fails on a headless CI runner.

set -euo pipefail

APP="${1:?usage: make-dmg.sh <app> <output.dmg> [volume-name]}"
OUT="${2:?usage: make-dmg.sh <app> <output.dmg> [volume-name]}"
VOLNAME="${3:-Differentialis}"

if [ ! -d "$APP" ]; then
  echo "error: app bundle not found: $APP" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

# Ad-hoc sign so the bundle carries a valid (if not Developer-ID) signature.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

app_name="$(basename "$APP")"

# Preferred path: a polished DMG with an Applications drop link.
if command -v create-dmg >/dev/null 2>&1; then
  if create-dmg \
      --volname "$VOLNAME" \
      --window-pos 200 120 \
      --window-size 540 380 \
      --icon-size 110 \
      --icon "$app_name" 150 200 \
      --hide-extension "$app_name" \
      --app-drop-link 390 200 \
      --hdiutil-retries 5 \
      "$OUT" "$APP"; then
    echo "create-dmg produced $OUT"
  else
    echo "create-dmg exited non-zero; will verify / fall back."
  fi
fi

# Fallback: plain compressed DMG that still has the Applications symlink.
if [ ! -f "$OUT" ]; then
  echo "Falling back to hdiutil…"
  staging="$(mktemp -d)"
  cp -R "$APP" "$staging/"
  ln -s /Applications "$staging/Applications"
  hdiutil create -volname "$VOLNAME" -srcfolder "$staging" -ov -format UDZO "$OUT"
  rm -rf "$staging"
fi

echo "DMG ready: $OUT"
