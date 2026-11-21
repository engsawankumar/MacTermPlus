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
ZIP="dist/MacTermPlus-$VERSION.zip"

if [[ "$GITHUB_REPO" == OWNER/* || -z "$GITHUB_REPO" ]] && [ $DRY_RUN -eq 0 ]; then
  echo "Set GITHUB_REPO in release.config first (e.g. yourname/MacTermPlus)." >&2; exit 1
fi

echo "▸ Building MacTerm+ $VERSION for $GITHUB_REPO"
VERSION="$VERSION" GITHUB_REPO="$GITHUB_REPO" ./scripts/build-app.sh

echo "▸ Packaging"
rm -f "$ZIP" "$ZIP.sha256"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "dist/MacTerm+.app" "$ZIP"
(cd dist && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
cat "$ZIP.sha256"

# Release notes: the CHANGELOG section for this version.
NOTES="$(mktemp)"
awk -v v="$VERSION" '$0 ~ "^## "v"$" {f=1; next} /^## / {f=0} f' CHANGELOG.md > "$NOTES"
[ -s "$NOTES" ] || echo "MacTerm+ $VERSION" > "$NOTES"
{
  echo
  echo "---"
  echo "**Install:** download \`$(basename "$ZIP")\`, unzip, move **MacTerm+** to Applications."
  echo "First launch of a build not signed by Apple: right-click the app → **Open** → **Open**."
  echo "Already installed? Use **MacTerm+ → Check for Updates…**"
} >> "$NOTES"

if [ $DRY_RUN -eq 1 ]; then
  echo "▸ Dry run — files ready in dist/:"; ls -lh dist/ | grep -E "zip"; echo; cat "$NOTES"; exit 0
fi

command -v gh >/dev/null || { echo "Install the GitHub CLI (brew install gh) and run: gh auth login" >&2; exit 1; }
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists on github.com/$GITHUB_REPO — nothing to do."; exit 0
fi
echo "▸ Publishing $TAG to github.com/$GITHUB_REPO"
gh release create "$TAG" "$ZIP" "$ZIP.sha256" --repo "$GITHUB_REPO" --title "MacTerm+ $VERSION" --notes-file "$NOTES"
echo "✓ Released. Users get it from MacTerm+ → Check for Updates."
