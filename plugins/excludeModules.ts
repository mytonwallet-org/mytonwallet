import type { Plugin } from 'vite';

const EXCLUDED_ID_PREFIX = '\0mtw-excluded:';

/**
 * Replaces every import matching `pattern` with a module that throws when evaluated.
 *
 * Meant for optional files a dependency loads inside `try`, such as the non-English BIP39 word lists: the
 * `catch` swallows the error, so the dependency behaves as if the file had never been shipped.
 *
 * The returned plugin works both in Vite and in the dependency optimizer, which runs Rolldown directly.
 */
export function excludeModules(pattern: RegExp) {
  return {
    name: 'mtw:exclude-modules',

    // The `.js` suffix keeps loaders keyed on the original extension, such as the JSON one, off the stub
    resolveId(source: string) {
      return pattern.test(source) ? `${EXCLUDED_ID_PREFIX}${source}.js` : undefined;
    },

    load(id: string) {
      if (!id.startsWith(EXCLUDED_ID_PREFIX)) return undefined;
      const message = `${id.slice(EXCLUDED_ID_PREFIX.length, -'.js'.length)} is excluded from the bundle`;
      return `throw new Error(${JSON.stringify(message)});`;
    },
  } satisfies Plugin;
}
