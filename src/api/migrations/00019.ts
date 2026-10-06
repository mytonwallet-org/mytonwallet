import type { ApiAccountAny, ApiTonWallet, ApiTronWallet } from '../types';

import { mapValues, omitUndefined } from '../../util/iteratees';
import { storage } from '../storages';

type OldAccount = Omit<ApiAccountAny, 'byChain'> & {
  ton?: ApiTonWallet & { type?: 'ton' };
  tron?: ApiTronWallet & { type?: 'tron' };
  byChain?: ApiAccountAny['byChain'];
};

export async function start() {
  const oldAccounts: Record<string, OldAccount> | undefined = await storage.getItem('accounts');
  if (!oldAccounts) {
    return;
  }

  const newAccounts = mapValues(oldAccounts, (oldAccount) => {
    const {
      ton: oldTon, tron: oldTron, byChain, ...account
    } = oldAccount;
    const { type: _tonType, ...ton } = oldTon ?? {} as NonNullable<OldAccount['ton']>;
    const { type: _tronType, ...tron } = oldTron ?? {} as NonNullable<OldAccount['tron']>;

    return {
      ...account,
      byChain: {
        ...omitUndefined({
          ton: oldTon ? ton : undefined,
          tron: oldTron ? tron : undefined,
        }),
        ...byChain,
      },
    };
  });

  await storage.setItem('accounts' as any, newAccounts);
}
