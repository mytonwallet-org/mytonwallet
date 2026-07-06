#!/usr/bin/env bash
#
# Deploy the Gram Wallet Web build to wallet.ton.org.
#
# wallet.ton.org is GitHub Pages, served from the docs/ directory of the
# ton-blockchain/ton-wallet repo. There is no CI in that repo -- deploys run
# from CI in the public mirror, or manually from a maintainer's machine.
#
# No CDN purge step, on purpose: Cloudflare fronts the domain but does not
# cache the HTML (cf-cache-status: DYNAMIC), the caching layer is the GitHub
# Pages CDN with max-age=600, and asset filenames are content-hashed -- so a
# deploy is fully visible within ~10 minutes with no invalidation call. The
# historical Core Wallet deploys never purged either.
#
# ton-blockchain/ton-wallet IS our public mirror (mytonwallet-org/mytonwallet): same
# 2022 root, differing only by the "core:web:deploy" helper (1a80ba4fb2, the target
# identity anchor used below) and the "[Build]" dist commit. The private dev repo
# shares NO history (re-rooted 2024). So the target is a hosting shell -- only docs/
# is authoritative: drop a fresh build into docs/ and commit it on ton-wallet's
# existing master. NEVER rebase the target onto the private dev master.
#
# The build source must be PUBLISHED on the public mirror and built from a hermetic
# environment. Both are enforced below (sections 1b and 1c) and independently
# re-checked on the built artifact (the environment gates in section 3).
#
# Prerequisites:
#   - push (write) access to TARGET_REPO
#   - a clean working tree in THIS dev checkout, on a ref that carries the Gram
#     combo profile
#   - node/npm on PATH
#
# Usage:
#   deploy/deploy_gram_wallet_web.sh [--dry-run]
#
# Env vars:
#   TARGET_REPO           default: git@github.com:ton-blockchain/ton-wallet.git
#   TARGET_BRANCH         default: master
#   PUBLIC_MIRROR_REPO    default: https://github.com/mytonwallet-org/mytonwallet.git
#                         source of truth for the source guard: HEAD must be
#                         reachable from one of its published branch heads
#   ALLOW_UNPUBLISHED_SOURCE  set to 1 to bypass the build-source guard -- ships
#                         UNREVIEWED state, only for deliberate emergencies,
#                         never for a normal deploy
#   ALLOW_TAINTED_BUILD_ENV   set to 1 to bypass the build-env hygiene gate
#                         (local .env / ambient app env); the artifact
#                         environment gates (6-7) still apply
#   WORKDIR               default: <sibling of this dev repo>/ton-wallet-deploy
#
# Rollback (if a bad build reaches wallet.ton.org):
#   Every live deploy first preserves the outgoing remote tip on the TARGET as
#   refs/backup/build-<sha>, so every prior state is recoverable from the
#   remote itself -- no local checkout history or reflog needed (an ephemeral
#   CI runner has neither):
#     git ls-remote git@github.com:ton-blockchain/ton-wallet.git 'refs/backup/*'
#     git clone git@github.com:ton-blockchain/ton-wallet.git && cd ton-wallet
#     git fetch origin '+refs/backup/*:refs/backup/*'
#     git push --force-with-lease=<TARGET_BRANCH> origin refs/backup/build-<sha>:<TARGET_BRANCH>
#   (or simply re-run this script from the previous good source ref). The
#   rolled-back build is live once the Pages CDN cache expires (~10 minutes,
#   see the note above).

set -e

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      echo "See the header comment of this script for prerequisites, env vars and rollback."
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--dry-run]" >&2
      exit 1
      ;;
  esac
done

