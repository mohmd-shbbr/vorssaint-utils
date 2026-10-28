#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Package only build outputs and public documentation, never an installed app.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/stage/NotchCraft.app"
VERSION="1.0.0-beta.3"
[[ -d "$APP" ]] || { echo 'Run ./build.sh --community first' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Refusing to package a dirty source tree' >&2; exit 1; }
SOURCE_SHA="$(git rev-parse --short HEAD)"
STAMP="$(/usr/libexec/PlistBuddy -c 'Print VorssaintBuildCommit' "$APP/Contents/Info.plist")"
[[ "$STAMP" == "$SOURCE_SHA · "* ]] || { echo 'Rebuild from the current clean commit first' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
mkdir -p dist
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto --noextattr --noqtn "$APP" "$STAGE/NotchCraft.app"
cp LICENSE "$STAGE/LICENSE.txt"
cp docs/COMMUNITY-RELEASE.md "$STAGE/READ-ME.md"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "NotchCraft" -srcfolder "$STAGE" -fs HFS+ -format UDZO \
    -ov "dist/NotchCraft-$VERSION-apple-silicon.dmg"
git archive --format=tar --prefix="NotchCraft-$VERSION/" HEAD \
    | gzip -n > "dist/NotchCraft-$VERSION-source.tar.gz"
(
    cd dist
    shasum -a 256 "NotchCraft-$VERSION-apple-silicon.dmg" "NotchCraft-$VERSION-source.tar.gz" \
        > "NotchCraft-$VERSION-SHA256SUMS.txt"
)
echo "Community package ready in dist/"
