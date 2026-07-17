#!/usr/bin/env bash

set -e

if [ -z "$1" ]; then
  echo "Missing argument: <target>"
  exit 1
fi

TARGET="$1"

IS_EXTENSION=1 ./deploy/copy_to_dist.sh

rm -f "MyWallet-$TARGET.zip"

cd dist

zip -r -X "../MyWallet-$TARGET.zip" ./*