log() { echo "==> $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# --- 1. Preconditions --------------------------------------------------------

DEV_REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || fail "Not inside a git repo. Run this script from the mytonwallet-dev repo root."
[ "$(pwd)" = "$DEV_REPO_ROOT" ] \
  || fail "Run this script from the repo root ($DEV_REPO_ROOT), currently in $(pwd)."

[ -z "$(git status --porcelain)" ] \
  || fail "Working tree is dirty. Commit or stash your changes before deploying (the build must be reproducible from a committed ref)."

command -v node >/dev/null 2>&1 || fail "node not found on PATH."

SOURCE_SHA="$(git rev-parse --short HEAD)"
SOURCE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

TARGET_REPO="${TARGET_REPO:-git@github.com:ton-blockchain/ton-wallet.git}"
TARGET_BRANCH="${TARGET_BRANCH:-master}"
PUBLIC_MIRROR_REPO="${PUBLIC_MIRROR_REPO:-https://github.com/mytonwallet-org/mytonwallet.git}"
WORKDIR="${WORKDIR:-$(dirname "$DEV_REPO_ROOT")/ton-wallet-deploy}"

log "Build source: $DEV_REPO_ROOT @ $SOURCE_BRANCH ($SOURCE_SHA)"
log "Target repo:  $TARGET_REPO ($TARGET_BRANCH)"
log "Workdir:      $WORKDIR"
[ "$DRY_RUN" = "1" ] && log "Mode:         dry-run (push will be skipped)"

# --- 1b. Build-env hygiene: refuse an environment that can poison the artifact
#
# webpack imports dev/loadEnv.ts (dotenv) and EnvironmentPlugin bakes
# process.env into the bundle and its CSP. A developer's .env or exported app
# env vars therefore ship inside the PUBLIC production artifact -- e.g. a beta
# BRILLIANT_API_BASE_URL lands in the SDK worker chunk and in connect-src, and
# a personal TONCENTER key becomes world-readable. The safe build env is CI
# with no app env injected: with the env empty, src/config.ts falls back to
# the production endpoints (verified against the live production web app).
#
# Outside CI this gate hard-fails on:
#   - a non-empty .env at the repo root (dotenv would load it), and
#   - any key documented in .env.example -- the dev-env surface -- present in
#     the ambient environment, plus APP_ENV/BASE_URL/APP_NAME (not in
#     .env.example, but equally baked into the artifact).
# Secret-bearing vars (*_KEY, TEST_MNEMONIC, TEST_PASSWORD, TEST_SESSION) are
# refused even in CI: a public web bundle has no legitimate use for them.

[ -f "$DEV_REPO_ROOT/.env.example" ] \
  || fail "$DEV_REPO_ROOT/.env.example not found -- this does not look like the mytonwallet repo root."

IS_CI_BUILD=0
if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  IS_CI_BUILD=1
fi

if [ "${ALLOW_TAINTED_BUILD_ENV:-0}" = "1" ]; then
  log "############################################################################"
  log "# WARNING  ALLOW_TAINTED_BUILD_ENV=1 -- skipping the build-env hygiene gate."
  log "# WARNING  A local .env / ambient env may be baked into the PUBLIC artifact."
  log "# WARNING  The artifact environment gates (6-7) still apply."
  log "############################################################################"
else
  ENV_SURFACE_KEYS=()
  while IFS= read -r key; do
    ENV_SURFACE_KEYS+=("$key")
  done < <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' "$DEV_REPO_ROOT/.env.example")

  for key in "${ENV_SURFACE_KEYS[@]}" TEST_SESSION ELECTRON_TONCENTER_MAINNET_KEY ELECTRON_TONCENTER_TESTNET_KEY; do
    case "$key" in
      *_KEY|TEST_MNEMONIC|TEST_PASSWORD|TEST_SESSION)
        [ -z "${!key:-}" ] \
          || fail "Secret-bearing env var $key is set in the build environment. It would be baked into the PUBLIC wallet.ton.org bundle. Unset it and re-run. Bypass (dangerous): ALLOW_TAINTED_BUILD_ENV=1."
        ;;
    esac
  done

  if [ "$IS_CI_BUILD" = "1" ]; then
    log "Build env: CI detected -- trusting the pinned CI environment (secret-bearing vars checked)."
  else
    [ ! -s "$DEV_REPO_ROOT/.env" ] \
      || fail "$DEV_REPO_ROOT/.env exists and is non-empty. webpack (dev/loadEnv.ts) bakes it into the production artifact and its CSP -- this is how a beta API URL or a personal key leaks into wallet.ton.org. The intended deploy path is CI (no .env there). To build locally anyway, move it aside first: mv .env .env.local-backup. Bypass (dangerous): ALLOW_TAINTED_BUILD_ENV=1."

    for key in "${ENV_SURFACE_KEYS[@]}" APP_ENV BASE_URL APP_NAME; do
      [ -z "${!key:-}" ] \
        || fail "Env var $key is set in the ambient environment. webpack would bake it into the production artifact. Unset it (unset $key) and re-run, or deploy from CI. Bypass (dangerous): ALLOW_TAINTED_BUILD_ENV=1."
    done
    log "Build env OK: no local .env, no ambient app env."
  fi
