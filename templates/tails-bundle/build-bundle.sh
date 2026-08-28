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
#
# Checked in BOTH directions, which is the part that is easy to miss. A placeholder that SURVIVES
# is an obvious failure, and the grep below catches it. A placeholder that was never in the source
# is a silent one: the sed succeeds, the build passes, and the instructions simply stop quoting the
# fingerprint, so a reader who wanted to compare it by hand finds nothing to compare against.
# Editing the prose is exactly how that happens.
for placeholder in "@VERSION@" "@SHA256@"; do
    grep -qF "$placeholder" "${here}/READ-THIS-FIRST.txt" || {
        echo "${placeholder} is not in READ-THIS-FIRST.txt, so nothing will be substituted for it." >&2
        exit 1; }
done

sed -e "s/@VERSION@/${version}/g" -e "s/@SHA256@/${sha256}/g" \
    "${here}/READ-THIS-FIRST.txt" > "$work/READ-THIS-FIRST.txt"

grep -q "@VERSION@\|@SHA256@" "$work/READ-THIS-FIRST.txt" && {
    echo "A placeholder survived substitution." >&2; exit 1; }

# The AppImage is deliberately NOT executable: it must not be runnable until start-here.sh has
# checked it, or double-clicking the app becomes an easier route than the check. start-here.sh
# sets the bit once the hash matches.
chmod 755 "$work/start-here.sh"
chmod 644 "$work/$appimage_name" "$work/SHA256SUMS" "$work/READ-THIS-FIRST.txt"

# --------------------------------------------------------------------------------------------
# Assertion 1: the checker refuses what it must, AND refuses for the reason under test.
#
# Runs BEFORE the zip is written. What the checker does is a property of the staged folder rather
# than of the archive, so nothing here needs the zip to exist. The failure arrives sooner, and
# the block can be run on a machine with no zip installed, which includes Tails itself and a
# Windows checkout under Git Bash.
#
# A verification that has never failed is not known to work. A refusal test that reads only the
# exit code is the next trap along: it passes when the script fails for an unrelated reason, and
# the case it was written for has then quietly stopped being covered.
#
# The old version of this block was an example of it. Deleting SHA256SUMS from a folder whose
# AppImage was ALREADY corrupted still refuses through the hash branch, so a broken
# missing-fingerprint branch would have looked tested. Each case below states the message it
# expects, and the folder is restored between cases.
#
# There is no zenity on a runner, so this also exercises the stderr fallback.
# --------------------------------------------------------------------------------------------
tampered="${staging}/tampered"

refuses_with() {
    local expected="$1"
    local output

    if output="$( cd "$tampered" && ./start-here.sh --check-only 2>&1 )"; then
        echo "The checker accepted the folder. Expected a refusal saying: ${expected}" >&2
        exit 1
    fi

    printf '%s' "$output" | grep -qF "$expected" || {
        echo "The checker refused, but not for the expected reason." >&2
        echo "expected to see: ${expected}" >&2
        echo "what it said:    ${output}" >&2
        exit 1; }

    echo "It refused, as it must: ${expected}"
}

( cd "$work" && ./start-here.sh --check-only )

cp -r "$work" "$tampered"
printf 'x' >> "${tampered}/${appimage_name}"
refuses_with "DO NOT USE THIS FILE"

# The launcher globs for the app so the version can change without editing the script, which
# means it can find more than one. Picking either would be a coin flip over which file gets
# launched, and the one it did not pick is the one somebody left behind.
cp "${work}/${appimage_name}" "${tampered}/${appimage_name}"
cp "${work}/${appimage_name}" "${tampered}/yourapp-0.0.0-x86_64.AppImage"
refuses_with "found 2"

rm -f "${tampered}/yourapp-0.0.0-x86_64.AppImage" "${tampered}/SHA256SUMS"
refuses_with "SHA256SUMS is missing"

mkdir -p "$outdir"
outdir="$(cd "$outdir" && pwd)"
( cd "$staging" && zip -qr "${outdir}/${bundle}.zip" "$bundle" )

# --------------------------------------------------------------------------------------------
# Assertion 2: the archive stores the modes intended. Info-ZIP writes Unix modes into the
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

echo "${bundle}.zip is assembled and verified."
