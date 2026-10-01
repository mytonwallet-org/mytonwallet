import { execFile } from 'child_process';
import path from 'path';
import type { Logger, Plugin } from 'vite';

/**
 * Regenerates the icon font in dev when an icon source changes. The generated font and CSS are committed,
 * so builds use them as they are.
 *
 * A burst of changes, such as a branch switch, triggers one more run after the current one finishes
 * instead of a run per file.
 */
export function iconFont(iconsDir: string): Plugin {
  let isRunning = false;
  let isRunPending = false;

  function build(logger: Logger) {
    if (isRunning) {
      isRunPending = true;
      return;
    }

    isRunning = true;
    execFile('npm', ['run', 'build:icons'], (err, _, stderr) => {
      if (err) {
        logger.error(`Icon font generation failed: ${stderr}`);
      }

      isRunning = false;
      if (isRunPending) {
        isRunPending = false;
        build(logger);
      }
    });
  }

  return {
    name: 'mtw:icon-font',
    apply: 'serve',

    configureServer(server) {
      const handleChange = (changedPath: string) => {
        if (path.dirname(changedPath) === iconsDir && changedPath.endsWith('.svg')) {
          build(server.config.logger);
        }
      };

      server.watcher.on('add', handleChange);
      server.watcher.on('change', handleChange);
      server.watcher.on('unlink', handleChange);
    },
  };
}
