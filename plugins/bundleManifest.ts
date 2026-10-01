import path from 'path';
import type { Plugin, Rolldown } from 'vite';

import { ROOT_DIR } from './viteBase';

/**
 * Writes `bundle-manifest.json` next to the bundle: every chunk with its imports and the source modules it
 * ships, so checks such as `dev/checkAgentV2BundleBoundary.mjs` can tell what loads upfront.
 *
 * Paths are relative to the repository root. A module that renders no code, such as a file of types, is left
 * out, since it ships nothing.
 */
export function bundleManifest(): Plugin {
  return {
    name: 'mtw:bundle-manifest',
    apply: 'build',

    generateBundle(_, bundle) {
      const chunks = Object.values(bundle)
        .filter((item): item is Rolldown.OutputChunk => item.type === 'chunk')
        .map((chunk) => ({
          fileName: chunk.fileName,
          name: chunk.name,
          isEntry: chunk.isEntry,
          isDynamicEntry: chunk.isDynamicEntry,
          facadeModuleId: chunk.facadeModuleId ? toRelativePath(chunk.facadeModuleId) : undefined,
          imports: chunk.imports,
          dynamicImports: chunk.dynamicImports,
          modules: chunk.moduleIds
            .filter((moduleId) => chunk.modules[moduleId]?.renderedLength)
            .map(toRelativePath),
        }));

      this.emitFile({
        type: 'asset',
        fileName: 'bundle-manifest.json',
        source: `${JSON.stringify({ chunks }, undefined, 2)}\n`,
      });
    },
  };
}

function toRelativePath(moduleId: string) {
  const filePath = moduleId.replace(/^\0/, '').split('?')[0];
  return path.isAbsolute(filePath) ? path.relative(ROOT_DIR, filePath).split(path.sep).join('/') : filePath;
}
