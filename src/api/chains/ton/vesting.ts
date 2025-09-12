import type { ApiVestingInfo } from '../../types';

import { parseAccountId } from '../../../util/account';
import { fetchStoredWallet } from '../../common/accounts';
import { callBackendGet } from '../../common/backend';

export async function fetchVestings(accountId: string) {
  const { network } = parseAccountId(accountId);
  const isTestnet = network === 'testnet';
  const { address } = await fetchStoredWallet(accountId, 'ton');

  return callBackendGet<ApiVestingInfo[]>(`/vesting/${address}`, { isTestnet });
}
