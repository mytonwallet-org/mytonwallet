import mtwConfig from '@mytonwallet/eslint-config';
import { globalIgnores } from 'eslint/config';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  mtwConfig.configs.frontendRecommended,
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
    'src/lib/axios-retry/',
    'src/lib/is-retry-allowed/',
    'src/push/lib/zk-email-helpers/',
    '.github/',
    'babel.config.js',
    'jest.config.js',
    'playwright.config.ts',
    'postcss.config.js',
    'coverage',
    'trash',
    'deploy',
    'dist',
    'dist-electron',
    'dist-air',
  ]),
);
