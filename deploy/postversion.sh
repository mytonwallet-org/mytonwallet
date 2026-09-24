#!/usr/bin/env bash
set -e
VERSION=$(node -p "require('./package.json').version")
DEFAULT_CHANGELOG="Bug fixes and performance improvements"
printf '%s\n' "$DEFAULT_CHANGELOG" > "changelogs/$VERSION.txt"
# The desktop force-update gate follows the release version. Electron only asks electron-updater
# for a new build when this file is newer than the running app, so a gate left behind silently
# freezes the whole desktop fleet on the last version that bumped it (26.6.1 -> 26.7.x, then
# 26.7.7 -> 26.9.6). A lower value written by hand still works as a kill switch until the next bump.
printf '%s\n' "$VERSION" > public/electronVersion.txt
git add "changelogs/$VERSION.txt" public/electronVersion.txt
git commit --amend --no-verify --no-edit "changelogs/$VERSION.txt" public/electronVersion.txt
