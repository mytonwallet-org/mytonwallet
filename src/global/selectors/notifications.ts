import type { ApiNotificationAddress } from '../../api/types';
import type { Account, GlobalState } from '../types';

import { getChainConfig, getOrderedAccountChains } from '../../util/chain';
import { selectAccount } from './accounts';

// This selector is not optimized for usage with React components wrapped by withGlobal
export function selectNotificationAddressesSlow(
  global: GlobalState,
  accountIds: string[],
  maxCount: number = Infinity,
): Record<string, ApiNotificationAddress[]> {
  const result: Record<string, ApiNotificationAddress[]> = {};
  let resultCount = 0;

  for (const accountId of accountIds) {
    if (resultCount >= maxCount) {
      break;
    }

    const account = selectAccount(global, accountId);
    if (!account) {
      continue;
    }

    const accountAddresses = selectAccountNotificationAddresses(account);
    if (accountAddresses.length === 0) {
      continue;
    }

    result[accountId] = accountAddresses;
    resultCount++;
  }

  return result;
}

function selectAccountNotificationAddresses(account: Account) {
  const addresses: ApiNotificationAddress[] = [];

  // `getOrderedAccountChains` drops stored keys absent from CHAIN_CONFIG before they reach
  // `getChainConfig(...).doesSupportPushNotifications`.
  for (const chain of getOrderedAccountChains(account.byChain)) {
    // If an unsupported chain is sent to the backend, the whole request fails
    if (!getChainConfig(chain).doesSupportPushNotifications) {
      continue;
    }

    addresses.push({
      title: account.title,
      address: account.byChain[chain]!.address,
      chain,
    });
  }

  return addresses;
}
