import type { Log } from '../../util/logs';
import type { Account } from '../types';

import {
  APP_COMMIT_HASH, APP_ENV, APP_VERSION, IS_EXTENSION, IS_GRAM_WALLET, IS_TELEGRAM_APP,
} from '../../config';
import { copyTextToClipboard } from '../../util/clipboard';
import { getBuildPlatform, getFlagsValue } from '../../util/getBuildPlatform';
import { getPlatform } from '../../util/getPlatform';
import { getIndexedDbLossEvidence } from '../../util/indexedDbLoss';
import { mapValues } from '../../util/iteratees';
import { getLogs } from '../../util/logs';
import { withTimeout } from '../../util/schedulers';
import { shareFile } from '../../util/share';
import { IS_IOS } from '../../util/windowEnvironment';
import { callApi } from '../../api';

interface LogsContext {
  currentAccountId?: string;
  accountsById?: Record<string, Account>;
}

// The worker answers only after the SDK has started, and the storage failure this export reports can stop that start
const API_LOGS_TIMEOUT = 5000;

// iOS allows downloading files even in TMA, however, in other platforms,
// downloading files from `blob:https://` schemes is limited by Telegram itself.
// Also, file downloading is limited in extensions.
export const CAN_DOWNLOAD_LOGS = IS_IOS || !(IS_EXTENSION || IS_TELEGRAM_APP);
export const EXPORT_LOGS_TITLE = CAN_DOWNLOAD_LOGS ? 'Download Logs' : 'Copy Logs';

/**
 * Resolves to `true` where the logs go to the clipboard and `false` where they are saved as a file. The share sheet
 * opens only within the click's user activation, so a caller that can collect `logs` before the click passes them in.
 */
export async function exportLogs(context: LogsContext, logs = collectLogs(context)) {
  const logsString = await logs;

  if (!CAN_DOWNLOAD_LOGS) {
    await copyTextToClipboard(logsString);
    return true;
  }

  const brandPrefix = IS_GRAM_WALLET ? 'gramwallet' : 'mytonwallet';
  await shareFile(`${brandPrefix}_logs_${new Date().toISOString()}.json`, logsString, 'application/json');

  return false;
}

export async function collectLogs({
  currentAccountId,
  accountsById,
}: LogsContext) {
  const accountsInfo = accountsById && mapValues(accountsById, (account) => ({
    type: account.type,
    addressByChain: mapValues(account.byChain, (accountChain) => accountChain.address),
  }));

  const mainLogs = getLogs();
  let isApiLogsTimedOut = false;
  const apiLogs = await withTimeout(callApi('getLogs'), API_LOGS_TIMEOUT, undefined, () => {
    isApiLogsTimedOut = true;
  }) ?? [];

  const time = new Date();
  const timezoneOffset = -time.getTimezoneOffset();

  return JSON.stringify(
    {
      time,
      timezone: `UTC${timezoneOffset < 0 ? '-' : '+'}${Math.abs(timezoneOffset) / 60}`,
      environment: APP_ENV,
      version: APP_VERSION,
      commit: APP_COMMIT_HASH,
      platform: getPlatform(),
      navigatorPlatform: navigator.platform,
      userAgent: navigator.userAgent,
      build: getBuildPlatform(),
      flags: getFlagsValue(),
      currentAccountId,
      accountsInfo,
      // The boot that found the storage missing logs it once, and the bounded log buffer drops that entry in time
      storageLossEvidence: getIndexedDbLossEvidence(),
      apiLogsTimedOut: isApiLogsTimedOut || undefined,
      logs: [
        ...mainLogs.map((log: Log) => ({ ...log, context: 'main' })),
        ...apiLogs.map((log: Log) => ({ ...log, context: 'api' })),
      ]
        .sort((a, b) => a.time - b.time)
        .map((log) => ({ ...log, time: new Date(log.time).toISOString() })),
    },
    undefined,
    2,
  );
}
