import path from 'path';
import type { ConfigEnv, Plugin, UserConfig } from 'vite';
import { mergeConfig } from 'vite';

import { emittedFiles } from './emittedFiles';
import { defineEnv } from './env';
import { htmlTemplate } from './htmlTemplate';
import { defaultLangPack, getLangPackFiles } from './langPacks';
import { createBaseConfig, ROOT_DIR } from './viteBase';

interface SiteOptions {
  // The site lives in `src/<name>` and builds into `dist-<name>`
  name: string;
  port: number;
  csp: string;
  env: Record<string, string>;
  // Replaces the app's `i18n/en.json`, which the shared `langProvider` bundles as the fallback lang pack
  defaultLangPackFile: string;
  // YAML lang packs served as `i18n/<langCode>.json`
  langPackDir?: string;
  // Regenerates `defaultLangPackFile` from the YAML files in `dir`
  langPackGenerator?: { dir: string; generate: NoneToVoidFunction };
  htmlVariables?: Record<string, string>;
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
  'Access-Control-Allow-Headers': 'X-Requested-With, content-type, Authorization',
};

/**
 * A standalone site built from `src/<name>` next to the wallet, such as MFA or Multisend. The sites reuse the
 * wallet's UI kit and API layer but have their own entry, CSP, environment and translations.
 */
export function createSiteConfig({ mode }: ConfigEnv, {
  name, port, csp, env, defaultLangPackFile, langPackDir, langPackGenerator, htmlVariables,
}: SiteOptions): UserConfig {
  const appEnv = process.env.APP_ENV || 'production';
  const isProductionMode = mode === 'production';
  const siteDir = path.resolve(ROOT_DIR, 'src', name);

  const baseConfig = createBaseConfig({
    mode,
    isProduction: appEnv === 'production',
    shouldMinify: isProductionMode,
    sourcemap: appEnv === 'development' ? true : 'hidden',
    outDir: path.resolve(ROOT_DIR, `dist-${name}`),
    devCssNames: '[name]__[local]',
  });

  const plugins: Plugin[] = [
    htmlTemplate({ CSP: csp, ...htmlVariables }),
    ...(langPackGenerator ? [defaultLangPack(langPackGenerator.dir, langPackGenerator.generate)] : []),
    ...(langPackDir ? [emittedFiles(() => getLangPackFiles(langPackDir, isProductionMode))] : []),
  ];

  return mergeConfig(baseConfig, {
    root: siteDir,
    publicDir: path.join(siteDir, 'public'),
    define: defineEnv(env),

    resolve: {
      alias: [{ find: /^.*\/i18n\/en\.json$/, replacement: defaultLangPackFile }],
    },

    server: {
      port,
      strictPort: true,
      host: '0.0.0.0',
      allowedHosts: true,
      headers: { 'Content-Security-Policy': csp, ...CORS_HEADERS },
    },

    optimizeDeps: {
      entries: ['index.html'],
    },

    build: {
      rolldownOptions: {
        input: { main: path.join(siteDir, 'index.html') },
      },
    },

    plugins,
  } satisfies UserConfig);
}
