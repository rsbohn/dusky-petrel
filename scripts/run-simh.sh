#!/usr/bin/env bash
# Build and boot CVIT/Nova in SIMH. Ctrl-E returns to the SIMH prompt.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA="${SIMH_NOVA:-nova}"
command -v "$SIMH_NOVA" >/dev/null 2>&1 || { echo "SIMH Nova not found: $SIMH_NOVA" >&2; exit 1; }
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
scripts/build-image.sh "$WORKDIR/cvit-dsk.img"
printf 'attach dsk "%s/cvit-dsk.img"\nboot dsk\n' "$WORKDIR" > "$WORKDIR/simh.ini"
"$SIMH_NOVA" "$WORKDIR/simh.ini"
