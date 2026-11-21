#!/bin/bash
# Builds MacTerm+, packages it for the in-app updater, and publishes a GitHub release.
#
#   ./scripts/release.sh            # version from ./VERSION, publishes with the GitHub CLI (gh)
#   ./scripts/release.sh --dry-run  # build + package only (files in dist/)
#
# Before the first release: set GITHUB_REPO in release.config, run `gh auth login`,
# and add a "## <version>" section to CHANGELOG.md.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
VERSION="${VERSION:-$(cat VERSION)}"
GITHUB_REPO="${GITHUB_REPO:-$(grep -E '^GITHUB_REPO=' release.config | cut -d= -f2)}"
TAG="v$VERSION"
NAME="MacTerm+-$VERSION"
ZIP="dist/$NAME.zip"
DMG="dist/$NAME.dmg"

if [[ "$GITHUB_REPO" == OWNER/* || -z "$GITHUB_REPO" ]] && [ $DRY_RUN -eq 0 ]; then
  echo "Set GITHUB_REPO in release.config first (e.g. yourname/MacTermPlus)." >&2; exit 1
fi

if [ $DRY_RUN -eq 0 ] && command -v gh >/dev/null && gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists on github.com/$GITHUB_REPO — nothing to do."; exit 0
fi

echo "▸ Checking for private data"
python3 scripts/check-secrets.py
echo "▸ Building MacTerm+ $VERSION for $GITHUB_REPO"
VERSION="$VERSION" GITHUB_REPO="$GITHUB_REPO" ./scripts/build-app.sh

# Never publish builds that aren't signed with the permanent identity: users would be asked
# for Keychain and folder permissions again after updating.
if ! codesign -d -r- "dist/MacTerm+.app" 2>&1 | grep -q "certificate"; then
  if [ "${ALLOW_ADHOC:-0}" != "1" ]; then
    echo "✗ dist/MacTerm+.app is not signed with the MacTerm+ identity (run ./scripts/setup-signing.sh)." >&2
    echo "  Not publishing. (Set ALLOW_ADHOC=1 to override.)" >&2
    [ -n "${CI:-}" ] && exit 0 || exit 1
  fi
fi

echo "▸ Packaging zip"
rm -f "$ZIP" "$ZIP.sha256" "$DMG" "$DMG.sha256"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "dist/MacTerm+.app" "$ZIP"

echo "▸ Building DMG"
STAGE="$(mktemp -d)/MacTerm+"
mkdir -p "$STAGE"
/usr/bin/ditto "dist/MacTerm+.app" "$STAGE/MacTerm+.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MacTerm+ $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"

(cd dist && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256" && shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256")
cat "$ZIP.sha256" "$DMG.sha256"

# Release notes: the CHANGELOG section for this version.
NOTES="$(mktemp)"
awk -v v="$VERSION" '$0 ~ "^## "v"$" {f=1; next} /^## / {f=0} f' CHANGELOG.md > "$NOTES"
[ -s "$NOTES" ] || echo "MacTerm+ $VERSION" > "$NOTES"
{
  echo
  echo "---"
  echo "**Install:** download \`$NAME.dmg\`, open it and drag **MacTerm+** to **Applications** (or use \`$NAME.zip\`)."
  echo "First launch: if macOS says it can't check the app, open **System Settings → Privacy & Security** and click **Open Anyway**."
  echo "Already installed? Use **MacTerm+ → Check for Updates…**"
} >> "$NOTES"

if [ $DRY_RUN -eq 1 ]; then
  echo "▸ Dry run — files ready in dist/:"; ls -lh dist/ | grep -E "zip|dmg"; echo; cat "$NOTES"; exit 0
fi

command -v gh >/dev/null || { echo "Install the GitHub CLI (brew install gh) and run: gh auth login" >&2; exit 1; }
echo "▸ Publishing $TAG to github.com/$GITHUB_REPO"
gh release create "$TAG" "$DMG" "$DMG.sha256" "$ZIP" "$ZIP.sha256" --repo "$GITHUB_REPO" --title "MacTerm+ $VERSION" --notes-file "$NOTES"
echo "✓ Released. Users get it from MacTerm+ → Check for Updates."
