import './dev/loadEnv';

import path from 'path';
import type { Plugin, UserConfig } from 'vite';
import { build, defineConfig } from 'vite';

import { defineEnv } from './plugins/env';
import { ROOT_DIR } from './plugins/viteBase';
import { APP_ENV, BASE_URL } from './src/config';

const OUT_DIR = path.resolve(ROOT_DIR, 'dist');
const MAIN_ENTRY = path.resolve(ROOT_DIR, 'src/electron/main.ts');
const PRELOAD_ENTRY = path.resolve(ROOT_DIR, 'src/electron/preload.ts');

/**
 * The Electron main process and its preload script, as CommonJS for Node. They are written into the
 * renderer's `dist`, which electron-builder packages without `node_modules`, so every dependency except
 * `electron` is bundled.
 *
 * The preload script is a separate build: a sandboxed preload can require only `electron`, so it must not
 * share a chunk with the main process.
 */
export default defineConfig(() => ({
  ...createNodeConfig('electron', MAIN_ENTRY),
  plugins: [buildPreload()],
}));

function createNodeConfig(name: string, entry: string): UserConfig {
  return {
    root: ROOT_DIR,
    publicDir: false,
    mode: 'production',
    define: {
      ...defineEnv({
        APP_ENV,
        BASE_URL,
        IS_PREVIEW: 'false',
        IS_HEADLESS: '',
      }),
      'process.env.NODE_ENV': JSON.stringify('production'),
    },
    ssr: {
      noExternal: true,
      external: ['electron'],
    },
    build: {
      ssr: entry,
      outDir: OUT_DIR,
      // The renderer build owns `dist`
      emptyOutDir: false,
      target: 'node22',
      minify: true,
      sourcemap: false,
      reportCompressedSize: false,
      rolldownOptions: {
        output: {
          format: 'cjs',
          entryFileNames: `${name}.js`,
          codeSplitting: false,
          // The minifier drops license notices of bundled libraries unless told to keep them
          comments: { legal: true },
          minify: { compress: true, mangle: true, codegen: { legalComments: 'eof' } },
        },
      },
    },
  };
}

// In watch mode the preload build starts once and keeps watching on its own
function buildPreload(): Plugin {
  let isStarted = false;

  return {
    name: 'mtw:electron-preload',
    apply: 'build',

    async closeBundle() {
      if (isStarted) return;
      isStarted = true;

      const config = createNodeConfig('preload', PRELOAD_ENTRY);
      await build({
        ...config,
        configFile: false,
        logLevel: 'warn',
        build: { ...config.build, ...(this.meta.watchMode && { watch: {} }) },
      });
    },
  };
}
