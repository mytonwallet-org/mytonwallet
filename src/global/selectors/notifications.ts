import type { ApiNotificationAddress } from '../../api/types';
import type { GlobalState } from '../types';

import { selectAccount } from './accounts';

// This selector is not optimized for usage with React components wrapped by withGlobal
export function selectNotificationTonAddressesSlow(
  global: GlobalState,
  accountIds: string[],
  maxCount: number = Infinity,
): Record<string, ApiNotificationAddress> {
  const result: Record<string, ApiNotificationAddress> = {};
  let resultCount = 0;

  for (const accountId of accountIds) {
    if (resultCount >= maxCount) {
      break;
    }

    const account = selectAccount(global, accountId);
    const address = account?.byChain.ton?.address;

    if (address) {
      result[accountId] = {
        title: account.title,
        address,
        chain: 'ton',
      };
      resultCount += 1;
    }
  }

  return result;
}
