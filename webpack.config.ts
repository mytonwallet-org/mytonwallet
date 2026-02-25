import './dev/loadEnv';
import 'webpack-dev-server';

import WatchFilePlugin from '@mytonwallet/webpack-watch-file-plugin';
import StatoscopeWebpackPlugin from '@statoscope/webpack-plugin';
// @ts-ignore
import PreloadWebpackPlugin from '@vue/preload-webpack-plugin';
import CopyWebpackPlugin from 'copy-webpack-plugin';
import fs from 'fs';
import { GitRevisionPlugin } from 'git-revision-webpack-plugin';
import HtmlPlugin from 'html-webpack-plugin';
import MiniCssExtractPlugin from 'mini-css-extract-plugin';
import path from 'path';
import type { Compiler, Configuration } from 'webpack';
import { EnvironmentPlugin, IgnorePlugin, ProvidePlugin } from 'webpack';

import { convertI18nYamlToJson } from './dev/locales/convertI18nYamlToJson';
import {
  APP_COMMIT_HASH,
  APP_ENV,
  APP_NAME,
  BASE_URL,
  BRILLIANT_API_BASE_URL,
  EXTENSION_DESCRIPTION,
  EXTENSION_NAME,
  IFRAME_WHITELIST,
  IPFS_GATEWAY_BASE_URL,
  IS_CAPACITOR,
  IS_CORE_WALLET,
  IS_EXPLORER,
  IS_EXTENSION,
  IS_FIREFOX_EXTENSION,
  IS_OPERA_EXTENSION,
  IS_PACKAGED_ELECTRON,
  IS_TELEGRAM_APP,
  MTW_STATIC_BASE_URL,
  PROXY_API_BASE_URL,
  SOLANA_MAINNET_API_URL,
  SOLANA_MAINNET_RPC_URL,
  SOLANA_TESTNET_API_URL,
  SOLANA_TESTNET_RPC_URL,
  SSE_BRIDGE_URL,
  SUBPROJECT_URL_MASK,
  TONAPIIO_MAINNET_URL,
  TONAPIIO_TESTNET_URL,
  TONCENTER_MAINNET_URL,
  TONCENTER_TESTNET_URL,
  TRON_MAINNET_API_URL,
  TRON_TESTNET_API_URL,
  WALLET_CONNECT_BRIDGE_PATTERNS,
} from './src/config';

const destinationDir = path.resolve(__dirname, 'dist');
const appCommitHash = APP_COMMIT_HASH || new GitRevisionPlugin().commithash();
const isStatoscopeBuild = process.env.IS_STATOSCOPE === '1'; // "Statoscope build" is a special mode where all the entries are used. It is used for comprehensive code size comparison in PRs.
const isWebApp = !(IS_EXTENSION || IS_PACKAGED_ELECTRON || IS_CAPACITOR);
const canUseStatoscope = isStatoscopeBuild || isWebApp;
const cspConnectSrcExtra = APP_ENV === 'development'
  ? `http://localhost:3000 ${process.env.CSP_CONNECT_SRC_EXTRA_URL}`
  : '';
const cspScriptSrcExtra = IS_TELEGRAM_APP ? 'https://telegram.org' : '';
const cspFrameSrcExtra = IS_CORE_WALLET ? '' : [
  'https://buy-sandbox.moonpay.com/',
  'https://buy.moonpay.com/',
  'https://sell.moonpay.com/',
  'https://sell-sandbox.moonpay.com/',
  'https://*.onetrust.com/', // This is a GDPR cookie consent widget from Moonpay
  'https://dreamwalkers.io/',
  'https://avanchange.com/',
  ...IFRAME_WHITELIST,
  SUBPROJECT_URL_MASK,
].join(' ');

const cspConnectSrcHosts = Array.from(new Set([
  BRILLIANT_API_BASE_URL,
  BRILLIANT_API_BASE_URL.replace(/^http(s?):/, 'ws$1:'),
  ensureTrailingSlash(PROXY_API_BASE_URL),
  MTW_STATIC_BASE_URL,
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
  ensureTrailingSlash(IPFS_GATEWAY_BASE_URL),
  ensureTrailingSlash(SSE_BRIDGE_URL),
])).join(' ');

