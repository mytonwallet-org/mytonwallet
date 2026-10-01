import type { HtmlTagDescriptor, Plugin } from 'vite';

/**
 * Adds `<link rel="preload">` for the emitted images that match `patterns`, so pictures shown right after
 * startup do not pop in late. Only the production build knows the final file names, so dev skips it.
 */
export function preloadAssets(patterns: RegExp[]): Plugin {
  return {
    name: 'mtw:preload-assets',
    apply: 'build',

    transformIndexHtml: {
      order: 'post',
      handler(_, { bundle }) {
        return Object.values(bundle ?? {})
          .filter(({ type, fileName }) => type === 'asset' && patterns.some((pattern) => pattern.test(fileName)))
          .map(({ fileName }) => fileName)
          .sort()
          .map((fileName): HtmlTagDescriptor => ({
            tag: 'link',
            attrs: { href: fileName, rel: 'preload', as: /\.(png|svg)$/.test(fileName) ? 'image' : 'script' },
            injectTo: 'head',
          }));
      },
    },
  };
}
