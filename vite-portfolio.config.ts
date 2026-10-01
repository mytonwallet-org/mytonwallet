import './dev/loadEnv';

import path from 'path';
import { defineConfig } from 'vite';

import { ROOT_DIR } from './plugins/viteBase';
import { createSiteConfig } from './plugins/viteSite';

const CSP = `
  default-src 'none';
  manifest-src 'self';
  connect-src 'self' https: http://localhost:3100;
  script-src 'self' 'wasm-unsafe-eval';
  style-src 'self' 'unsafe-inline' https://fonts.googleapis.com/;
  img-src 'self' data: https:;
  media-src 'self' data:;
  object-src 'none';
  base-uri 'none';
  font-src 'self' https://fonts.gstatic.com/;
  form-action 'none';
  frame-src 'self'`
  .replace(/\s+/g, ' ').trim();

export default defineConfig((configEnv) => createSiteConfig(configEnv, {
  name: 'portfolio',
  port: 4325,
  csp: CSP,
  env: {
    APP_ENV: 'production',
    IS_HEADLESS: '',
    PORTFOLIO_API_URL: '',
  },
  defaultLangPackFile: path.resolve(ROOT_DIR, 'src/portfolio/utils/mockI18nEn.json'),
}));
