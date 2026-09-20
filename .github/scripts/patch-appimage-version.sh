#!/usr/bin/env bash
#
# Patches the flutter_distributor / fastforge AppImage maker so the generated
# .desktop file inside the AppImage contains X-AppImage-Version.
#
# Background:
# - GearLever displays the AppImage version ONLY from the embedded .desktop key
#   `X-AppImage-Version` (see AppImageProvider._get_app_version). Without it,
#   GearLever falls back to the first 6 chars of the file md5 (or blank).
# - MakeAppImageConfig.desktopFileContent never emitted that key, so every
#   Harmony-Music AppImage was affected. DEB/RPM were fine (they use
#   pubspec version natively).
# - The value used is `appBuildName` (pubspec build-name without +build-number,
#   e.g. `1.13.1` from `1.13.1+29`), matching the GitHub tag `v1.13.1`.
#
# Usage (CI, AFTER `dart pub global activate flutter_distributor`):
#   bash .github/scripts/patch-appimage-version.sh
#
# Idempotent: files already containing X-AppImage-Version are skipped, so a
# future upstream fix won't break CI.
set -euo pipefail

PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
PATTERN="flutter_app_packager*/lib/src/makers/appimage/make_appimage_config.dart"

mapfile -t FILES < <(find "$PUB_CACHE" -path "*$PATTERN" 2>/dev/null || true)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "patch-appimage-version: no make_appimage_config.dart found under $PUB_CACHE" >&2
  ls "$PUB_CACHE" >&2 || true
  exit 1
fi

patched=0
skipped=0
for f in "${FILES[@]}"; do
  echo "Checking $f"
  if grep -q "X-AppImage-Version" "$f"; then
    echo "  already contains X-AppImage-Version, skipping (upstream may have fixed it)"
    skipped=$((skipped + 1))
    continue
  fi
  if ! grep -q "'Type': 'Application'," "$f"; then
    echo "  ERROR: anchor \"'Type': 'Application',\" not found in $f, maker source may have changed" >&2
    exit 1
  fi
  perl -0pi -e "s/'Type': 'Application',/'Type': 'Application',\n      'Version': '1.0',\n      'X-AppImage-Version': appBuildName,/g" "$f"
  if grep -q "X-AppImage-Version" "$f"; then
    echo "  patched OK"
    patched=$((patched + 1))
  else
    echo "  ERROR: patch applied but key not found in $f" >&2
    exit 1
  fi
done

echo "patch-appimage-version: patched=$patched skipped=$skipped"
