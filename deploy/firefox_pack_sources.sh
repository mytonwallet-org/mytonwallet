#!/usr/bin/env bash

set -e

rm -f MyWallet-firefox-sources.tgz

COPYFILE_DISABLE=1 tar \
  --exclude='*.zip' \
  --exclude='*.tgz' \
  --exclude=./.git \
  --exclude=./dist \
  --exclude=./dist-electron \
  --exclude=./node_modules \
  --exclude=./trash \
  --exclude=./.DS_Store \
  --exclude=./.idea \
  --exclude=./mobile/android \
  --exclude=./mobile/ios \
  "$@" -cvzf /tmp/MyWallet-firefox-sources.tgz ./

mv /tmp/MyWallet-firefox-sources.tgz ./