const cspImageSrcHosts = [
  MTW_STATIC_BASE_URL,
  'https://imgproxy.mytonwallet.org',
  'https://dns-image.mytonwallet.org',
  'https://mytonwallet.s3.eu-central-1.amazonaws.com',
  'https://cache.tonapi.io', // Deprecated
  'https://c.tonapi.io',
  'https://imgproxy.toncenter.com',
  'https://web-api.changelly.com',
].join(' ');

// The `media-src` rule contains `data:` because of iOS sound initialization.
const CSP = `
  default-src 'none';
  manifest-src 'self';
  connect-src 'self' blob: ${cspConnectSrcHosts} ${cspConnectSrcExtra};
  script-src 'self' 'wasm-unsafe-eval' ${cspScriptSrcExtra};
  style-src 'self' https://fonts.googleapis.com/;
  img-src 'self' data: blob: https: ${cspImageSrcHosts};
  media-src 'self' data: https://static.mytonwallet.org/;
  object-src 'none';
  base-uri ${IS_EXPLORER ? '\'self\'' : '\'none\''};
  font-src 'self' https://fonts.gstatic.com/;
  form-action 'none';
  frame-src 'self' https: ${cspFrameSrcExtra};`
  .replace(/\s+/g, ' ').trim();

// eslint-disable-next-line @typescript-eslint/no-require-imports
const appVersion = require('./package.json').version;

const defaultI18nFilename = path.resolve(__dirname, './src/i18n/en.json');

const statoscopeStatsFilename = 'statoscope-build-statistics.json';
const statoscopeStatsFileToCompare = process.env.STATOSCOPE_STATS_TO_COMPARE;
// If a compared stat file name is the same as the main stats file name, the Statoscope UI doesn't show it.
if (path.basename(statoscopeStatsFileToCompare || '') === statoscopeStatsFilename) {
  throw new Error(`The STATOSCOPE_STATS_TO_COMPARE file name mustn't be ${statoscopeStatsFilename}`);
}

