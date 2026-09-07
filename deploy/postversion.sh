#!/usr/bin/env bash

set -e

VERSION=$(node -p "require('./package.json').version")
DEFAULT_CHANGELOG="Bug fixes and performance improvements"

printf '%s\n' "$DEFAULT_CHANGELOG" > "changelogs/$VERSION.txt"
git add "changelogs/$VERSION.txt"

git commit --amend --no-verify --no-edit "changelogs/$VERSION.txt"
