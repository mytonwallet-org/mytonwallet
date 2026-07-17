#!/usr/bin/env bash

set -e

VERSION=$(node -p "require('./package.json').version")
DEFAULT_CHANGELOG="Bug fixes and performance improvements"

printf '%s' "$VERSION" > public/version.txt

printf '%s\n' "$DEFAULT_CHANGELOG" > "changelogs/$VERSION.txt"
git add "changelogs/$VERSION.txt"

git commit --amend --no-verify --no-edit public/version.txt "changelogs/$VERSION.txt"
