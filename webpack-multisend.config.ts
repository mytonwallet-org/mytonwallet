import './dev/loadEnv';

import StatoscopeWebpackPlugin from '@statoscope/webpack-plugin';
import HtmlPlugin from 'html-webpack-plugin';
import MiniCssExtractPlugin from 'mini-css-extract-plugin';
import path from 'path';
import type { Compiler, Configuration } from 'webpack';
import {
  EnvironmentPlugin, NormalModuleReplacementPlugin, ProvidePlugin,
} from 'webpack';

import { APP_ENV } from './src/multisend/config';

const destinationDir = path.resolve(__dirname, 'dist-multisend');

const CSP = `
  default-src 'none';
  manifest-src 'self';
  connect-src 'self' https:;
  script-src 'self' 'wasm-unsafe-eval';
  style-src 'self' https://fonts.googleapis.com/;
  img-src 'self' data: https:;
  media-src 'self' data:;
  object-src 'none';
  base-uri 'none';
  font-src 'self' https://fonts.gstatic.com/;
  form-action 'none';
  frame-src 'self'`
  .replace(/\s+/g, ' ').trim();

export default function createConfig(
  _: any,
  { mode = 'production' }: { mode: 'none' | 'development' | 'production' },
): Configuration {
  return {
    mode,

    entry: {
      main: './src/multisend/index.tsx',
    },

    devServer: {
      port: 4323,
      host: '0.0.0.0',
      allowedHosts: 'all',
      static: [
        {
          directory: path.resolve(__dirname, 'src/multisend/public'),
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
      new HtmlPlugin({
        template: 'src/multisend/index.html',
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
      }),
      new NormalModuleReplacementPlugin(
        /i18n\/en\.json/,
        '../multisend/utils/mockI18nEn.json',
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
