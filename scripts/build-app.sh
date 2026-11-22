#!/bin/bash
# Builds MacTerm+.app (Apple Silicon, release) into ./dist. Works with Xcode or just the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/MacTerm+.app"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
GITHUB_REPO="${GITHUB_REPO:-$(grep -E '^GITHUB_REPO=' release.config 2>/dev/null | cut -d= -f2)}"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/MacTermPlus"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacTermPlus"

if [ ! -f Resources/AppIcon.icns ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacTerm+</string>
  <key>CFBundleDisplayName</key><string>MacTerm+</string>
  <key>CFBundleIdentifier</key><string>app.macterm-plus</string>
  <key>CFBundleExecutable</key><string>MacTermPlus</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>MTPUpdateRepo</key><string>${GITHUB_REPO}</string>
  <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Bairagi. Built by Bairagi.</string>
</dict>
</plist>
PLIST

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${PROVISIONING_PROFILE:-}" ]; then
  # Developer ID build with the Keychain Sharing entitlement → enables iCloud Keychain.
  #   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" TEAM_ID=TEAMID \
  #   PROVISIONING_PROFILE=~/Downloads/MacTermPlus.provisionprofile [BUNDLE_ID=app.macterm-plus] ./scripts/build-app.sh
  BUNDLE_ID="${BUNDLE_ID:-app.macterm-plus}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
  cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  ENT="$(mktemp)"
  sed -e "s/TEAM_ID/$TEAM_ID/g" -e "s/BUNDLE_ID/$BUNDLE_ID/g" Resources/MacTermPlus.entitlements.template > "$ENT"
  codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$SIGN_IDENTITY" "$APP"
  echo "Signed with $SIGN_IDENTITY (iCloud Keychain enabled). Notarize before sharing: xcrun notarytool submit …"
elif [ -f "$HOME/.macterm-signing/signing.keychain-db" ]; then
  # Permanent MacTerm+ identity (scripts/setup-signing.sh): same signature every build, so macOS
  # keeps Keychain "Always Allow" choices and folder permissions across updates.
  KC="$HOME/.macterm-signing/signing.keychain-db"
  security unlock-keychain -p "$(cat "$HOME/.macterm-signing/keychain-password")" "$KC"
  codesign --force --deep --keychain "$KC" --sign "MacTerm+ Code Signing (Bairagi)" "$APP"
  echo "Signed with the permanent MacTerm+ identity."
else
  # Ad-hoc signature: runs on this Mac, but macOS asks for permissions again after each update.
  # Run ./scripts/setup-signing.sh once to fix that.
  codesign --force --deep --sign - "$APP"
  echo "Warning: ad-hoc signed (run ./scripts/setup-signing.sh for a permanent identity)." >&2
fi
echo "Built $APP"
