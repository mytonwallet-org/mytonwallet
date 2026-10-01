import path from 'path';
import type { Plugin } from 'vite';

export type EmittedFiles = Record<string, () => string | Uint8Array>;

const CONTENT_TYPES: Record<string, string> = {
  '.json': 'application/json',
  '.txt': 'text/plain; charset=utf-8',
};

/**
 * Serves files generated from the sources rather than imported by the code: translations, the extension
 * manifest, hosting headers and build identity files.
 *
 * A build writes them next to the bundle. The dev server answers the same paths from memory, so the app
 * fetches translations and `version.txt` the same way in both modes.
 *
 * `getFiles` is called on every use, so each build and each dev request sees the current sources.
 */
export function emittedFiles(getFiles: () => EmittedFiles): Plugin {
  return {
    name: 'mtw:emitted-files',

    generateBundle() {
      for (const [fileName, getContent] of Object.entries(getFiles())) {
        this.emitFile({ type: 'asset', fileName, source: getContent() });
      }
    },

    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = new URL(req.url!, 'http://localhost');
        const fileName = decodeURIComponent(url.pathname).slice(1);
        const getContent = getFiles()[fileName];
        // A module import of the same file, such as the bundled `i18n/en.json`, is Vite's to transform
        if (!getContent || url.searchParams.has('import')) {
          next();
          return;
        }

        res.setHeader('Content-Type', CONTENT_TYPES[path.extname(fileName)] ?? 'application/octet-stream');
        res.end(getContent());
      });
    },
  };
}
