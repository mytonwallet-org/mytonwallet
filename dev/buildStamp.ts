import { execFileSync } from 'child_process';

/**
 * Identifies the bundle a running app is actually executing.
 *
 * Everything else that would answer that question is either absent at runtime or reports the
 * native app rather than the JS inside it: the marketing version and the build number belong to
 * the wrapper, and the wrapper is replaced by an update whether or not the bundle beneath it is.
 * An installed build was found running a JS bundle six weeks older than the app around it, and
 * nothing in the app, its logs or its diagnostics export could state that - it had to be inferred
 * from a request header the newer bundle would have sent.
 *
 * Resolved once, at build time, and baked in by `defineEnv`. A tree without git, or with
 * uncommitted work, still builds: the parts that cannot be established are simply left out.
 */
export function resolveBuildStamp(): string {
  const parts = [gitDescribe(), new Date().toISOString().slice(0, 19).replace('T', ' ')];
  return parts.filter(Boolean).join(' ');
}

function gitDescribe(): string {
  try {
    const commit = execFileSync('git', ['rev-parse', '--short=9', 'HEAD'], { encoding: 'utf8' }).trim();
    const dirty = execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim().length > 0;
    return dirty ? `${commit}-dirty` : commit;
  } catch {
    // A source drop without git history is a legitimate way to build; say so rather than fail.
    return 'nogit';
  }
}
