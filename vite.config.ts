import './dev/loadEnv';

import { execFileSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import type { Plugin } from 'vite';
import { build, defineConfig, mergeConfig } from 'vite';
import webextensionPolyfillPackage from 'webextension-polyfill/package.json';

import type { EmittedFiles } from './plugins/emittedFiles';

import { resolveBuildStamp } from './dev/buildStamp';
import { createBundleStatsPlugins } from './plugins/bundleStats';
import { emittedFiles } from './plugins/emittedFiles';
import { defineEnv } from './plugins/env';
import { htmlTemplate } from './plugins/htmlTemplate';
import { iconFont } from './plugins/iconFont';
import { defaultLangPack, getLangPackFiles, writeJsonLangPack } from './plugins/langPacks';
import { preloadAssets } from './plugins/preloadAssets';
import { createBaseConfig, ROOT_DIR } from './plugins/viteBase';
import {
  AGENT_API_URL,
  APP_COMMIT_HASH,
  APP_ENV,
  APP_NAME,
  BASE_URL,
  BRILLIANT_API_BASE_URL,
  EVM_MAINNET_RPC_URL,
  EVM_TESTNET_RPC_URL,
  EXTENSION_DESCRIPTION,
  EXTENSION_NAME,
  GLOBAL_STATE_CACHE_KEY,
  IFRAME_WHITELIST,
  IPFS_GATEWAY_BASE_URL,
  IS_EXPLORER,
  IS_EXTENSION,
  IS_FIREFOX_EXTENSION,
  IS_GRAM_WALLET,
  IS_HEADLESS,
  IS_OPERA_EXTENSION,
  IS_PACKAGED_ELECTRON,
  IS_TELEGRAM_APP,
  LANG_LIST,
  MFA_API_BASE_URL,
  MW_STATIC_BASE_URL,
  PORTFOLIO_API_URL,
  PROXY_API_BASE_URL,
  SOLANA_MAINNET_API_URL,
  SOLANA_MAINNET_RPC_URL,
  SOLANA_TESTNET_API_URL,
  SOLANA_TESTNET_RPC_URL,
  SSE_BRIDGE_URL,
  SUBPROJECT_URL_MASK,
  TON_CONNECT_ANALYTICS_URL,
  TONAPIIO_MAINNET_URL,
  TONAPIIO_TESTNET_URL,
  TONCENTER_MAINNET_URL,
  TONCENTER_TESTNET_URL,
  TRON_MAINNET_API_URL,
  TRON_TESTNET_API_URL,
  UTXO_MAINNET_RPC_URL,
  UTXO_TESTNET_RPC_URL,
  WALLET_CONNECT_BRIDGE_PATTERNS,
  WALLET_CONNECT_PAY_CONNECT_ORIGINS,
  WALLET_CONNECT_PAY_FRAME_ORIGINS,
} from './src/config';

// `public/fallbackScript.js` runs before the bundle (pre-paint, CSP-external) so it hardcodes the RTL
// language codes. Fail the build if they drift from LANG_LIST's `rtl: true` entries.
const fallbackRtlCodes = (
  fs.readFileSync(path.resolve(ROOT_DIR, 'public/fallbackScript.js'), 'utf8')
    .match(/RTL_LANG_CODES\s*=\s*\[([^\]]*)]/)?.[1] ?? ''
).split(',').map((code) => code.trim().replace(/['"]/g, '')).filter(Boolean);
const langListRtlCodes = LANG_LIST.filter((lang) => lang.rtl).map((lang) => lang.langCode);
if (JSON.stringify([...fallbackRtlCodes].sort()) !== JSON.stringify([...langListRtlCodes].sort())) {
  throw new Error(
    `public/fallbackScript.js RTL_LANG_CODES [${fallbackRtlCodes.join(', ')}] is out of sync with LANG_LIST `
    + `rtl entries [${langListRtlCodes.join(', ')}] - update fallbackScript.js to match.`,
  );
}

const destinationDir = path.resolve(ROOT_DIR, 'dist');
const I18N_DIR = path.resolve(ROOT_DIR, 'src/i18n');
const appCommitHash = APP_COMMIT_HASH || runGit(['rev-parse', 'HEAD']);
const isWebApp = !(IS_EXTENSION || IS_PACKAGED_ELECTRON || IS_HEADLESS);
const cspConnectSrcExtra = APP_ENV === 'development'
  ? `http://localhost:3000 ${process.env.CSP_CONNECT_SRC_EXTRA_URL}`
  : '';
const cspScriptSrcExtra = IS_TELEGRAM_APP ? 'https://telegram.org' : '';
const cspFrameSrcExtra = [
  'https://buy-sandbox.moonpay.com/',
  'https://buy.moonpay.com/',
  'https://sell.moonpay.com/',
  'https://sell-sandbox.moonpay.com/',
  'https://*.onetrust.com/', // This is a GDPR cookie consent widget from Moonpay
  'https://dreamwalkers.io/',
  'https://avanchange.com/',
  ...WALLET_CONNECT_PAY_FRAME_ORIGINS,
  ...IFRAME_WHITELIST,
  SUBPROJECT_URL_MASK,
].join(' ');

const cspConnectSrcHosts = Array.from(new Set([
  BRILLIANT_API_BASE_URL,
  BRILLIANT_API_BASE_URL.replace(/^http(s?):/, 'ws$1:'),
  ensureTrailingSlash(PROXY_API_BASE_URL),
  MW_STATIC_BASE_URL,
  TONCENTER_MAINNET_URL,
  TONCENTER_MAINNET_URL.replace(/^http(s?):/, 'ws$1:'),
  TONCENTER_TESTNET_URL,
  TONCENTER_TESTNET_URL.replace(/^http(s?):/, 'ws$1:'),
  TONAPIIO_MAINNET_URL,
  TONAPIIO_TESTNET_URL,
  TRON_MAINNET_API_URL,
  TRON_TESTNET_API_URL,
  SOLANA_MAINNET_RPC_URL,
  SOLANA_MAINNET_RPC_URL.replace(/^http(s?):/, 'ws$1:'),
  SOLANA_TESTNET_RPC_URL,
  SOLANA_TESTNET_RPC_URL.replace(/^http(s?):/, 'ws$1:'),
  SOLANA_MAINNET_API_URL,
  SOLANA_TESTNET_API_URL,
  WALLET_CONNECT_BRIDGE_PATTERNS,
  ...WALLET_CONNECT_PAY_CONNECT_ORIGINS,
  AGENT_API_URL ? new URL(AGENT_API_URL).origin : undefined,
  EVM_MAINNET_RPC_URL,
  EVM_TESTNET_RPC_URL,
  EVM_MAINNET_RPC_URL.replace(/^http(s?):/, 'ws$1:'),
  EVM_TESTNET_RPC_URL.replace(/^http(s?):/, 'ws$1:'),
  UTXO_MAINNET_RPC_URL,
  UTXO_TESTNET_RPC_URL,
  UTXO_MAINNET_RPC_URL.replace(/^http(s?):/, 'ws$1:'),
  UTXO_TESTNET_RPC_URL.replace(/^http(s?):/, 'ws$1:'),

  ensureTrailingSlash(IPFS_GATEWAY_BASE_URL),
  ensureTrailingSlash(SSE_BRIDGE_URL),
  MFA_API_BASE_URL,
  ensureTrailingSlash(PORTFOLIO_API_URL),
  TON_CONNECT_ANALYTICS_URL,
])).join(' ');

const cspImageSrcHosts = [
  MW_STATIC_BASE_URL,
  'https://imgproxy.mytonwallet.org',
  'https://dns-image.mytonwallet.org',
  'https://mytonwallet.s3.eu-central-1.amazonaws.com',
  'https://cache.tonapi.io', // Deprecated
  'https://c.tonapi.io',
  'https://web-api.changelly.com',
].join(' ');

// Kept out of `CSP` because that string is also served via a `<meta>` tag and the extension manifest,
// where `frame-ancestors` is invalid. It only works as an HTTP header, so it is appended in `_headers`.
// `X-Frame-Options` stays in `_headers` as a fail-closed fallback should this directive ever be dropped.
// Empty for the Telegram build, which is itself framed by web.telegram.org and whose framing policy
// `_headers_telegram` owns; any directive here would override that file's `X-Frame-Options`.
const cspFrameAncestors = IS_TELEGRAM_APP ? '' : `${[
  'frame-ancestors \'self\'',
  'https://stand.ton-connect.io', // The TON Connect conformance stand embeds the wallet in an iframe.
  ...(APP_ENV === 'production' ? [] : ['http://localhost:*', 'http://127.0.0.1:*']),
].join(' ')};`;

// `process.env` keys baked into the bundle and their defaults. A variable set at build time wins.
const ENV_DEFAULTS = {
  APP_ENV: 'production',
  APP_NAME: '',
  APP_VERSION: getAppVersion(),
  APP_COMMIT_HASH: appCommitHash ?? '',
  TEST_SESSION: '',
  TONCENTER_MAINNET_URL: '',
  TONCENTER_MAINNET_KEY: '',
  TONCENTER_TESTNET_URL: '',
  TONCENTER_TESTNET_KEY: '',
  TONAPIIO_MAINNET_URL: '',
  TONAPIIO_TESTNET_URL: '',
  BRILLIANT_API_BASE_URL: '',
  TRON_MAINNET_API_URL: '',
  SOLANA_MAINNET_RPC_URL: '',
  SOLANA_TESTNET_RPC_URL: '',
  SOLANA_MAINNET_API_URL: '',
  SOLANA_MAINNET_API_KEY: '',
  SOLANA_TESTNET_API_URL: '',
  SOLANA_TESTNET_API_KEY: '',
  EVM_MAINNET_RPC_URL: '',
  EVM_TESTNET_RPC_URL: '',
  UTXO_MAINNET_RPC_URL: '',
  UTXO_TESTNET_RPC_URL: '',
  TRON_TESTNET_API_URL: '',
  PROXY_HOSTS: '',
  STAKING_POOLS: '',
  LIQUID_POOL: '',
  LIQUID_JETTON: '',
  IS_PACKAGED_ELECTRON: 'false',
  IS_ANDROID_DIRECT: 'false',
  ELECTRON_TONCENTER_MAINNET_KEY: '',
  ELECTRON_TONCENTER_TESTNET_KEY: '',
  BASE_URL,
  BOT_USERNAME: '',
  IS_EXTENSION: '', // It's necessary to use an empty string, because it's used in bundle-time conditions
  IS_FIREFOX_EXTENSION: 'false',
  IS_OPERA_EXTENSION: 'false',
  IS_AIR_APP: 'false',
  IS_GRAM_WALLET: 'false',
  IS_TELEGRAM_APP: 'false',
  IS_EXPLORER: 'false',
  IS_HEADLESS: '', // Empty string for the same reason as IS_EXTENSION above
  SWAP_FEE_ADDRESS: '',
  DIESEL_ADDRESS: '',
  GIVEAWAY_CHECKIN_URL: '',
  PROXY_API_BASE_URL: '',
  WALLET_CONNECT_PROJECT_ID: '',
  WALLET_CONNECT_PAY_APP_ID: '',
  MULTISEND_DAPP_URL: '',
  PORTFOLIO_DAPP_URL: '',
  AGENT_API_URL: '',
  SDK_BUILD_STAMP: resolveBuildStamp(),
  AGENT_OVERRIDE: 'no_override',
  AGENT_V2_QUOTA_STATUS_ENABLED: '0',
  MFA_BOT_URL: '',
  MFA_API_BASE_URL: '',
  MFA_MASTER_ADDRESS: '',
  MFA_EXTENSION_CODE_HASH: '',
  NO_TON: '0',
  NO_TRON: '0',
  NO_SOLANA: '0',
  NO_EVM: '0',
  NO_UTXO: '0',
  NO_EXTRA_FEATURES: '0',
  NO_LEDGER: '0',
};

const ALIASES = {
  // Removes duplicate copies
  'bn.js': path.join(ROOT_DIR, 'node_modules/bn.js/lib/bn.js'),
  // Keeps the TL-B preview runtime on the app's TON core copy. `@ton-community/tlb-runtime` depends
  // on `@ton/core` ^0.61, while the app bundles 0.60.x.
  '@ton/core': path.join(ROOT_DIR, 'node_modules/@ton/core'),
  // The package entry point is the Node build
  tronweb: path.join(ROOT_DIR, 'node_modules/tronweb/dist/TronWeb.js'),
};

// Scripts the extension manifest refers to by name. Each must be a single classic script: MV3 service
// workers and content scripts cannot load chunks, and the page script is injected into dApp pages.
const EXTENSION_SCRIPTS = {
  extensionServiceWorker: 'src/extension/serviceWorker.ts',
  extensionContentScript: 'src/extension/contentScript.ts',
  extensionPageScript: 'src/extension/pageScript/index.ts',
};

const EXTENSION_BANNER = '/*! webextension-polyfill: for licensing and source code, see THIRD_PARTY_NOTICES.txt. */';

// `version.txt` moves only on a release bump, so it cannot tell which revision a host actually serves -
// staging redeploys off every master commit and reports the same version for weeks. `build.txt` carries
// the revision itself, alongside the rest of the build identity, and stays out of `version.txt` because
// the in-app update check parses that file with a strict semver regex and silently treats anything else
// as "no update available".
const BUILD_INFO_FILENAME = 'build.txt';

// Emitted from the same version the bundle bakes in as APP_VERSION, so the file the in-app update check
// fetches cannot drift from the running code. Stays a bare semver so that same strict regex accepts it.
const APP_VERSION_FILENAME = 'version.txt';

export default defineConfig(({ command, mode }) => {
  const isDevServer = command === 'serve';
  const isProductionMode = mode === 'production';
  const csp = buildCsp(isDevServer);

  // Extension bundles ship unminified so that store reviewers can read them. AMO is the exception: its
  // validator refuses to parse any file above 5 MB and fails the whole submission, and the service worker
  // bundle is well past that. Mozilla accepts minified code as long as the sources are submitted alongside
  // it, which `firefox_pack_sources.sh` does on every release. That limit belongs to the store rather than
  // to one environment, so both packaged environments are built the way AMO would receive them, which also
  // keeps the staging package worth validating.
  const shouldMinify = IS_FIREFOX_EXTENSION
    ? APP_ENV === 'production' || APP_ENV === 'staging'
    : APP_ENV === 'production' && !IS_EXTENSION;
  // Extensions always ship their maps: AMO validation skips `.map` files, and user stack traces stay resolvable
  const sourcemap = IS_EXTENSION || !(APP_ENV === 'production' && !isWebApp);
  const banner = IS_EXTENSION ? EXTENSION_BANNER : undefined;
  const define = defineEnv(ENV_DEFAULTS);
  const bundleStats = process.env.BUNDLE_STATS === '1'
    ? createBundleStatsPlugins(process.env.BUNDLE_STATS_BASELINE_PATH)
    : undefined;

  const baseConfig = createBaseConfig({
    mode,
    isProduction: APP_ENV === 'production',
    shouldMinify,
    sourcemap,
    outDir: destinationDir,
    banner,
    extraWorkerPlugins: bundleStats?.workerPlugins,
  });

  return mergeConfig(baseConfig, {
    root: path.resolve(ROOT_DIR, 'src'),
    publicDir: path.resolve(ROOT_DIR, 'public'),
    // When using the History API, the index.html page has to be served in place of any 404 responses
    appType: IS_EXPLORER ? 'spa' : 'mpa',
    define,

    resolve: { alias: ALIASES },

    server: {
      port: 4321,
      strictPort: true,
      host: '0.0.0.0',
      allowedHosts: true,
      headers: {
        'Content-Security-Policy': csp,
      },
    },

    optimizeDeps: {
      entries: ['index.html', 'api/providers/worker/provider.ts', 'lib/mediaWorker/index.worker.ts'],
    },

    build: {
      // Binary data is loaded with `fetch`, and the CSP `connect-src` rule blocks the `data:` URL that an inlined
      // asset becomes, so small `.bin` files stay separate files
      assetsInlineLimit: (file: string) => (file.endsWith('.bin') ? false : undefined),
      rolldownOptions: {
        input: { main: path.resolve(ROOT_DIR, 'src/index.html') },
        output: {
          // Opera add-on review rejects `.tgs` files, while RLottie reads them by content, not by extension
          assetFileNames: IS_OPERA_EXTENSION
            ? (asset: { names: string[] }) => (
              asset.names[0]?.endsWith('.tgs') ? '[name].[hash].json' : '[name].[hash][extname]'
            )
            : '[name].[hash][extname]',
        },
      },
    },

    plugins: [
      defaultLangPack(I18N_DIR, () => {
        writeJsonLangPack(path.join(I18N_DIR, 'en.yaml'), path.join(I18N_DIR, 'en.json'), isProductionMode);
      }),
      iconFont(path.resolve(ROOT_DIR, 'src/assets/font-icons')),
      htmlTemplate({
        CACHE_KEY: GLOBAL_STATE_CACHE_KEY,
        TITLE: APP_NAME,
        HOMEPAGE: IS_GRAM_WALLET ? 'https://wallet.ton.org' : 'https://mywallet.io',
        ASSETS_PREFIX: IS_GRAM_WALLET ? 'gramWallet/' : '',
        CSP: csp,
        MANIFEST_LINK: IS_EXTENSION
          ? ''
          : `<link rel="manifest" href="./${IS_GRAM_WALLET ? 'gramWallet/' : ''}site.webmanifest">`,
        TELEGRAM_SCRIPT: IS_TELEGRAM_APP ? '<script src="https://telegram.org/js/telegram-web-app.js"></script>' : '',
      }),
      preloadAssets([
        /duck_.*?\.png/, // Lottie thumbs
        /coin_.*?\.png/, // Coin icons
        /theme_.*?\.png/, // Theme icons
        /chain_.*?\.png/, // Chain icons
        /settings_.*?\.svg/, // Settings icons (svg)
        ...(IS_GRAM_WALLET ? [
          /gram_wallet_.*?\.png/, // Lottie thumbs for Gram Wallet
        ] : []),
      ]),
      emittedFiles(() => getEmittedFiles(csp, isProductionMode)),
      ...(IS_EXTENSION ? [buildExtensionScripts({ mode, define, shouldMinify, sourcemap })] : []),
      ...(bundleStats?.plugins ?? []),
    ],
  });
});

function getEmittedFiles(csp: string, isProductionMode: boolean): EmittedFiles {
  const headersFile = IS_TELEGRAM_APP ? '_headers_telegram' : '_headers';

  return {
    ...getLangPackFiles(I18N_DIR, isProductionMode),
    ...(IS_EXTENSION && getExtensionLicenseFiles()),
    'manifest.json': () => buildExtensionManifest(csp),
    [headersFile]: () => buildHeaders(fs.readFileSync(path.resolve(ROOT_DIR, 'src', headersFile), 'utf8'), csp),
    [BUILD_INFO_FILENAME]: getBuildInfo,
    [APP_VERSION_FILENAME]: getAppVersion,
  };
}

function getExtensionLicenseFiles(): EmittedFiles {
  const { version, license } = webextensionPolyfillPackage;
  if (license !== 'MPL-2.0') {
    throw new Error('Review webextension-polyfill notices for its new license');
  }

  const polyfillFiles = ['LICENSE', 'dist/browser-polyfill.js', 'dist/browser-polyfill.js.map'].map((fileName) => [
    `third-party-licenses/webextension-polyfill/${path.basename(fileName)}`,
    () => fs.readFileSync(require.resolve(`webextension-polyfill/${fileName}`)),
  ]);

  return {
    'THIRD_PARTY_NOTICES.txt': () => fs
      .readFileSync(path.resolve(ROOT_DIR, 'src/extension/thirdPartyNotices.txt'), 'utf8')
      .replaceAll('{{VERSION}}', version),
    ...Object.fromEntries(polyfillFiles),
  };
}

function buildExtensionManifest(csp: string) {
  const manifest = JSON.parse(fs.readFileSync(path.resolve(ROOT_DIR, 'src/extension/manifest.json'), 'utf8'));
  manifest.version = getAppVersion();
  manifest.name = EXTENSION_NAME;
  manifest.description = EXTENSION_DESCRIPTION;
  manifest.content_security_policy = {
    extension_pages: csp,
  };
  manifest.action = { default_title: APP_NAME };
  manifest.icons = IS_GRAM_WALLET
    ? {
      192: 'gramWallet/icon-192x192.png',
      256: 'gramWallet/icon-256x256.png',
      512: 'gramWallet/icon-512x512.png',
    }
    : { 192: 'icon-192x192.png', 384: 'icon-384x384.png', 512: 'icon-512x512.png' };

  if (IS_FIREFOX_EXTENSION) {
    manifest.background = {
      scripts: [manifest.background.service_worker],
    };
    manifest.host_permissions = ['<all_urls>'];
    manifest.permissions = manifest.permissions.filter((value: string) => value !== 'system.display');
    manifest.browser_specific_settings = {
      gecko: {
        id: '{98fcdaee-2b58-4f71-8a3c-f0c66f24dede}',
        // The oldest ESR that runs Manifest V3 (109) and module workers (114). Keep in sync with `.browserslistrc`.
        strict_min_version: '115.0',
      },
    };
  }

  return JSON.stringify(manifest, undefined, 2);
}

function buildHeaders(template: string, csp: string) {
  const headers = template.replace('{{CSP}}', `${csp} ${cspFrameAncestors}`.trim());

  // Consolidate the retiring mytonwallet.app brand host onto mywallet.io in search. The app
  // keeps serving on .app (installed PWAs and deeplinks pin it), so this is a canonical
  // header rather than a redirect; the same site also answers on web(.beta).mywallet.io, which
  // self-canonicalizes. Omitted for Gram: it is a different brand
  // (wallet.ton.org ships to ton-blockchain/ton-wallet) and must never point at mywallet.io.
  const canonical = IS_GRAM_WALLET ? undefined
    : APP_ENV === 'staging' ? 'https://web-beta.mywallet.io/'
      : 'https://web.mywallet.io/';
  return canonical
    ? headers.replace('{{CANONICAL}}', canonical)
    : headers.replace(/^.*\{\{CANONICAL\}\}.*\n?/m, '');
}

/**
 * Builds the scripts listed in `EXTENSION_SCRIPTS` next to the popup bundle once it is written. Every script
 * is a separate IIFE build with its dynamic imports inlined, so it never needs to load a chunk.
 */
function buildExtensionScripts({ mode, define, shouldMinify, sourcemap }: {
  mode: string;
  define: Record<string, string>;
  shouldMinify: boolean;
  sourcemap: boolean;
}): Plugin {
  let outDir: string;

  return {
    name: 'mtw:extension-scripts',
    apply: 'build',

    configResolved(config) {
      outDir = config.build.outDir;
    },

    async closeBundle() {
      for (const [name, entry] of Object.entries(EXTENSION_SCRIPTS)) {
        const baseConfig = createBaseConfig({
          mode,
          isProduction: APP_ENV === 'production',
          shouldMinify,
          sourcemap,
          outDir,
          banner: EXTENSION_BANNER,
        });

        await build(mergeConfig(baseConfig, {
          configFile: false,
          root: ROOT_DIR,
          logLevel: 'warn',
          define,
          resolve: { alias: ALIASES },
          build: {
            emptyOutDir: false,
            rolldownOptions: {
              input: path.resolve(ROOT_DIR, entry),
              // Vite's dynamic import helper reads `import.meta` to locate chunks, and a single file has none
              checks: { emptyImportMeta: false },
              output: {
                format: 'iife',
                entryFileNames: `${name}.js`,
                codeSplitting: false,
              },
            },
          },
        }));
      }
    },
  };
}

function buildCsp(isDevServer: boolean) {
  // The dev server injects CSS with `<style>` elements
  const cspStyleSrcExtra = isDevServer ? ' \'unsafe-inline\'' : '';

  // The `media-src` rule contains `data:` because of iOS sound initialization.
  return `
    default-src 'none';
    manifest-src 'self';
    connect-src 'self' blob: ${cspConnectSrcHosts} ${cspConnectSrcExtra};
    script-src 'self' 'wasm-unsafe-eval' ${cspScriptSrcExtra};
    style-src 'self' https://fonts.googleapis.com/${cspStyleSrcExtra};
    img-src 'self' data: blob: https: ${cspImageSrcHosts};
    media-src 'self' data: https://static.mytonwallet.org/;
    object-src 'none';
    base-uri 'none';
    font-src 'self' https://fonts.gstatic.com/;
    form-action 'none';
    frame-src 'self' https: ${cspFrameSrcExtra};`
    .replace(/\s+/g, ' ').trim();
}

function getAppVersion(): string {
  return JSON.parse(fs.readFileSync(path.resolve(ROOT_DIR, 'package.json'), 'utf8')).version;
}

function getBuildBranch() {
  const fromEnv = process.env.BRANCH || process.env.GITHUB_REF_NAME;
  if (fromEnv) {
    return fromEnv;
  }

  // A detached HEAD, which is how CI checks out, makes git name the branch "HEAD" - identifies nothing.
  const branch = runGit(['rev-parse', '--abbrev-ref', 'HEAD']);
  return branch === 'HEAD' ? undefined : branch;
}

// Resolved per build, so a watch session reports the build it has just produced rather than the
// moment this config was loaded.
function getBuildInfo() {
  return `${([
    ['version', getAppVersion()],
    ['commit', appCommitHash],
    ['branch', getBuildBranch()],
    ['env', APP_ENV],
    ['built', new Date().toISOString()],
    ['deploy', process.env.DEPLOY_ID], // Netlify only: links the served bundle to its deploy log.
  ] as [string, string | undefined][])
    .filter(([, value]) => value)
    .map(([key, value]) => `${key}=${value}`)
    .join('\n')}\n`;
}

function runGit(args: string[]) {
  try {
    return execFileSync('git', args, { cwd: ROOT_DIR, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return undefined;
  }
}

/**
 * Adds a trailing slash to the given url.
 * This is needed for the CSP to work correctly:
 *  - paths that end in `/` match any path they are a prefix of. For example:
 *    `example.com/api/` will permit resources from `example.com/api/users/new`.
 *
 * https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy#host-source
 */
function ensureTrailingSlash(url: string) {
  return url.endsWith('/') ? url : url + '/';
}
