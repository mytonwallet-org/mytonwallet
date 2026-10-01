import browserslist from 'browserslist';
import path from 'path';
import type { Plugin, UserConfig } from 'vite';
import { transformWithOxc } from 'vite';

import { disabledImports } from './disabledImports';
import { excludeModules } from './excludeModules';
import { vendoredModules } from './vendoredModules';

export const ROOT_DIR = path.resolve(__dirname, '..');
const LIB_DIR = path.join(ROOT_DIR, 'src/lib');

// Browserslist names of the engines that Oxc can compile for, mapped to Oxc's names. Browsers missing here,
// such as Opera Mobile, have their own version numbers and are covered by the Chromium entries.
const OXC_ENGINES: Record<string, string> = {
  chrome: 'chrome',
  and_chr: 'chrome',
  edge: 'edge',
  firefox: 'firefox',
  and_ff: 'firefox',
  safari: 'safari',
  ios_saf: 'ios',
  opera: 'opera',
  samsung: 'samsung',
};

// Vite does not read `.browserslistrc`, so the targets are derived from it here. Autoprefixer reads the same
// file, which keeps JS syntax lowering and CSS prefixes in line with one list of browsers.
const BROWSER_TARGETS = getBrowserTargets();

/**
 * Dependencies such as `@ton/core` and `bip39` use `Buffer` and `process` without importing them. Each
 * module that does gets its own import instead of a global, so pages that host the extension's page
 * script never see a `window.process` of ours.
 */
const NODE_GLOBALS: Record<string, string | [string, string]> = {
  Buffer: ['buffer', 'Buffer'],
  process: 'process/browser',
};

// Code written for Node reads `global`, which is `globalThis` in a browser
const GLOBAL_DEFINE = { global: 'globalThis' };

// Non-English BIP39 word lists are loaded by `bip39` inside `try` and are never used by the app
const EXCLUDED_MODULES = /\/wordlists\/(?!english).*\.json$/;

interface BaseConfigOptions {
  mode: string;
  isProduction: boolean;
  shouldMinify: boolean;
  sourcemap: boolean | 'inline' | 'hidden';
  outDir: string;
  banner?: string;
  // Readable CSS module class names used outside production
  devCssNames?: string;
  extraWorkerPlugins?: () => Plugin[];
}

/**
 * Settings every build shares: module resolution, CSS modules, asset handling, output naming and the
 * `Buffer`/`process` injection.
 *
 * Output stays flat with `name.hash.ext` file names. `deploy/copy_to_dist.sh` deletes `assets/`, the
 * immutable caching rule in `_headers` matches `/*.*.*`, and the stack trace resolver expects a map
 * next to each script.
 */
export function createBaseConfig({
  mode, isProduction, shouldMinify, sourcemap, outDir, banner,
  // The hash is there because same-named modules collide otherwise
  devCssNames = '[name]__[local]__[hash:base64:5]',
  extraWorkerPlugins,
}: BaseConfigOptions): UserConfig {
  const output = {
    entryFileNames: '[name].[hash].js',
    chunkFileNames: '[name].[hash].js',
    assetFileNames: '[name].[hash][extname]',
    banner,
    // A minified build drops the license notices of bundled libraries unless told to keep them. They go to the
    // end of each file, so the notices ship with the code they cover.
    ...(shouldMinify && {
      comments: { legal: true },
      minify: { compress: true, mangle: true, codegen: { legalComments: 'eof' as const } },
    }),
  };

  return {
    mode,
    base: './',
    appType: 'mpa',
    assetsInclude: ['**/*.tgs'],

    define: GLOBAL_DEFINE,

    css: {
      modules: {
        // `camelCase` keeps the original names too, which dynamic `styles[`key-${name}`]` lookups rely on
        localsConvention: 'camelCase',
        generateScopedName: isProduction ? '[hash:base64:8]' : devCssNames,
      },
      // Compressed Sass output is the only CSS minification. A CSS minifier would change more than
      // whitespace: Vite's own lowers selectors such as `:dir(rtl)` to `:lang()` lists, which match differently.
      preprocessorOptions: {
        scss: {
          style: mode === 'production' ? 'compressed' : 'expanded',
        },
      },
    },

    oxc: {
      jsx: { runtime: 'classic', pragma: 'React.createElement', pragmaFrag: 'React.Fragment' },
    },

    server: {
      // The dev server answers `/@fs/<path>` for every file it is allowed to read, to anyone who can reach it:
      // its host is open to the network, and the sites allow any origin. So it may read only what the pages
      // load: the sources, their dependencies and `package.json`, which provides the app version.
      fs: {
        allow: [
          path.join(ROOT_DIR, 'src'),
          path.join(ROOT_DIR, 'node_modules'),
          path.join(ROOT_DIR, 'package.json'),
        ],
      },
    },

    optimizeDeps: {
      rolldownOptions: {
        plugins: [excludeModules(EXCLUDED_MODULES)],
        // The dependency optimizer ignores the top-level `define`
        transform: { define: GLOBAL_DEFINE, inject: NODE_GLOBALS },
      },
    },

    build: {
      outDir,
      emptyOutDir: true,
      // `deploy/copy_to_dist.sh` copies `public/` and drops the files a flavor must not ship
      copyPublicDir: false,
      assetsDir: '',
      // Assets load through CSP-restricted channels that do not accept `data:` URLs
      assetsInlineLimit: 0,
      target: BROWSER_TARGETS,
      minify: shouldMinify,
      cssMinify: false,
      sourcemap,
      reportCompressedSize: false,
      chunkSizeWarningLimit: Infinity,
      rolldownOptions: {
        transform: { inject: NODE_GLOBALS },
        treeshake: { moduleSideEffects: getModuleSideEffects },
        output,
      },
    },

    worker: {
      // A module worker loads its lazy chunks on demand, while a classic one would have them all bundled in
      format: 'es',
      plugins: () => [
        { ...excludeModules(EXCLUDED_MODULES), enforce: 'pre' },
        disabledImports(ROOT_DIR),
        vendoredModules(LIB_DIR),
        ...(extraWorkerPlugins?.() ?? []),
      ],
      rolldownOptions: {
        transform: { inject: NODE_GLOBALS },
        output,
      },
    },

    plugins: [
      { ...excludeModules(EXCLUDED_MODULES), enforce: 'pre' },
      disabledImports(ROOT_DIR),
      vendoredModules(LIB_DIR),
      ...nodeGlobalsInDev(),
    ],
  };
}

