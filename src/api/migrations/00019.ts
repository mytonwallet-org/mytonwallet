import type { ApiAccountAny, ApiTonWallet, ApiTronWallet } from '../types';

import { mapValues, omitUndefined } from '../../util/iteratees';
import { storage } from '../storages';

type OldAccount = Omit<ApiAccountAny, 'byChain'> & {
  ton?: ApiTonWallet & { type?: 'ton' };
  tron?: ApiTronWallet & { type?: 'tron' };
};

export async function start() {
  const oldAccounts: Record<string, OldAccount> | undefined = await storage.getItem('accounts');
  if (!oldAccounts) {
    return;
  }

  const newAccounts = mapValues(oldAccounts, (oldAccount) => {
    const { ton, tron, ...account } = oldAccount;
    if (ton) delete ton.type;
    if (tron) delete tron.type;
    return {
      ...account,
      byChain: omitUndefined({ ton, tron }),
    };
  });

  await storage.setItem('accounts' as any, newAccounts);
}
