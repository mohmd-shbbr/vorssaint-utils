#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
# Install on the same filesystem using a verified candidate and reversible swaps.
set -euo pipefail
SOURCE_APP="$1"
APP_PATH="$2"
APP_PARENT=$(dirname "$APP_PATH")
mkdir -p "$APP_PARENT"
# A user-owned bundle may remain writable after temporary admin membership ends.
# In that case swap Contents inside the existing bundle, on the same filesystem.
CONTENTS_ONLY=false
STAGING_PARENT="$APP_PARENT"
if [[ ! -w "$APP_PARENT" && -d "$APP_PATH/Contents" && -w "$APP_PATH" ]]; then
    CONTENTS_ONLY=true
    STAGING_PARENT="${TMPDIR:-/tmp}"
fi
STAGING=$(mktemp -d "$STAGING_PARENT/.vorssaint-update.XXXXXX")
if [[ "$CONTENTS_ONLY" = true && "$(/usr/bin/stat -f %d "$STAGING")" != "$(/usr/bin/stat -f %d "$APP_PATH")" ]]; then
    rmdir "$STAGING"
    echo 'Cannot stage a safe update on the app filesystem.' >&2
    exit 1
fi
SUCCESS=false
WAS_RUNNING=false
cleanup() {
    local status=$?
    if [[ "$SUCCESS" != true && -d "$STAGING/previous-contents" ]]; then
        if [[ -e "$APP_PATH/Contents" ]]; then mv "$APP_PATH/Contents" "$STAGING/failed-contents"; fi
        mv "$STAGING/previous-contents" "$APP_PATH/Contents"
    fi
    if [[ "$SUCCESS" != true && -d "$STAGING/previous.app" ]]; then
        if [[ -e "$APP_PATH" ]]; then mv "$APP_PATH" "$STAGING/failed.app"; fi
        mv "$STAGING/previous.app" "$APP_PATH"
    fi
    if [[ "$SUCCESS" != true && "$WAS_RUNNING" = true && -d "$APP_PATH" ]]; then
        /usr/bin/open -g "$APP_PATH" || true
    fi
    rm -rf "$STAGING"
    return "$status"
}
trap cleanup EXIT
/usr/bin/ditto --noextattr --noqtn "$SOURCE_APP" "$STAGING/candidate.app"
/usr/bin/codesign --verify --deep --strict "$STAGING/candidate.app"
# Stop only the exact installed executable, never another app or a test fixture.
for pid in $(/usr/bin/pgrep -x VorssaintDeveloper || true); do
    executable=$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)
    if [[ "$executable" = "$APP_PATH/Contents/MacOS/VorssaintDeveloper" ]]; then
        WAS_RUNNING=true
        kill -TERM "$pid"
        for attempt in {1..25}; do
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 0.2
        done
        if kill -0 "$pid" 2>/dev/null; then echo 'App did not quit; update deferred.' >&2; exit 1; fi
    fi
done
if [[ "$CONTENTS_ONLY" = true ]]; then
    mv "$APP_PATH/Contents" "$STAGING/previous-contents"
    mv "$STAGING/candidate.app/Contents" "$APP_PATH/Contents"
else
    if [[ -e "$APP_PATH" ]]; then mv "$APP_PATH" "$STAGING/previous.app"; fi
    mv "$STAGING/candidate.app" "$APP_PATH"
fi
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
SUCCESS=true
if [[ "$WAS_RUNNING" = true ]]; then /usr/bin/open -g "$APP_PATH"; fi
printf 'Installed: %s\n' "$APP_PATH"
