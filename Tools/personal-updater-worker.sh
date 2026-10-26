#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
REPOSITORY="$1"
BRANCH="$2"
STATE_DIR="$3"
CHECKOUT="$STATE_DIR/source"
if [[ -z "${VORSSAINT_UPDATER_APP_PATH:-}" ]]; then
    VORSSAINT_UPDATER_APP_PATH="$HOME/Applications/Vorssaint (Developer).app"
    if [[ -w /Applications || ( -d "/Applications/Vorssaint (Developer).app/Contents" && -w "/Applications/Vorssaint (Developer).app" ) ]]; then VORSSAINT_UPDATER_APP_PATH='/Applications/Vorssaint (Developer).app'; fi
fi
APP_PATH="$VORSSAINT_UPDATER_APP_PATH"
export GIT_TERMINAL_PROMPT=0
printf '[%s] Checking the personal fork\n' "$(date -u +%FT%TZ)"
if [[ ! -d "$CHECKOUT/.git" ]]; then
    /usr/bin/git clone --depth=1 --no-tags --single-branch --branch "$BRANCH" "$REPOSITORY" "$CHECKOUT"
fi
cd "$CHECKOUT"
[[ -z "$(git status --porcelain)" ]] || { echo 'Updater checkout has local changes; leaving them untouched.' >&2; exit 1; }
git fetch origin "refs/heads/$BRANCH"
CANDIDATE=$(git rev-parse FETCH_HEAD)
INSTALLED=$(cat "$STATE_DIR/installed-commit" 2>/dev/null || true)
if [[ "$CANDIDATE" = "$INSTALLED" ]] && [[ -d "$APP_PATH" ]]; then
    echo 'Custom app is up to date.'
    exit 0
fi
# Moving backwards or replacing unrelated history must be reviewed manually.
git merge-base --is-ancestor HEAD "$CANDIDATE"
git checkout --detach "$CANDIDATE"
./build.sh --test-suite=utilities --test-suite=transient-paste --test-suite=settings
./build.sh --dev
./build/VorssaintDeveloper --selftest
# The bundle is already signed with this Mac's stable identity. Verify the
# copied candidate before replacing the per-user app; no admin access is needed.
/bin/bash ./Tools/personal-install.sh 'build/stage.noindex/Vorssaint (Developer).app' "$APP_PATH"
printf '%s\n' "$CANDIDATE" > "$STATE_DIR/installed-commit.next"
mv "$STATE_DIR/installed-commit.next" "$STATE_DIR/installed-commit"
echo "Installed custom source $CANDIDATE"
