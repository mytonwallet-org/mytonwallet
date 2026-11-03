import type { ApiPerpsOperation } from '../../api/types';
import type { GlobalState } from '../types';

import { INITIAL_STATE } from '../initialState';
import { updatePerpsOperation } from './perps';

const ACCOUNT_ID = '0-mainnet';

function buildOperation(id: string, state: ApiPerpsOperation['state']): ApiPerpsOperation {
  return { id, accountId: ACCOUNT_ID, assetId: 'hyperliquid:hl:BTC', kind: 'reduce',
    state, stage: 'withdrawal', createdAt: Number(id) || 0 };
}

it('retains unresolved operations when pruning resolved history and isolates wallet state', () => {
  const states: ApiPerpsOperation['state'][] = ['running', 'partial', 'unknown'];
  const unresolved = states.map((state) => buildOperation(state, state));
  const completed = Array.from({ length: 25 }, (_, index) => buildOperation(String(index + 1), 'completed'));
  const global: GlobalState = {
    ...INITIAL_STATE,
    accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: {} } } },
    byAccountId: {
      [ACCOUNT_ID]: {
        perpsOperations: Object.fromEntries([...unresolved, ...completed].map((value) => [value.id, value])),
      },
      other: { savedAddresses: [] },
    },
  };

  const updated = updatePerpsOperation(global, buildOperation('26', 'completed'));
  const retained = updated.byAccountId[ACCOUNT_ID].perpsOperations!;
  expect(Object.keys(retained)).toHaveLength(23);
  for (const operation of unresolved) expect(retained[operation.id]).toEqual(operation);
  expect(retained['1']).toBeUndefined();
  expect(updated.byAccountId.other).toBe(global.byAccountId.other);
  expect(updatePerpsOperation(updated, { ...unresolved[0], accountId: 'removed' })).toBe(updated);
});
