import './dev/loadEnv';

import path from 'path';
import { defineConfig } from 'vite';

import { buildMfaLocales } from './dev/locales/buildMfaLocales';
import { writeJsonLangPack } from './plugins/langPacks';
import { ROOT_DIR } from './plugins/viteBase';
import { createSiteConfig } from './plugins/viteSite';
import { APP_ENV, IS_TELEGRAM_APP, TONAPIIO_MAINNET_URL } from './src/config';
import { MFA_API_URL } from './src/mfa/config';

const GENERATED_I18N_DIR = path.resolve(ROOT_DIR, 'src/mfa/i18n-generated');

const cspConnectSrcHosts = [
  'https://toncenter.mytonwallet.org/',
  'https://raw.githubusercontent.com/ton-blockchain/wallets-list/',
  'https://tonconnectbridge.mytonwallet.org/',
  MFA_API_URL,
  TONAPIIO_MAINNET_URL,
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

export default defineConfig((configEnv) => createSiteConfig(configEnv, {
  name: 'mfa',
  port: 4324,
  csp: CSP,
  env: {
    APP_ENV: 'production',
    IS_TELEGRAM_APP: 'false',
    IS_HEADLESS: '',
    MFA_APP_URL: '',
    MFA_API_URL: '',
    TONCENTER_MAINNET_URL: '',
    TONCENTER_MAINNET_KEY: '',
    TONAPIIO_MAINNET_URL: '',
  },
  defaultLangPackFile: path.join(GENERATED_I18N_DIR, 'en.json'),
  langPackDir: GENERATED_I18N_DIR,
  langPackGenerator: {
    dir: path.resolve(ROOT_DIR, 'src/mfa/i18n'),
    generate() {
      buildMfaLocales();
      writeJsonLangPack(
        path.join(GENERATED_I18N_DIR, 'en.yaml'),
        path.join(GENERATED_I18N_DIR, 'en.json'),
        configEnv.mode === 'production',
      );
    },
  },
  htmlVariables: {
    HTML_CLASS_EXTRA: IS_TELEGRAM_APP ? ' force-transparent-bg' : '',
    TELEGRAM_SCRIPT: IS_TELEGRAM_APP ? '<script src="https://telegram.org/js/telegram-web-app.js"></script>' : '',
  },
}));
