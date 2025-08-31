// todo: When the mobile apps become fully air (with no legacy Capacitor mode), this configuration should be merged into
// webpack.config.ts (src/api/air/index.ts should become an entry). It is not possible yet, because a different
// IS_AIR_APP value need to be injected into different entries, which is not possible with Webpack. When the Capacitor
// mode is removed, IS_AIR_APP will be `1` in all the entries.

import dotenv from 'dotenv';
import path from 'path';
import type { Configuration } from 'webpack';
import { BannerPlugin, EnvironmentPlugin, ProvidePlugin } from 'webpack';

dotenv.config();

const { APP_ENV = 'production' } = process.env;

// eslint-disable-next-line @typescript-eslint/no-require-imports
const appVersion = require('./package.json').version;

export default function createConfig(
  _: any,
  { mode = 'production' }: { mode: 'none' | 'development' | 'production' },
): Configuration {
  return {
    mode,

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
      filename: 'mytonwallet-sdk.js',
      path: path.resolve(__dirname, 'dist-air'),
      clean: true,
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
      new ProvidePlugin({
        Buffer: ['buffer', 'Buffer'],
      }),
      new ProvidePlugin({
        process: 'process/browser',
      }),
      new EnvironmentPlugin({
        APP_ENV: 'production',
        APP_VERSION: appVersion,
        IS_CAPACITOR: '1',
        IS_AIR_APP: '1',
        TONHTTPAPI_MAINNET_URL: '',
        TONHTTPAPI_MAINNET_API_KEY: '',
        TONHTTPAPI_TESTNET_URL: '',
        TONHTTPAPI_TESTNET_API_KEY: '',
        TONAPIIO_MAINNET_URL: '',
        TONAPIIO_TESTNET_URL: '',
        TONHTTPAPI_V3_MAINNET_API_KEY: '',
        TONHTTPAPI_V3_TESTNET_API_KEY: '',
        BRILLIANT_API_BASE_URL: '',
        TRON_MAINNET_API_URL: '',
        TRON_TESTNET_API_URL: '',
        PROXY_HOSTS: '',
        STAKING_POOLS: '',
      }),
    ],

    devtool: APP_ENV === 'production' ? undefined : 'inline-source-map',
  };
}
