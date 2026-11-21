#!/bin/bash
# Regenerates THIRD_PARTY_NOTICES.md from the resolved dependencies' license files.
# MIT and Apache-2.0 require shipping these notices with the app; this keeps you compliant.
set -euo pipefail
cd "$(dirname "$0")/.."
swift package resolve >/dev/null
OUT=THIRD_PARTY_NOTICES.md
{
  echo "# Third-party notices"
  echo
  echo "MacTerm+ includes the following open-source components. All use permissive licenses (MIT or Apache-2.0)."
  echo
  for d in .build/checkouts/*; do
    f=$(ls "$d" | grep -iE '^(license|licence)' | head -1 || true)
    [ -z "$f" ] && continue
    echo "## $(basename "$d")"
    echo
    echo '```'
    cat "$d/$f"
    echo '```'
    echo
  done
} > "$OUT"
echo "Wrote $OUT"
