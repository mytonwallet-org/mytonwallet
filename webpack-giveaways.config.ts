import './dev/loadEnv';

import HtmlPlugin from 'html-webpack-plugin';
import MiniCssExtractPlugin from 'mini-css-extract-plugin';
import path from 'path';
import type { Configuration } from 'webpack';
import {
  EnvironmentPlugin, NormalModuleReplacementPlugin, ProvidePlugin,
} from 'webpack';

import { APP_ENV, GIVEAWAYS_API_URL } from './src/giveaways/config';

const cspConnectSrcExtra = APP_ENV === 'development'
  ? `http://localhost:5005 ${GIVEAWAYS_API_URL}`
  : GIVEAWAYS_API_URL;
const CSP = `
  default-src 'none';
  connect-src 'self' https: ${cspConnectSrcExtra};
  script-src 'self' 'wasm-unsafe-eval' https://challenges.cloudflare.com/;
  style-src 'self' https://fonts.googleapis.com/;
  img-src 'self' data: https:;
  media-src 'self' data:;
  object-src 'none';
  base-uri 'none';
  font-src 'self' https://fonts.gstatic.com/;
  form-action 'none';
  frame-src 'self' https://challenges.cloudflare.com/`
  .replace(/\s+/g, ' ').trim();

export default function createConfig(
  _: any,
  { mode = 'production' }: { mode: 'none' | 'development' | 'production' },
): Configuration {
  return {
    mode,

    entry: {
      main: './src/giveaways/index.tsx',
    },

    devServer: {
      port: 4322,
      host: '0.0.0.0',
      allowedHosts: 'all',
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
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
        'Access-Control-Allow-Headers': 'X-Requested-With, content-type, Authorization',
      },
    },

    ignoreWarnings: [
      (warning) => {
        return /(config)|(windowEnvironment)/.test(warning.message);
      },
    ],

    output: {
      filename: '[name].[contenthash].js',
      path: path.resolve(__dirname, 'dist-giveaways'),
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
          test: /\.(woff(2)?|ttf|eot|svg|png|jpg|tgs|webp|mp3)(\?v=\d+\.\d+\.\d+)?$/,
          type: 'asset/resource',
        },
        {
          test: /\.wasm$/,
          type: 'asset/resource',
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
        stream: require.resolve('stream-browserify'),
        process: require.resolve('process/browser'),
      },
    },

    plugins: [
      new HtmlPlugin({
        template: 'src/giveaways/index.html',
        chunks: ['main'],
        csp: CSP,
        templateParameters: {
          'process.env.BASE_URL': process.env.BASE_URL,
        },
      }),
      new MiniCssExtractPlugin({
        filename: '[name].[contenthash].css',
        chunkFilename: '[name].[chunkhash].css',
        ignoreOrder: true,
      }),
      new ProvidePlugin({
        Buffer: ['buffer', 'Buffer'],
      }),
      new ProvidePlugin({
        process: 'process/browser',
      }),
      /* eslint-disable no-null/no-null */
      new EnvironmentPlugin({
        APP_ENV: 'production',
        GIVEAWAYS_API_URL: null,
        GIVEAWAY_CAPTCHA_PUBLIC_KEY: null,
      }),
      /* eslint-enable no-null/no-null */
      new NormalModuleReplacementPlugin(
        /src\/config\.ts/,
        './giveaways/config.ts',
      ),
      new NormalModuleReplacementPlugin(
        /src\/util\/windowEnvironment\.ts/,
        '../giveaways/utils/windowEnvironment.ts',
      ),
      new NormalModuleReplacementPlugin(
        /i18n\/en\.json/,
        '../giveaways/utils/mockI18nEn.json',
      ),
    ],
    devtool: APP_ENV === 'development' ? 'source-map' : 'hidden-source-map',
  };
}
