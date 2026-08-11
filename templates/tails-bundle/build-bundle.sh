#!/bin/bash
#
# Template. Assembles the Tails bundle and asserts the two things about it that are not
# self-evident, so a defect is a build failure rather than a download.
#
# Call this from BOTH your release job and your pull-request job, so the artifact that gets
# reviewed is the artifact that gets published. A bundle assembled only on a tag has its
# verification step exercised for the first time by whoever downloads it.
#
# Usage: build-bundle.sh <path-to-appimage> <version> [output-directory]

set -euo pipefail

appimage_path="${1:?path to the AppImage is required}"
version="${2:?version is required}"
outdir="${3:-.}"

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
appimage_name="$(basename "$appimage_path")"
bundle="yourapp-${version}-tails"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# One top-level folder inside the zip, so extracting produces a folder rather than four loose
# files in whatever directory the user happened to be in. The instructions name that folder, so
# the two have to agree.
work="${staging}/${bundle}"
mkdir -p "$work"

cp "$appimage_path" "$work/$appimage_name"
cp "${here}/start-here.sh" "$work/start-here.sh"

# Generated here, from the file actually being shipped, with a bare filename so that
# `sha256sum -c` works from inside the folder wherever it is extracted. Never copy a hash
# between files.
( cd "$work" && sha256sum "$appimage_name" > SHA256SUMS )
sha256="$(awk '{print $1}' "$work/SHA256SUMS")"

# The instructions quote the version and the hash. Substituted from the same two values the rest
# of the bundle is built from, so a reader comparing the text against SHA256SUMS cannot be shown
# two different numbers.
sed -e "s/@VERSION@/${version}/g" -e "s/@SHA256@/${sha256}/g" \
    "${here}/READ-THIS-FIRST.txt" > "$work/READ-THIS-FIRST.txt"

grep -q "@VERSION@\|@SHA256@" "$work/READ-THIS-FIRST.txt" && {
    echo "A placeholder survived substitution." >&2; exit 1; }

# The AppImage is deliberately NOT executable: it must not be runnable until start-here.sh has
# checked it, or double-clicking the app becomes an easier route than the check. start-here.sh
# sets the bit once the hash matches.
chmod 755 "$work/start-here.sh"
chmod 644 "$work/$appimage_name" "$work/SHA256SUMS" "$work/READ-THIS-FIRST.txt"

mkdir -p "$outdir"
outdir="$(cd "$outdir" && pwd)"
( cd "$staging" && zip -qr "${outdir}/${bundle}.zip" "$bundle" )

# --------------------------------------------------------------------------------------------
# Assertion 1: the archive stores the modes intended. Info-ZIP writes Unix modes into the
# central directory and Archive Manager on Tails restores them, but that is a property of the
# tools rather than a certainty, and both directions matter here: the script has to arrive
# runnable and the AppImage has to arrive not runnable.
# --------------------------------------------------------------------------------------------
command -v zipinfo >/dev/null || { echo "zipinfo is needed to verify the bundle." >&2; exit 1; }
zipinfo "${outdir}/${bundle}.zip"

zipinfo "${outdir}/${bundle}.zip" | grep -qE "^-rwxr-xr-x.* ${bundle}/start-here\.sh$" || {
    echo "start-here.sh is not stored executable, so extracting it cannot produce a runnable file." >&2
    exit 1; }

zipinfo "${outdir}/${bundle}.zip" | grep -qE "^-rw-r--r--.* ${bundle}/${appimage_name//./\\.}$" || {
    echo "The AppImage is stored executable, so it can be launched without being checked." >&2
    exit 1; }

# --------------------------------------------------------------------------------------------
# Assertion 2: the checker refuses what it must. A verification that has never failed is not
# known to work. There is no zenity on a runner, so this also exercises the stderr fallback.
# --------------------------------------------------------------------------------------------
( cd "$work" && ./start-here.sh --check-only )

tampered="${staging}/tampered"
cp -r "$work" "$tampered"
printf 'x' >> "${tampered}/${appimage_name}"
if ( cd "$tampered" && ./start-here.sh --check-only ) 2>/dev/null; then
    echo "The checker accepted a corrupted AppImage. It is decoration, not a check." >&2
    exit 1
fi

rm -f "${tampered}/SHA256SUMS"
if ( cd "$tampered" && ./start-here.sh --check-only ) 2>/dev/null; then
    echo "The checker passed with no SHA256SUMS present." >&2
    exit 1
fi

echo "${bundle}.zip is assembled and verified."
