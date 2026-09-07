import type { ApiEVMWallet, EVMChain } from '../../../types';

import { getChainConfig } from '../../../../util/chain';
import { fetchStoredAccount } from '../../../common/accounts';

/**
 * The wallet an account uses on the given EVM chain.
 *
 * All EVM chains of an account share one wallet, but the account stores an entry per chain it knew
 * when it was created, so a chain added to the app later has no entry in an older account. Such a
 * chain is served by the wallet of its standard chain.
 */
export async function fetchEvmWallet(accountId: string, chain: EVMChain): Promise<ApiEVMWallet> {
  const account = await fetchStoredAccount(accountId);
  const standardChain = getChainConfig(chain).chainStandard as EVMChain | undefined;
  const wallet = account.byChain[chain] ?? (standardChain && account.byChain[standardChain]);

  if (!wallet) {
    throw new Error(`${chain} wallet missing in account ${accountId}`);
  }

  return wallet;
}
