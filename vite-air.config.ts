import './dev/loadEnv';

import fs from 'fs';
import path from 'path';
import { defineConfig, mergeConfig } from 'vite';

import { defineEnv } from './plugins/env';
import { createBaseConfig, ROOT_DIR } from './plugins/viteBase';
import { APP_ENV } from './src/config';

const sdkName = process.env.IS_GRAM_WALLET === '1' ? 'gramwallet' : 'mytonwallet';

/**
 * The SDK the native Air apps load into a web view from `file://` with a plain `<script>` tag. It is a
 * single classic script that sets `window.airBridge`, so dynamic imports are inlined and nothing else is
 * emitted.
 */
export default defineConfig(({ mode }) => mergeConfig(createBaseConfig({
  mode,
  isProduction: APP_ENV === 'production',
  shouldMinify: APP_ENV === 'production',
  sourcemap: APP_ENV === 'production' ? false : 'inline',
  outDir: path.resolve(ROOT_DIR, 'dist-air'),
  // The native apps route network requests through `fetch`
  banner: 'window.XMLHttpRequest = undefined;',
}), {
  root: ROOT_DIR,
  publicDir: false,
  define: defineEnv({
    APP_ENV: 'production',
    IS_GRAM_WALLET: '0',
    IS_HEADLESS: '',
    APP_VERSION: JSON.parse(fs.readFileSync(path.resolve(ROOT_DIR, 'package.json'), 'utf8')).version,
    PLATFORM_ENV: '',
    IS_AIR_APP: '1',
    IS_ANDROID_DIRECT: '0',
    AGENT_OVERRIDE: 'no_override',
    AGENT_V2_QUOTA_STATUS_ENABLED: '0',
    AGENT_API_URL: '',
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
    UTXO_MAINNET_RPC_URL: '',
    UTXO_TESTNET_RPC_URL: '',
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
    NO_UTXO: '0',
    NO_WALLETCONNECT: '0',
    NO_SWAP: '0',
    NO_STAKING: '0',
    NO_PORTFOLIO: '0',
    NO_MFA: '0',
    NO_EXTRA_FEATURES: '0',
    NO_LEDGER: '0',
  }),
  build: {
    // `deploy/build_sdk.sh` builds both SDKs into the same directory
    emptyOutDir: process.env.SDK_OUTPUT_CLEAN !== '0',
    rolldownOptions: {
      input: path.resolve(ROOT_DIR, 'src/api/air/index.ts'),
      // Vite's dynamic import helper reads `import.meta` to locate chunks, and a single file has none
      checks: { emptyImportMeta: false },
      output: {
        format: 'iife',
        entryFileNames: `${sdkName}-sdk.js`,
        codeSplitting: false,
      },
    },
  },
}));
