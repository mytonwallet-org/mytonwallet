import fs from 'fs';
import path from 'path';
import type { Plugin } from 'vite';

import type { EmittedFiles } from './emittedFiles';

import { convertI18nYamlToJson } from '../dev/locales/convertI18nYamlToJson';

/**
 * Keeps a generated lang pack in sync with its YAML sources: `generate` runs before the first module is
 * resolved, and again on every YAML change in `sourceDir` in dev.
 */
export function defaultLangPack(sourceDir: string, generate: NoneToVoidFunction): Plugin {
  return {
    name: 'mtw:default-lang-pack',

    buildStart() {
      generate();
    },

    configureServer(server) {
      server.watcher.add(sourceDir);
      server.watcher.on('change', (changedPath) => {
        if (path.dirname(changedPath) === sourceDir && changedPath.endsWith('.yaml')) {
          generate();
        }
      });
    },
  };
}

// A production build fails on invalid YAML. Dev keeps the last valid JSON so a typo does not stop the server.
export function writeJsonLangPack(yamlPath: string, jsonPath: string, isProductionMode: boolean) {
  const json = convertI18nYamlToJson(fs.readFileSync(yamlPath, 'utf8'), isProductionMode);
  if (json) {
    fs.writeFileSync(jsonPath, json, 'utf-8');
  }
}

// Every YAML lang pack in `dir` as `i18n/<langCode>.json`, which the app fetches when the language changes
export function getLangPackFiles(dir: string, isProductionMode: boolean): EmittedFiles {
  return Object.fromEntries(fs.readdirSync(dir)
    .filter((fileName) => fileName.endsWith('.yaml'))
    .map((fileName) => [
      `i18n/${path.basename(fileName, '.yaml')}.json`,
      () => convertI18nYamlToJson(fs.readFileSync(path.join(dir, fileName), 'utf8'), isProductionMode)!,
    ]));
}