fi

# --- 1c. Source lineage guard: the source must be PUBLISHED on the mirror -----
#
# wallet.ton.org is production; the source MUST be public-mirror content.
# Positive discriminator: HEAD is reachable from a branch head actually pushed
# to the public mirror. A mere merge-base with the mirror would also admit any
# stale checkout or arbitrarily patched fork -- not accepted. The private dev
# repo (re-rooted in 2024, no shared history) fails outright.
#
# The mirror's branch heads are fetched into the local refs/gram-deploy-mirror/*
# namespace (pruned on every run, invisible to normal branch listings).

MIRROR_GUARD_NS="refs/gram-deploy-mirror"

log "Fetching public mirror branch heads (source guard)..."
git fetch --filter=blob:none --no-tags --prune "$PUBLIC_MIRROR_REPO" "+refs/heads/*:${MIRROR_GUARD_NS}/*"

PUBLISHED_REF=""
while IFS= read -r ref; do
  if git merge-base --is-ancestor HEAD "$ref" 2>/dev/null; then
    PUBLISHED_REF="${ref#"${MIRROR_GUARD_NS}"/}"
    break
  fi
done < <(git for-each-ref --format='%(refname)' "$MIRROR_GUARD_NS")

if [ -n "$PUBLISHED_REF" ]; then
  log "Source OK: $SOURCE_BRANCH@$SOURCE_SHA is published on the public mirror (reachable from its branch '$PUBLISHED_REF')."
elif [ "${ALLOW_UNPUBLISHED_SOURCE:-0}" = "1" ]; then
  log "############################################################################"
  log "# WARNING  ALLOW_UNPUBLISHED_SOURCE=1 -- source $SOURCE_BRANCH@$SOURCE_SHA"
  log "# WARNING  is NOT published on the public mirror. You are shipping UNREVIEWED"
  log "# WARNING  state to the PRODUCTION domain wallet.ton.org, and the [Build]"
  log "# WARNING  commit will point at a non-public SHA. Proceeding anyway."
  log "############################################################################"
else
  fail "Build source $SOURCE_BRANCH@$SOURCE_SHA is NOT published on the public mirror ($PUBLIC_MIRROR_REPO): it is not reachable from any of the mirror's branch heads. wallet.ton.org must be built from mirror-published state -- master, or a release branch that has been pushed there. Push the ref to the mirror first. To override deliberately (ships unreviewed state), re-run with ALLOW_UNPUBLISHED_SOURCE=1."
fi

# --- 2. Build in the dev checkout (the source that carries the Gram combo) ----
#
# Build here, NOT inside the target clone: the target's own source tree is a
# frozen public-mirror snapshot and does not contain the Gram combo profile.

log "Building (npm run tonorg:build:production)..."
( cd "$DEV_REPO_ROOT" && npm run tonorg:build:production )

DIST_DIR="$DEV_REPO_ROOT/dist"
[ -d "$DIST_DIR" ] || fail "Build did not produce $DIST_DIR."

# --- 3. Artifact gates: fail fast before touching the target -----------------
#
# These gates -- not git lineage -- are what guarantee the artifact is the
# right combo build (Gram branding, Core behavior) built against the right
# environment (production endpoints only). They hold regardless of which ref
# or machine the artifact came from.

log "Verifying build output before publishing..."

[ -d "$DIST_DIR/gramWallet" ] \
  || fail "$DIST_DIR/gramWallet is missing -- Gram assets were not produced. Aborting."

grep -q "Gram Wallet" "$DIST_DIR/index.html" \
  || fail "$DIST_DIR/index.html does not contain 'Gram Wallet' -- wrong branding. Aborting."