export default function createConfig(
  _: any,
  { mode = 'production' }: { mode: 'none' | 'development' | 'production' },
): Configuration {
  return {
    mode,
    target: 'web',

    optimization: {
      minimize: APP_ENV === 'production' && !IS_EXTENSION,
      usedExports: true,
      ...(APP_ENV === 'staging' && {
        chunkIds: 'named',
      }),
      ...(IS_CAPACITOR && {
        splitChunks: false,
      }),
    },

    entry: {
      main: './src/index.tsx',
      ...((IS_EXTENSION || isStatoscopeBuild) && {
        extensionServiceWorker: {
          import: './src/extension/serviceWorker.ts',
          // Extension service worker isn't allowed to load code dynamically. This option inlines all dynamic imports.
          chunkLoading: false,
        },
        extensionContentScript: './src/extension/contentScript.ts',
        extensionPageScript: './src/extension/pageScript/index.ts',
      }),
    },

    devServer: {
      port: 4321,
      host: '0.0.0.0',
      allowedHosts: 'all',
      hot: false,
      // When using the History API, the index.html page will likely have to be served in place of any 404 responses
      // https://webpack.js.org/configuration/dev-server/#devserverhistoryapifallback
      historyApiFallback: IS_EXPLORER,
      static: [
        {
          directory: path.resolve(__dirname, 'public'),
        },
        {
          directory: path.resolve(__dirname, 'src/lib/rlottie'),
        },
      ],
      devMiddleware: {
        stats: 'minimal',
      },
      headers: {
        'Content-Security-Policy': CSP,
      },
    },

    watchOptions: { ignored: defaultI18nFilename },

    output: {
      filename: (pathData) => (pathData.chunk?.name?.startsWith('extension') ? '[name].js' : '[name].[contenthash].js'),
      chunkFilename: '[id].[chunkhash].js',
      assetModuleFilename: '[name].[contenthash][ext]',
      path: destinationDir,
      clean: true,
    },

    module: {
      rules: [
        {
          test: /\.(ts|tsx|js|mjs|cjs)$/,
          loader: 'babel-loader',
          exclude: /node_modules/,
        },
        {
          test: /\.css$/,
          use: [
            MiniCssExtractPlugin.loader,
            {
              loader: 'css-loader',
              options: {
                importLoaders: 1,
              },
            },
            'postcss-loader',
          ],
        },
        {
          test: /\.module\.scss$/,
          use: [
            MiniCssExtractPlugin.loader,
            {
              loader: 'css-loader',
              options: {
                modules: {
                  namedExport: false,
                  exportLocalsConvention: 'camelCase',
                  auto: true,
                  localIdentName: APP_ENV === 'production' ? '[sha1:hash:base64:8]' : '[name]__[local]',
                },
              },
            },
            'postcss-loader',
            'sass-loader',
          ],
        },
        {
          test: /\.scss$/,
          exclude: /\.module\.scss$/,
          use: [MiniCssExtractPlugin.loader, 'css-loader', 'postcss-loader', 'sass-loader'],
        },
        {
          test: /\.(woff(2)?|ttf|eot|svg|png|jpg|tgs|webp|mp3|mp4|avif)(\?v=\d+\.\d+\.\d+)?$/,
          type: 'asset/resource',
        },
        {
          test: /\.wasm$/,
          type: 'asset/resource',
        },
        {
          test: /\.(txt|tl)$/i,
          type: 'asset/source',
        },
        {
          test: /\.m?js$/,
          resolve: {
            fullySpecified: false,
          },
        },
      ],
    },

    resolve: {
      extensions: ['.js', '.cjs', '.mjs', '.ts', '.tsx'],
      fallback: {
        crypto: false,
        stream: require.resolve('stream-browserify'),
        process: require.resolve('process/browser'),
      },
      alias: {
        // It is used to remove duplicate dependencies
        'bn.js': path.join(__dirname, 'node_modules/bn.js/lib/bn.js'),
        // By default, the bundle for Node is imported
        tronweb: path.join(__dirname, 'node_modules/tronweb/dist/TronWeb.js'),
      },
    },

    plugins: [
      ...(IS_OPERA_EXTENSION ? [{
        apply: (compiler: Compiler) => {
          compiler.hooks.afterDone.tap('After Compilation', async () => {
            for (const filename of await fs.promises.readdir(destinationDir)) {
              const file = path.join(destinationDir, filename);

              if (file.endsWith('.tgs')) {
                await fs.promises.rename(file, file.replace('.tgs', '.json'));
              } else if (filename.includes('main') && filename.endsWith('.js')) {
                const content = (await fs.promises.readFile(file))
                  .toString('utf-8')
                  .replace(/\.tgs"/g, '.json"');
                await fs.promises.writeFile(file, content);
              }
            }
          });
        },
      }] : []),
      new WatchFilePlugin({
        rules: [
          {
            name: 'i18n to JSON conversion',
            files: 'src/i18n/en.yaml',
            action: (filePath) => {
              const defaultI18nYaml = fs.readFileSync(filePath, 'utf8');
              const defaultI18nJson = convertI18nYamlToJson(defaultI18nYaml, mode === 'production');

              if (!defaultI18nJson) {
                return;
              }

              fs.writeFileSync(defaultI18nFilename, defaultI18nJson, 'utf-8');
            },
            firstCompilation: true,
          },
          {
            name: 'Icon font generation',
            files: 'src/assets/font-icons/*.svg',
            action: 'npm run build:icons',
            sharedAction: true,
          },
        ],
      }),
      // Do not add the BIP39 word list in other languages
      new IgnorePlugin({
        checkResource(resource) {
          return /.*\/wordlists\/(?!english).*\.json/.test(resource);
        },
      }),
      new HtmlPlugin({
        template: 'src/index.html',
        chunks: ['main'],
        csp: CSP,
        title: APP_NAME,
        homepage: IS_CORE_WALLET ? 'https://wallet.ton.org' : 'https://mytonwallet.io',
        assets_prefix: IS_CORE_WALLET ? 'coreWallet/' : '',
      }),
      new PreloadWebpackPlugin({
        include: 'allAssets',
        fileWhitelist: [
          /duck_.*?\.png/, // Lottie thumbs
          /coin_.*?\.png/, // Coin icons
          /theme_.*?\.png/, // Theme icons
          /chain_.*?\.png/, // Chain icons
          /settings_.*?\.svg/, // Settings icons (svg)
          ...(IS_CORE_WALLET ? [
            /core_wallet_.*?\.png/, // Lottie thumbs for TON Wallet
          ] : []),
        ],
        as(entry: string) {
          if (/\.png$/.test(entry)) return 'image';
          if (/\.svg$/.test(entry)) return 'image';
          return 'script';
        },
      }),
      new MiniCssExtractPlugin({
        filename: '[name].[contenthash].css',
        chunkFilename: '[name].[chunkhash].css',
        ignoreOrder: true,
      }),
      new EnvironmentPlugin({
        APP_ENV: 'production',
        APP_NAME: '',
        APP_VERSION: appVersion,
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
        IS_CAPACITOR: 'false',
        IS_AIR_APP: 'false',
        IS_CORE_WALLET: 'false',
        IS_TELEGRAM_APP: 'false',
        IS_EXPLORER: 'false',
        SWAP_FEE_ADDRESS: '',
        DIESEL_ADDRESS: '',
        GIVEAWAY_CHECKIN_URL: '',
        PROXY_API_BASE_URL: '',
        WALLET_CONNECT_PROJECT_ID: '',
      }),
      new ProvidePlugin({
        Buffer: ['buffer', 'Buffer'],
      }),
      new ProvidePlugin({
        process: 'process/browser',
      }),
      new CopyWebpackPlugin({
        patterns: [
          {
            from: 'src/extension/manifest.json',
            transform: (content) => {
              const manifest = JSON.parse(content.toString());
              manifest.version = appVersion;
              manifest.name = EXTENSION_NAME;
              manifest.description = EXTENSION_DESCRIPTION;
              manifest.content_security_policy = {
                extension_pages: CSP,
              };
              manifest.action = { default_title: APP_NAME };
              manifest.icons = IS_CORE_WALLET
                ? {
                  192: 'coreWallet/icon-192x192.png',
                  256: 'coreWallet/icon-256x256.png',
                  512: 'coreWallet/icon-512x512.png',
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
                    strict_min_version: '91.1.0', // Minimum version for using a proxy
                  },
                };
              }

              return JSON.stringify(manifest, undefined, 2);
            },
          },
          {
            from: 'src/i18n/*.yaml',
            to: 'i18n/[name].json',
            transform: (content: Buffer) => convertI18nYamlToJson(
              content as unknown as string, mode === 'production',
            ) as any,
          },
          {
            from: IS_TELEGRAM_APP ? 'src/_headers_telegram' : 'src/_headers',
            transform: (content: Buffer) => content.toString().replace('{{CSP}}', CSP),
          },
        ],
      }),
      ...(canUseStatoscope ? [new StatoscopeWebpackPlugin({
        statsOptions: {
          context: __dirname,
        },
        saveReportTo: path.join(destinationDir, 'statoscope-report.html'),
        saveStatsTo: path.join(destinationDir, statoscopeStatsFilename),
        normalizeStats: true,
        open: false,
        extensions: [new WebpackContextExtension()],
        ...(statoscopeStatsFileToCompare ? { additionalStats: [statoscopeStatsFileToCompare] } : undefined),
      })] : []),
    ],

    devtool: IS_EXTENSION ? 'cheap-source-map' : APP_ENV === 'production' && !isWebApp ? undefined : 'source-map',
  };
}

class WebpackContextExtension {
  context: string;

  constructor() {
    this.context = '';
  }

  handleCompiler(compiler: Compiler) {
    this.context = compiler.context;
  }

  getExtension() {
    return {
      descriptor: { name: 'custom-webpack-extension-context', version: '1.0.0' },
      payload: { context: this.context },
    };
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
