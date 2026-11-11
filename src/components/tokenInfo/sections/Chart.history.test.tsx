import '../../../util/bigintPatch';
import '../../../global/actions/api/tokens';

import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';
import { setGlobal } from '../../../global';

import type { UserToken } from '../../../global/types';

import { TONCOIN } from '../../../config';
import { INITIAL_STATE } from '../../../global/initialState';
import { pause } from '../../../util/schedulers';
import { callApi } from '../../../api';

import Chart from './Chart';

// Native worker and HTTP are the external boundaries; Chart and legacy actions run unchanged.
jest.mock('../../../api', () => ({ callApi: jest.fn() }));

it('renders the token chart when the web response has no backfill', async () => {
  const root = document.createElement('div');
  document.body.appendChild(root);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = jest.fn(() => Promise.resolve({
    ok: true, status: 200, headers: { get: () => undefined }, json: () => Promise.resolve({ points: [] }),
  })) as any;
  jest.mocked(callApi).mockResolvedValue([[1704067200, 200], [1704153600, 300]]);
  try {
    setGlobal({ ...INITIAL_STATE,
      settings: { ...INITIAL_STATE.settings, langCode: 'en', baseCurrency: 'USD' },
      currentAccountId: '0-mainnet',
      accounts: { byId: { '0-mainnet': { type: 'mnemonic', byChain: {} } } },
      byAccountId: { '0-mainnet': { currentTokenPeriod: 'ALL' } },
      tokenPriceHistory: { bySlug: { [TONCOIN.slug]: { ALL: [[1704067200, 200], [1704153600, 300]] } },
        restoredBySlug: {} },
    });
    TeactDOM.render(
      <Chart
        token={TONCOIN as UserToken}
        chartMode="price"
        isActive
        onChartModeChange={() => {}}
        onBalanceChangeUpdate={() => {}}
      />, root);
    await pause(100);
    expect(root.textContent).toContain('50%');
  } finally {
    TeactDOM.render(undefined, root);
    root.remove();
    globalThis.fetch = originalFetch;
  }
});
