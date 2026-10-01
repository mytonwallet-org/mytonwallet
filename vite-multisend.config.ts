import './dev/loadEnv';

import path from 'path';
import { defineConfig } from 'vite';

import { ROOT_DIR } from './plugins/viteBase';
import { createSiteConfig } from './plugins/viteSite';

export default defineConfig((configEnv) => createSiteConfig(configEnv, {
  name: 'multisend',
  port: 4323,
  csp: `
    default-src 'none';
    manifest-src 'self';
    connect-src 'self' https:;
    script-src 'self' 'wasm-unsafe-eval';
    style-src 'self' https://fonts.googleapis.com/${configEnv.command === 'serve' ? ' \'unsafe-inline\'' : ''};
    img-src 'self' data: https:;
    media-src 'self' data:;
    object-src 'none';
    base-uri 'none';
    font-src 'self' https://fonts.gstatic.com/;
    form-action 'none';
    frame-src 'self'`
    .replace(/\s+/g, ' ').trim(),
  env: {
    APP_ENV: 'production',
    IS_HEADLESS: '',
  },
  defaultLangPackFile: path.resolve(ROOT_DIR, 'src/multisend/utils/mockI18nEn.json'),
}));
