import mtwConfig from '@mytonwallet/eslint-config';
import { globalIgnores } from 'eslint/config';
import tseslint from 'typescript-eslint';

import fileNamingConfig from './dev/fileNamingConfig.mjs';

export default tseslint.config(
  mtwConfig.configs.frontendRecommended.map((config) => ({
    ...config,
    ignores: [...(config.ignores || []), '**/*.module.scss'],
  })),
  ...fileNamingConfig,
  globalIgnores([
    'dev',
    'public',
    'mobile',
    'src/lib/big.js/',
    'src/lib/rlottie/rlottie-wasm.js',
    'src/lib/aes-js/index.js',
    'src/lib/noble-ed25519/index.js',
    'src/lib/tonConnectFriendlyPatch.js',
    'src/lib/dexie/',
    'src/lib/LovelyChart/',
    'src/push/lib/zk-email-helpers/',
    '.github/',
    '.claude/',
    'headless/',
    'babel.config.js',
    'jest.config.js',
    'playwright.agent-v2.config.ts',
    'postcss.config.js',
    'coverage',
    'trash',
    'deploy',
    'dist',
    'dist-electron',
    'dist-air',
    'dist-push',
  ]),
);
