import './dev/loadEnv';

import WatchFilePlugin from '@mytonwallet/webpack-watch-file-plugin';
import StatoscopeWebpackPlugin from '@statoscope/webpack-plugin';
import CopyWebpackPlugin from 'copy-webpack-plugin';
import fs from 'fs';
import HtmlPlugin from 'html-webpack-plugin';
import MiniCssExtractPlugin from 'mini-css-extract-plugin';
import path from 'path';
import type { Compiler, Configuration } from 'webpack';
import { EnvironmentPlugin, NormalModuleReplacementPlugin, ProvidePlugin } from 'webpack';

import { convertI18nYamlToJson } from './dev/locales/convertI18nYamlToJson';
import { APP_ENV, IS_TELEGRAM_APP } from './src/config';
import { PUSH_API_URL } from './src/push/config';

const destinationDir = path.resolve(__dirname, 'dist-push');
const defaultI18nFilename = path.resolve(__dirname, './src/push/i18n/en.json');

const cspConnectSrcHosts = [
  'https://toncenter.mytonwallet.org/',
  'https://raw.githubusercontent.com/ton-blockchain/wallets-list/',
  'https://tonconnectbridge.mytonwallet.org/',
  PUSH_API_URL,
  'https://mytonwalletorg--jwt-prover-v0-1-0-jwtprover-endpoint.modal.run',
].filter(Boolean).join(' ');

const cspConnectSrcExtra = APP_ENV === 'development'
  ? `http://localhost:3000 ${process.env.CSP_CONNECT_SRC_EXTRA_URL}`
  : '';

const cspScriptSrcExtra = IS_TELEGRAM_APP ? 'https://telegram.org' : '';
const scpScriptSrc = [
  'https://accounts.google.com/gsi/client',
  'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/',
  'https://alcdn.msauth.net/browser/',
  cspScriptSrcExtra,
].filter(Boolean).join(' ');

const CSP = `
  default-src 'none';
  manifest-src 'self';
  connect-src 'self' blob: https: ${cspConnectSrcHosts} ${cspConnectSrcExtra};
  script-src 'self' 'wasm-unsafe-eval' ${scpScriptSrc};
  style-src 'self' 'unsafe-inline' https://fonts.googleapis.com/ https://accounts.google.com/gsi/style;
  img-src 'self' data: https:;
  media-src 'self' data:;
  object-src 'none';
  base-uri 'none';
  font-src 'self' https://fonts.gstatic.com/;
  form-action 'none';
  frame-src 'self' https://accounts.google.com/;
  worker-src 'self' blob:`
  .replace(/\s+/g, ' ').trim();

export default function createConfig(
  _: any,
  { mode = 'production' }: { mode: 'none' | 'development' | 'production' },
): Configuration {
  return {
    mode,

    entry: {
      main: './src/push/index.tsx',
    },

    devServer: {
      port: 4324,
      host: '0.0.0.0',
      allowedHosts: 'all',
      static: [
        {
          directory: path.resolve(__dirname, 'src/push/public'),
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

    watchOptions: { ignored: defaultI18nFilename },

    output: {
      filename: '[name].[contenthash].js',
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
      new WatchFilePlugin({
        rules: [
          {
            name: 'i18n to JSON conversion',
            files: 'src/push/i18n/en.yaml',
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
        ],
      }),
      new HtmlPlugin({
        template: 'src/push/index.html',
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

      new EnvironmentPlugin({
        APP_ENV: 'production',
        IS_TELEGRAM_APP: 'false',
        PUSH_APP_URL: '',
        PUSH_API_URL: '',
        PUSH_GOOGLE_OAUTH_CLIENT_ID: '',
        PUSH_APPLE_OAUTH_CLIENT_ID: '',
        PUSH_MICROSOFT_OAUTH_CLIENT_ID: '',
        PUSH_FACEBOOK_OAUTH_CLIENT_ID: '',
      }),
      new CopyWebpackPlugin({
        patterns: [
          {
            from: 'src/push/i18n/*.yaml',
            to: 'i18n/[name].json',
            transform: (content: Buffer) => convertI18nYamlToJson(
              content as unknown as string, mode === 'production',
            ) as any,
          },
        ],
      }),
      new NormalModuleReplacementPlugin(
        /i18n\/en\.json/,
        // Seems to be a bug in NormalModuleReplacementPlugin, so we are forced to use the function approach
        (resource) => {
          resource.request = resource.request.replace(/i18n\/en\.json/, 'push/i18n/en.json');
        },
      ),
      new StatoscopeWebpackPlugin({
        statsOptions: {
          context: __dirname,
        },
        saveReportTo: path.join(destinationDir, 'statoscope-report.html'),
        saveStatsTo: path.join(destinationDir, 'statoscope-build-statistics.json'),
        normalizeStats: true,
        open: 'file',
        extensions: [new WebpackContextExtension()],
      }),
    ],
    devtool: APP_ENV === 'development' ? 'source-map' : 'hidden-source-map',
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
