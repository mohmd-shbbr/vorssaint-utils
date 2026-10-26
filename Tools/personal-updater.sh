#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
# Personal fork updater: build and install locally to retain this Mac's signing identity.
set -euo pipefail

REPOSITORY='https://github.com/mohmd-shbbr/vorssaint-utils.git'
BRANCH='feature/rich-snippets-and-arguments'
LABEL='com.vorssaint.personal-updater'
STATE_DIR="${VORSSAINT_UPDATER_STATE_DIR:-$HOME/Library/Application Support/VorssaintPersonalUpdater}"
CHECKOUT="$STATE_DIR/source"
AGENT_FILE="$HOME/Library/LaunchAgents/$LABEL.plist"

case "${1:---run}" in
  --install-service)
    mkdir -p "$STATE_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/VorssaintPersonalUpdater"
    cp "$0" "$STATE_DIR/updater.sh"
    cp "$(dirname "$0")/personal-updater-worker.sh" "$STATE_DIR/personal-updater-worker.sh"
    chmod 700 "$STATE_DIR/updater.sh"
    app_path="$HOME/Applications/Vorssaint (Developer).app"
    if [[ -w /Applications || ( -d "/Applications/Vorssaint (Developer).app/Contents" && -w "/Applications/Vorssaint (Developer).app" ) ]]; then app_path='/Applications/Vorssaint (Developer).app'; fi
    /usr/bin/python3 - "$AGENT_FILE" "$STATE_DIR/updater.sh" "$HOME/Library/Logs/VorssaintPersonalUpdater" "$LABEL" "$app_path" <<'PY'
import plistlib,sys
path,script,logs,label,app_path=sys.argv[1:]
with open(path,'wb') as f:
    plistlib.dump({'Label':label,'ProgramArguments':['/bin/bash',script,'--run'],
                  'EnvironmentVariables':{'VORSSAINT_UPDATER_APP_PATH':app_path},
                  'StartInterval':21600,'RunAtLoad':True,'ProcessType':'Background',
                  'StandardOutPath':logs+'/updates.log','StandardErrorPath':logs+'/errors.log'},f)
PY
    /bin/launchctl bootout "gui/$(id -u)" "$AGENT_FILE" 2>/dev/null || true
    /bin/launchctl bootstrap "gui/$(id -u)" "$AGENT_FILE"
    echo 'Personal updater installed. It checks the fork every six hours while this Mac is awake.'
    exit 0
    ;;
  --uninstall-service)
    /bin/launchctl bootout "gui/$(id -u)" "$AGENT_FILE" 2>/dev/null || true
    if [[ -f "$AGENT_FILE" ]]; then mv "$AGENT_FILE" "$AGENT_FILE.disabled"; fi
    echo 'Personal updater stopped. The app, settings, source and logs are retained.'
    exit 0
    ;;
  --check)
    /usr/bin/git ls-remote --exit-code "$REPOSITORY" "refs/heads/$BRANCH"
    exit 0
    ;;
  --run) ;;
  *) echo 'Usage: personal-updater.sh [--run|--check|--install-service|--uninstall-service]' >&2; exit 2 ;;
esac

mkdir -p "$STATE_DIR"
# An OS file lock is released even if a previous build crashed or the Mac rebooted.
exec /usr/bin/perl -MFcntl=:flock -e '
    open(my $lock, ">>", $ARGV[0]) or die "open updater lock: $!";
    flock($lock, LOCK_EX | LOCK_NB) or exit(0);
    shift @ARGV;
    system(@ARGV);
    my $status = $?;
    exit($status == -1 ? 1 : ($status & 127) ? 128 + ($status & 127) : $status >> 8);
' "$STATE_DIR/update.lock" /bin/bash "$(dirname "$0")/personal-updater-worker.sh" "$REPOSITORY" "$BRANCH" "$STATE_DIR"
