import './dev/loadEnv';

import path from 'path';
import type { Configuration } from 'webpack';
import { BannerPlugin, EnvironmentPlugin, IgnorePlugin, ProvidePlugin } from 'webpack';

import { APP_ENV } from './src/config';

// eslint-disable-next-line @typescript-eslint/no-require-imports
const appVersion = require('./package.json').version;
const sdkName = process.env.IS_GRAM_WALLET === '1' ? 'gramwallet' : 'mytonwallet';

export default function createConfig(
  _: any,
  { mode = 'production' }: { mode: 'none' | 'development' | 'production' },
): Configuration {
  return {
    mode,

    ignoreWarnings: [
      { module: /src[\\/]api[\\/]storages[\\/]index\.ts$/, message: /Critical dependency/ },
    ],

    optimization: {
      usedExports: true,
      minimize: APP_ENV === 'production',
    },

    entry: {
      main: {
        import: './src/api/air/index.ts',
        // Air doesn't support dynamic importing. This option inlines all dynamic imports.
        chunkLoading: false,
      },
    },

    output: {
      filename: `${sdkName}-sdk.js`,
      path: path.resolve(__dirname, 'dist-air'),
      clean: process.env.SDK_OUTPUT_CLEAN !== '0',
    },

    module: {
      rules: [
        {
          test: /\.(ts|tsx|js)$/,
          loader: 'babel-loader',
          exclude: /node_modules/,
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
      extensions: ['.js', '.ts', '.tsx'],
      fallback: {
        stream: require.resolve('stream-browserify'),
        process: require.resolve('process/browser'),
      },
    },

    plugins: [
      new BannerPlugin({
        banner: 'window.XMLHttpRequest = undefined;',
        raw: true,
      }),
      new IgnorePlugin({
        checkResource(resource) {
          return /.*\/wordlists\/(?!english).*\.json/.test(resource);
        },
      }),
      new ProvidePlugin({
        Buffer: ['buffer', 'Buffer'],
      }),
      new ProvidePlugin({
        process: 'process/browser',
      }),
      new EnvironmentPlugin({
        APP_ENV: 'production',
        IS_GRAM_WALLET: '0',
        APP_VERSION: appVersion,
        PLATFORM_ENV: '',
        IS_CAPACITOR: '1',
        IS_AIR_APP: '1',
        IS_ANDROID_DIRECT: '0',
        TONCENTER_MAINNET_URL: '',
        TONCENTER_MAINNET_KEY: '',
        TONCENTER_TESTNET_URL: '',
        TONCENTER_TESTNET_KEY: '',
        TONAPIIO_MAINNET_URL: '',
        TONAPIIO_TESTNET_URL: '',
        BRILLIANT_API_BASE_URL: '',
        TRON_MAINNET_API_URL: '',
        SOLANA_MAINNET_API_URL: '',
        SOLANA_MAINNET_API_KEY: '',
        SOLANA_TESTNET_API_URL: '',
        SOLANA_TESTNET_API_KEY: '',
        TRON_TESTNET_API_URL: '',
        SOLANA_MAINNET_RPC_URL: '',
        SOLANA_TESTNET_RPC_URL: '',
        EVM_MAINNET_RPC_URL: '',
        EVM_TESTNET_RPC_URL: '',
        PROXY_HOSTS: '',
        STAKING_POOLS: '',
        BOT_USERNAME: '',
        SWAP_FEE_ADDRESS: '',
        DIESEL_ADDRESS: '',
        PROXY_API_BASE_URL: '',
        WALLET_CONNECT_PROJECT_ID: '',
        WALLET_CONNECT_PAY_APP_ID: '',
        MFA_API_BASE_URL: '',
        NO_TON: '0',
        NO_TRON: '0',
        NO_SOLANA: '0',
        NO_EVM: '0',
        NO_WALLETCONNECT: '0',
        NO_SWAP: '0',
        NO_STAKING: '0',
        NO_PORTFOLIO: '0',
        NO_MFA: '0',
        NO_LEDGER: '0',
        NO_NOTIFICATIONS: '0',
      }),
    ],

    devtool: APP_ENV === 'production' ? undefined : 'inline-source-map',
  };
}