! grep -q "TON Wallet" "$DIST_DIR/index.html" \
  || fail "$DIST_DIR/index.html contains 'TON Wallet' -- Core branding leaked into the Gram build. Aborting."

MAIN_JS_FILES=("$DIST_DIR"/main.*.js)
if [ ! -e "${MAIN_JS_FILES[0]}" ]; then
  MAIN_JS_FILES=("$DIST_DIR"/*.js)
fi
grep -rq "tonwallet-global-state" "${MAIN_JS_FILES[@]}" \
  || fail "'tonwallet-global-state' storage key not found in the bundle -- Core storage behavior missing. Aborting."

[ -f "$DIST_DIR/gramWallet/site.webmanifest" ] \
  || fail "$DIST_DIR/gramWallet/site.webmanifest is missing -- manifest not laid out for the combo profile. Aborting."

# Environment gate (positive): every connect-src token must be on the
# production allowlist. webpack assembles connect-src from ALL env-configurable
# backend URLs (webpack.config.ts, cspConnectSrcHosts), so ANY environment
# poisoning -- beta/staging/localhost/personal endpoints, via .env or ambient
# env -- surfaces here no matter how it got in. The list below is the exact
# token set of a clean production combo build (src/config.ts defaults). It
# intentionally includes WalletConnect Pay's hardcoded staging origin -- that
# string is a constant in src/config.ts, not an environment leak. If an
# endpoint legitimately changes in src/config.ts, update this list in the same
# PR: the gate failing on a legit change is a deliberate deploy-gate review,
# not a false positive.

ALLOWED_CONNECT_SRC=(
  "'self'"
  "blob:"
  "https://*.walletconnect.com"
  "https://*.walletconnect.org"
  "https://agent.mywallet.io"
  "https://analytics.ton.org"
  "https://api-portfolio.mywallet.io/api/"
  "https://api.mywallet.io"
  "https://api.mywallet.io/proxy/"
  "https://api.pay.walletconnect.com/"
  "https://api.pay.walletconnect.org/"
  "https://api.shasta.trongrid.io"
  "https://evmapi-testnet.mytonwallet.org"
  "https://evmapi.mytonwallet.org"
  "https://ipfs.io/ipfs/"
  "https://mfa-server.mytonwallet.org"
  "https://pay.walletconnect.com/"
  "https://solanaapi-devnet.mytonwallet.org"
  "https://solanaapi.mytonwallet.org"
  "https://staging.api.pay.walletconnect.org/"
  "https://static.mytonwallet.org"
  "https://tonapiio-testnet.mytonwallet.org"
  "https://tonapiio.mytonwallet.org"
  "https://toncenter-testnet.mytonwallet.org"
  "https://toncenter.mytonwallet.org"
  "https://tonconnectbridge.mytonwallet.org/bridge/"
  "https://tronapi.mytonwallet.org"
  "wss://*.walletconnect.com"
  "wss://*.walletconnect.org"
  "wss://api.mywallet.io"
  "wss://evmapi-testnet.mytonwallet.org"
  "wss://evmapi.mytonwallet.org"
  "wss://solanaapi-devnet.mytonwallet.org"
  "wss://solanaapi.mytonwallet.org"
  "wss://toncenter-testnet.mytonwallet.org"
  "wss://toncenter.mytonwallet.org"
)

CSP_CONNECT_SRC="$(grep -oE 'connect-src[^;]*' "$DIST_DIR/index.html" || true)"
[ -n "$CSP_CONNECT_SRC" ] \
  || fail "No connect-src directive found in the $DIST_DIR/index.html CSP. Aborting."

read -ra CSP_TOKENS <<< "$CSP_CONNECT_SRC"
for token in "${CSP_TOKENS[@]}"; do
  [ "$token" = "connect-src" ] && continue
  token_ok=0
  for allowed in "${ALLOWED_CONNECT_SRC[@]}"; do
    if [ "$token" = "$allowed" ]; then
      token_ok=1
      break
    fi
  done
  [ "$token_ok" = "1" ] \
    || fail "connect-src contains a host that is NOT on the production allowlist: '$token'. Either the build environment poisoned the artifact, or src/config.ts endpoints changed -- in the latter case update ALLOWED_CONNECT_SRC in this script deliberately. Aborting."
done

# Environment gate (negative): no non-production host of OUR infrastructure
# anywhere in the shipped files -- catches env poisoning baked into JS chunks
# (e.g. the SDK worker) even where the CSP would not show it. Deliberately
# scoped to our domains: vendored libraries legitimately contain strings like
# "http://localhost:8545", and WalletConnect Pay ships a hardcoded staging
# origin, so a bare beta/staging/localhost scan would false-positive on every
# clean build. The exemptions below are hardcoded compile-time constants
# present in every clean build regardless of env: BETA_URL (src/config.ts:57),
# both branches of its ternary.

NON_PROD_HOST_RE='[a-z0-9.-]*(beta|staging)[a-z0-9.-]*\.(mytonwallet\.(org|app|io)|mywallet\.io|gramwallet\.(io|app))|[a-z0-9-]+\.netlify\.app'
NON_PROD_HITS="$(grep -rhoE "$NON_PROD_HOST_RE" "$DIST_DIR" \
  --include='*.js' --include='*.html' --include='*.css' --include='*.json' \
  --include='*.webmanifest' --include='_redirects' --include='_headers' \
  | sort -u | grep -vxE 'beta\.mywallet\.io|beta\.wallet\.ton\.org' || true)"
[ -z "$NON_PROD_HITS" ] \
  || fail "Non-production hosts of our infrastructure found in the built artifact: $(echo "$NON_PROD_HITS" | tr '\n' ' '). The build environment poisoned the bundle. Aborting."

log "All gates passed."

# --- 4. Prepare the target clone (hosting shell) -----------------------------

if [ ! -d "$WORKDIR" ]; then
  log "Cloning $TARGET_REPO into $WORKDIR..."
  git clone "$TARGET_REPO" "$WORKDIR"
fi

cd "$WORKDIR"

# A pre-existing WORKDIR must actually point at TARGET_REPO -- otherwise the
# push below would go to whatever the stale clone's origin is, while every
# guard and log line talks about TARGET_REPO.
if [ "$(git remote get-url origin)" != "$TARGET_REPO" ]; then
  fail "WORKDIR $WORKDIR already exists but its origin ($(git remote get-url origin)) is not TARGET_REPO ($TARGET_REPO). Remove the stale WORKDIR or fix TARGET_REPO."
fi

git fetch origin
git rev-parse --verify "origin/$TARGET_BRANCH" >/dev/null 2>&1 \
  || fail "origin/$TARGET_BRANCH not found in $WORKDIR after fetch."

# --- 5. Target identity guard: the target must BE the ton-wallet hosting shell
#
# Belt-and-suspenders against a mis-set TARGET_REPO, checked BEFORE any
# mutation. Shared history is NOT a discriminator here: our own public mirror
# shares the entire 2022 lineage with ton-wallet, so an ancestry-with-mirror
# check would happily pass a TARGET_REPO typo pointing at the mirror -- a repo
# whose master triggers store-release CI on push. Require positive identity of
# the hosting shell instead:
#   (a) the "core:web:deploy" commit -- which is REACHABLE only in ton-wallet's
#       history (mere object PRESENCE proves nothing: GitHub packs can carry
#       unreachable fork-network objects) -- must be an ancestor of the target
#       branch, and
#   (b) the target branch must actually host a built site at docs/index.html
#       (the mirror has a docs/ tree too, but it holds markdown, not a site).

TON_WALLET_ANCHOR_COMMIT="1a80ba4fb2eec9e27a843b2626e1611159cd1f55"  # "Add `npm run core:web:deploy` script"

git merge-base --is-ancestor "$TON_WALLET_ANCHOR_COMMIT" "origin/$TARGET_BRANCH" 2>/dev/null \
  || fail "Target '$TARGET_REPO' ($TARGET_BRANCH) does not contain the ton-wallet anchor commit ${TON_WALLET_ANCHOR_COMMIT:0:12} (\"core:web:deploy\") in its history. This is NOT the wallet.ton.org hosting repo (a TARGET_REPO typo pointing at our public mirror also fails here, by design). Refusing to deploy."

git cat-file -e "origin/$TARGET_BRANCH:docs/index.html" 2>/dev/null \
  || fail "Target '$TARGET_REPO' ($TARGET_BRANCH) has no docs/index.html -- it does not look like the GitHub Pages hosting shell of wallet.ton.org. Refusing to deploy."

# The pre-deploy remote tip: preserved as a backup ref before the force-push,
# and used as the explicit lease value so a concurrent upstream push aborts us.
REMOTE_TIP_SHA="$(git rev-parse "origin/$TARGET_BRANCH")"

if ! git checkout "$TARGET_BRANCH" 2>/dev/null; then
  git checkout -b "$TARGET_BRANCH" "origin/$TARGET_BRANCH"
fi
git reset --hard "origin/$TARGET_BRANCH"

# --- 6. Reset the previous build commit off the target -----------------------
#
# Keeps history flat: each deploy replaces the prior "[Build]" rather than
# stacking build blobs. The target's source stays as-is (public-lineage);
# only docs/ is refreshed. The replaced tip stays recoverable via the backup
# ref pushed in step 8.

LAST_SUBJECT="$(git log -1 --pretty=%s)"
case "$LAST_SUBJECT" in
  "[Build]"*)
    log "Last commit is a previous build ('$LAST_SUBJECT'), resetting it off..."
    git reset --hard HEAD^
    ;;
esac

# --- 7. Publish the build into docs/ and commit ------------------------------

# Drop anything untracked/ignored (e.g. .DS_Store from a previous manual
# session) -- `git add -A` below would silently ship it to production.
git clean -fdx

rm -rf docs
cp -R "$DIST_DIR" docs

VERSION="$(node -p "require('$DEV_REPO_ROOT/package.json').version")"
COMMIT_MSG="[Build] Gram Wallet Web v${VERSION} (source ${SOURCE_BRANCH}@${SOURCE_SHA})"

git add -A
git commit -m "$COMMIT_MSG"

# --- 8. Push: preserve the outgoing tip, then lease-protected force ----------
#
# Two by-construction properties:
#   - Recoverability: the outgoing remote tip is stored on the TARGET as
#     refs/backup/build-<sha> BEFORE being replaced, so every prior deploy
#     state can be restored from the remote alone (see the rollback recipe in
#     the header). A local reflog is useless on an ephemeral CI runner.
#   - No silent clobber: the force-push carries an explicit lease pinned to
#     the tip we fetched in step 4; if the TON side pushed anything in
#     between, the push is REFUSED instead of overwriting their commit. (The
#     explicit expected value also sidesteps the background-fetch caveat of
#     bare --force-with-lease, with no need for --force-if-includes.)

BACKUP_REF="refs/backup/build-${REMOTE_TIP_SHA}"

if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] Would run: git push origin ${REMOTE_TIP_SHA}:${BACKUP_REF}"
  log "[dry-run] Would run: git push --force-with-lease=${TARGET_BRANCH}:${REMOTE_TIP_SHA} origin $TARGET_BRANCH"
  log "[dry-run] Commit created locally in $WORKDIR, NOT pushed. Inspect with: git -C $WORKDIR log -1"
else
  log "Preserving the outgoing remote tip as ${BACKUP_REF}..."
  git push origin "${REMOTE_TIP_SHA}:${BACKUP_REF}"
  log "Pushing (lease-protected force) to origin/$TARGET_BRANCH..."
  git push --force-with-lease="${TARGET_BRANCH}:${REMOTE_TIP_SHA}" origin "$TARGET_BRANCH"
fi

# --- Summary -----------------------------------------------------------------

echo
echo "=================================================================="
echo "Deployed:   https://wallet.ton.org"
echo "Version:    $VERSION"
echo "Source:     $SOURCE_BRANCH@$SOURCE_SHA"
echo "Commit:     $COMMIT_MSG"
[ "$DRY_RUN" = "1" ] && echo "Mode:       dry-run -- nothing was pushed"
echo "=================================================================="
echo "Checklist: verify wallet.ton.org against the canary profile before"
echo "considering this deploy fully live (CDN cache expires within ~10 min)."
echo "=================================================================="
