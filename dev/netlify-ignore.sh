#!/bin/bash

# Netlify's ignore command: exit 0 cancels the build. `CACHED_COMMIT_REF` is the last commit this
# preview built, or the production build's on a first push, and equals `COMMIT_REF` without a cache.
[ "${CONTEXT:-}" = deploy-preview ] || exit 1
bash "$(dirname "$0")/web-untouched.sh" netlify "${CACHED_COMMIT_REF:-}" "${COMMIT_REF:-}" || exit 1
