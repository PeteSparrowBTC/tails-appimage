#!/bin/bash
#
# Template. Checks an AppImage against SHA256SUMS and launches it only if they match.
#
# Adapt: replace yourapp with your application's name in the glob below. Everything else is
# generic.
#
# Written for someone at an offline Tails machine who does not use a terminal and has no
# documentation except the file beside this one. Three properties matter, and each is the
# difference between a check and the appearance of one.
#
#   Output goes through zenity. A script launched from a file manager has no terminal, so
#   anything printed goes nowhere, and a check that fails silently is worse than no check
#   because it teaches the user that silence means success. Tails ships zenity 4.1.90. The
#   stderr fallback is for CI, which has no display.
#
#   It launches the app on success. If it only verified, launching would be a separate step and
#   verifying would be the optional one that gets dropped.
#
#   It does not overclaim. SHA256SUMS travels in the same folder as the app, so whoever could
#   replace one could replace both. This proves the file was not damaged, half-copied or altered
#   on the stick. It does not prove the download was genuine.
#
# The AppImage should be stored in the zip NON-executable (644). Then it cannot run until this
# script has checked it, which stops the fastest route to the app being the one that skips the
# check. This script sets the bit itself, after the hash matches.

set -u

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CHECK_ONLY="${1:-}"

have_zenity() { command -v zenity >/dev/null 2>&1; }

fail() {
    if have_zenity; then
        zenity --error --width=460 --title="yourapp" --text="$1" 2>/dev/null
    else
        printf 'ERROR: %s\n' "$1" >&2
    fi
    exit 1
}

confirm() {
    if have_zenity; then
        zenity --question --width=460 --title="yourapp" \
               --ok-label="Start the app" --cancel-label="Not now" --text="$1" 2>/dev/null
    else
        printf '%s\n' "$1"
    fi
}

cd "$HERE" || fail "Could not open the folder this file is in."

[ -f SHA256SUMS ] || fail "SHA256SUMS is missing from this folder. Extract the whole zip again, and keep the files together."

shopt -s nullglob
apps=(yourapp-*-x86_64.AppImage)
shopt -u nullglob

[ "${#apps[@]}" -eq 1 ] || fail "Expected exactly one copy of the app in this folder, found ${#apps[@]}. Extract the whole zip again."
app="${apps[0]}"

# The check. One line of coreutils, the same command the documentation gives for doing it by
# hand, so what runs and what a reader can reproduce are not two different things.
if ! sha256sum --check --status SHA256SUMS 2>/dev/null; then
    fail "DO NOT USE THIS FILE.

The app in this folder is not the file that was packaged with these instructions. It may have been damaged while copying, or changed by something else.

Expected: $(awk '{print $1}' SHA256SUMS | head -1)
Found:    $(sha256sum "$app" 2>/dev/null | awk '{print $1}')

Delete it and get a fresh copy from whoever gave you this."
fi

# For CI: verify and exit, without trying to open a window on a machine with no display.
if [ "$CHECK_ONLY" = "--check-only" ]; then
    printf 'OK: %s matches SHA256SUMS.\n' "$app"
    exit 0
fi

# Only now does the app become runnable. chmod also covers the case where the archive was
# extracted by something that dropped the modes.
chmod +x "$app" 2>/dev/null

# If the bit still will not stick, the folder is on media mounted noexec, which is the normal
# state of a USB stick and needs a different fix from a different message.
if [ ! -x "$app" ]; then
    fail "The app cannot be started from where it is.

This usually means the folder is still on the USB stick, and programs are not allowed to run from a stick.

Copy this whole folder into your Home folder, open it there, and run this file again."
fi

confirm "The app has been checked and is the file that came with these instructions.

This confirms the file was not damaged or altered. It cannot prove the download itself was genuine; that is what whoever gave you this vouched for.

Press Start to open it." || exit 0

./"$app" || fail "The app did not start. If this folder is on the USB stick, copy it into your Home folder and try again from there."
