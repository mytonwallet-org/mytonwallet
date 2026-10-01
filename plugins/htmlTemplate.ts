import type { Plugin } from 'vite';

/**
 * Fills `%NAME%` placeholders in `index.html`. A value may carry whole tags, which is how optional
 * elements such as the web manifest link are switched off for a build.
 *
 * Runs before Vite parses the HTML, so the substituted tags get the same treatment as hand-written ones.
 */
export function htmlTemplate(variables: Record<string, string>): Plugin {
  return {
    name: 'mtw:html-template',
    transformIndexHtml: {
      order: 'pre',
      handler(html) {
        return html.replace(/%([A-Z_]+)%/g, (placeholder, name: string) => {
          if (!(name in variables)) {
            throw new Error(`Unknown HTML template variable ${placeholder}`);
          }
          return variables[name];
        });
      },
    },
  };
}
