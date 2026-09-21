#!/usr/bin/env bash
#
# Injects X-AppImage-Version into already-built AppImages and repacks them.
#
# Background:
# - GearLever displays the AppImage version ONLY from the embedded .desktop key
#   `X-AppImage-Version` (AppImageProvider._get_app_version). Without it,
#   GearLever falls back to the first 6 chars of the file md5 (or blank).
# - The flutter_distributor/fastforge AppImage maker never emits that key,
#   and patching its pub-cache source is ineffective because
#   `dart pub global activate` precompiles the tool to a snapshot before we
#   could patch it. So we fix the artifact itself: extract, edit, repack.
# - Version source is EXPECTED_VERSION (setup job `name` output = pubspec
#   build-name without +build-number, e.g. `1.14.0` from `1.14.0+30`),
#   matching the GitHub tag `v1.14.0`. Nothing is hardcoded: bump
#   `version:` in pubspec.yaml and CI follows automatically.
#
# Usage (CI, AFTER `flutter_distributor package`, BEFORE verify/upload):
#   EXPECTED_VERSION=1.14.0 bash .github/scripts/inject-appimage-version.sh
#
# Idempotent: re-running replaces the value instead of duplicating the key,
# so a future upstream fix that emits the key natively becomes a value
# replace no-op.
set -euo pipefail

: "${EXPECTED_VERSION:?EXPECTED_VERSION env var must be set (e.g. 1.14.0)}"

if ! command -v appimagetool >/dev/null 2>&1; then
  echo "inject-appimage-version: appimagetool not found on PATH" >&2
  exit 1
fi

mapfile -t IMAGES < <(find dist -name '*.AppImage' -type f)
if [ "${#IMAGES[@]}" -eq 0 ]; then
  echo "inject-appimage-version: no AppImage found under dist/" >&2
  exit 1
fi

for img in "${IMAGES[@]}"; do
  echo "Injecting X-AppImage-Version=$EXPECTED_VERSION into $img"
  chmod +x "$img"
  tmpdir=$(mktemp -d)
  img_abs="$PWD/$img"
  # Full extract: repack needs the whole AppDir, not just the .desktop file.
  (cd "$tmpdir" && "$img_abs" --appimage-extract >/dev/null)
  desktop=$(find "$tmpdir/squashfs-root" -maxdepth 1 -name '*.desktop' | head -1)
  if [ -z "$desktop" ]; then
    echo "inject-appimage-version: no .desktop file at AppDir root of $img" >&2
    rm -rf "$tmpdir"
    exit 1
  fi
  echo "--- $desktop (before) ---"
  cat "$desktop"
  echo "--- end (before) ---"
  if grep -q '^X-AppImage-Version=' "$desktop"; then
    sed -i "s|^X-AppImage-Version=.*|X-AppImage-Version=${EXPECTED_VERSION}|" "$desktop"
  else
    if ! grep -q '^Version=' "$desktop"; then
      sed -i '/^Type=Application$/a Version=1.0' "$desktop"
    fi
    sed -i "/^Type=Application\$/a X-AppImage-Version=${EXPECTED_VERSION}" "$desktop"
  fi
  count=$(grep -c '^X-AppImage-Version=' "$desktop" || true)
  if [ "$count" != "1" ]; then
    echo "inject-appimage-version: expected exactly 1 X-AppImage-Version key, found $count" >&2
    rm -rf "$tmpdir"
    exit 1
  fi
  grep -q "^X-AppImage-Version=${EXPECTED_VERSION}$" "$desktop"
  echo "--- $desktop (after) ---"
  cat "$desktop"
  echo "--- end (after) ---"
  ARCH=x86_64 appimagetool --no-appstream "$tmpdir/squashfs-root" "$tmpdir/out.AppImage" >/dev/null
  chmod +x "$tmpdir/out.AppImage"
  mv "$tmpdir/out.AppImage" "$img"
  rm -rf "$tmpdir"
  echo "Repacked $img"
done

echo "inject-appimage-version: done (${#IMAGES[@]} AppImage(s), version=$EXPECTED_VERSION)"
