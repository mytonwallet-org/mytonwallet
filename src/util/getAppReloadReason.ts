import type { AppReloadReason } from '../global/types';

const COMMIT_LINE_REGEX = /^commit=(\S+)$/m;

/**
 * Decides, from the served `build.txt`, why a failed lazy chunk calls for a reload. Without build info the host is not
 * serving the app right now, so a reload could land on an error page and nothing is suggested.
 */
export default function getAppReloadReason(buildInfo: string, runningCommit: string): AppReloadReason | undefined {
  const servedCommit = buildInfo.match(COMMIT_LINE_REGEX)?.[1];
  if (!servedCommit) return undefined;

  // With the same build served, the chunk failed on its own. Only a reload recovers it in Chromium,
  // which keeps a failed module fetch for the lifetime of the page.
  return servedCommit === runningCommit ? 'chunkLoadFailed' : 'buildOutdated';
}
