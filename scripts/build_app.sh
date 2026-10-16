#!/bin/bash
# Builds MacUtils.app (release) with an .icns generated from MacUtils/Resources/AppIcon.png
# and packages dist/MacUtils-<version>.zip.
# Usage: scripts/build_app.sh [version]   (defaults to the contents of ./VERSION)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(cat VERSION)}"
VERSION="${VERSION#v}"
BUILD="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="MacUtils.app"
ICON_SRC="MacUtils/Resources/AppIcon.png"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacUtils" "$APP/Contents/MacOS/MacUtils"
cp -R "$BIN_DIR"/MacUtils_MacUtils.bundle "$APP/Contents/Resources/" 2>/dev/null || true

# Icon: build every iconset size from the 1024px PNG
TMP="$(mktemp -d)"
sips -z 1024 1024 "$ICON_SRC" --out "$TMP/base.png" >/dev/null
mkdir "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/base.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/base.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$TMP"

cp MacUtils/App/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string MacUtils" \
                        -c "Add :CFBundleIconFile string AppIcon" \
                        -c "Set :CFBundleShortVersionString $VERSION" \
                        -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
# A stable signing identity (scripts/setup_signing.sh) keeps the Accessibility permission across rebuilds.
# Without one the app is ad-hoc signed, and macOS forgets the permission after every build.
# Look in the login keychain explicitly (CI uses its own keychain on the search list).
IDENTITY=""
KEYCHAIN_ARGS=()
for candidate in "MacUtils Release Signing" "MacUtils Local Signing"; do
  if security find-certificate -c "$candidate" >/dev/null 2>&1; then
    IDENTITY="$candidate"; break
  elif security find-certificate -c "$candidate" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
    IDENTITY="$candidate"; KEYCHAIN_ARGS=(--keychain "$HOME/Library/Keychains/login.keychain-db"); break
  fi
done
if [ "${SIGN_IDENTITY:-}" = "adhoc" ] || [ -z "$IDENTITY" ]; then
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
  echo "Signed ad-hoc (run scripts/setup_signing.sh once to keep permissions across rebuilds)"
else
  codesign --force --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$APP"
  echo "Signed with \"$IDENTITY\""
fi

mkdir -p dist
ZIP="dist/MacUtils-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $APP ($VERSION, build $BUILD) -> $ZIP"
