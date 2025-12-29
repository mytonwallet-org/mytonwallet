import './dev/loadEnv';

import path from 'path';
import { EnvironmentPlugin } from 'webpack';

import { APP_ENV, BASE_URL } from './src/config';

export default {
  mode: 'production',

  target: 'node',

  entry: {
    electron: './src/electron/main.ts',
    preload: './src/electron/preload.ts',
  },

  output: {
    filename: '[name].js',
    path: path.resolve(__dirname, 'dist'),
  },

  resolve: {
    extensions: ['.js', '.cjs', '.mjs', '.ts', '.tsx'],
  },

  plugins: [
    new EnvironmentPlugin({
      APP_ENV,
      BASE_URL,
      IS_PREVIEW: 'false',
    }),
  ],

  module: {
    rules: [
      {
        test: /\.(ts|tsx|js|mjs|cjs)$/,
        loader: 'babel-loader',
        exclude: /node_modules/,
      },
    ],
  },

  externals: {
    electron: 'require("electron")',
  },
};