// The oldest version of each engine that `.browserslistrc` selects, as Oxc targets such as `chrome87`
function getBrowserTargets() {
  const oldestVersions = new Map<string, string>();
  for (const browser of browserslist(undefined, { path: ROOT_DIR })) {
    const [name, versions] = browser.split(' ');
    const engine = OXC_ENGINES[name];
    // A range such as `ios_saf 18.5-18.7` starts with its oldest version
    const version = versions.split('-')[0];
    const oldestVersion = oldestVersions.get(engine);
    if (engine && (!oldestVersion || compareVersions(version, oldestVersion) < 0)) {
      oldestVersions.set(engine, version);
    }
  }

  return [...oldestVersions].map(([engine, version]) => `${engine}${version}`);
}

function compareVersions(a: string, b: string) {
  const [aMajor, aMinor = 0] = a.split('.').map(Number);
  const [bMajor, bMinor = 0] = b.split('.').map(Number);
  return aMajor - bMajor || aMinor - bMinor;
}

/**
 * Modules known to be free of side effects that tree-shaking cannot prove so, which lets a build that never
 * uses them, such as the Air SDK, drop them. Other modules keep the default detection.
 *
 * On import, Dexie only registers itself in a global to detect two copies in one app. The vendored CommonJS
 * libraries only define their exports, but look side-effectful after `vendoredModules` wraps them.
 */
function getModuleSideEffects(id: string) {
  return /[\\/]node_modules[\\/]dexie[\\/]|[\\/]src[\\/]lib[\\/]((aes-js|noble-ed25519)[\\/]|quantize\.js$)/.test(id)
    ? false
    : undefined;
}

/**
 * The dev server transforms each source file on its own, outside Rolldown, so the injection has to run
 * as a plugin there. Vite does not replace `define` keys in dev code: it assigns them to `globalThis` at
 * runtime, where the injected `process` would hide them. So the keys are replaced first, as in a build,
 * and in a separate pass, because Oxc injects before it defines.
 */
function nodeGlobalsInDev(): Plugin[] {
  const idFilter = { include: /\.[cm]?[jt]sx?(\?|$)/, exclude: /\/node_modules\// };
  let define: Record<string, string>;

  return [{
    name: 'mtw:define-in-dev',
    apply: 'serve',
    enforce: 'post',
    configResolved(config) {
      define = config.define ?? {};
    },
    transform: {
      filter: { id: idFilter, code: /\b(process\.env|global)\b/ },
      async handler(code, id) {
        const { code: transformedCode, map } = await transformWithOxc(code, id, {
          lang: 'js',
          define,
          sourcemap: true,
        });
        return { code: transformedCode, map };
      },
    },
  }, {
    name: 'mtw:inject-node-globals',
    apply: 'serve',
    enforce: 'post',
    transform: {
      filter: { id: idFilter, code: /\b(Buffer|process)\b/ },
      async handler(code, id) {
        const { code: transformedCode, map } = await transformWithOxc(code, id, {
          lang: 'js',
          inject: NODE_GLOBALS,
          sourcemap: true,
        });
        return { code: transformedCode, map };
      },
    },
  }];
}
