import '../../../../global/actions/api/portfolio';
import '../../../../global/actions/api/wallet';
import '../../../../global/actions/ui/misc';

import React from '../../../../lib/teact/teact';
import TeactDOM from '../../../../lib/teact/teact-dom';
import { getActions, getGlobal, setGlobal } from '../../../../global';

import type { ApiPortfolioHistoryResponse } from '../../../../api/types';

import { ANIMATION_LEVEL_MIN, DEFAULT_STAKING_STATE, MAIN_ACCOUNT_ID, TONCOIN } from '../../../../config';
import { INITIAL_STATE } from '../../../../global/initialState';
import { cloneDeep } from '../../../../util/iteratees';
import { pause } from '../../../../util/schedulers';
import { callApi } from '../../../../api';

import Card from './Card';

jest.mock('../../../../api', () => ({ callApi: jest.fn() }));

let root: HTMLDivElement;

beforeAll(() => {
  Object.defineProperty(document, 'fonts', { configurable: true, value: { ready: Promise.resolve() } });
});

afterAll(() => {
  Reflect.deleteProperty(document, 'fonts');
});

beforeEach(() => {
  jest.mocked(callApi).mockReset();
  root = document.createElement('div');
  document.body.appendChild(root);
  const global = cloneDeep(INITIAL_STATE);
  setGlobal({
    ...global,
    currentAccountId: MAIN_ACCOUNT_ID,
    accounts: {
      byId: {
        [MAIN_ACCOUNT_ID]: {
          title: 'Test Account',
          type: 'mnemonic',
          byChain: { ton: { address: 'UQTestAddress' } },
        },
      },
    },
    byAccountId: {
      [MAIN_ACCOUNT_ID]: { balances: { bySlug: { [TONCOIN.slug]: 10_000_000_000n } } },
    },
    tokenInfo: {
      bySlug: { [TONCOIN.slug]: { ...TONCOIN, priceUsd: 11, percentChange24h: 10 } },
    },
    settings: { ...global.settings, animationLevel: ANIMATION_LEVEL_MIN, baseCurrency: 'USD' },
    portfolio: {
      activeRange: '3M',
      pnlChangeByAccountId: {
        [MAIN_ACCOUNT_ID]: { range: '3M', baseCurrency: 'USD', amount: 999, percent: 99 },
      },
    },
  });
});

afterEach(() => {
  getActions().closePortfolio();
  TeactDOM.render(undefined, root);
  root.remove();
});

async function renderCard() {
  TeactDOM.render(<Card accountId={MAIN_ACCOUNT_ID} isActive onYieldClick={() => {}} />, root);
  await pause(50);
}

function getChangeButton() {
  return root.querySelector('.icon-chevron-right')!.closest<HTMLElement>('[role="button"]')!;
}

it('uses local 24-hour prices instead of persisted Portfolio returns', async () => {
  await renderCard();
  expect(getChangeButton().textContent).toContain('10%');
  expect(getChangeButton().textContent).toContain('$10');
  expect(getChangeButton().textContent).not.toContain('999');
});

it('does not fetch Portfolio on mount or after a balance tick', async () => {
  await renderCard();
  expect(callApi).not.toHaveBeenCalled();

  const global = getGlobal();
  setGlobal({
    ...global,
    byAccountId: {
      ...global.byAccountId,
      [MAIN_ACCOUNT_ID]: { balances: { bySlug: { [TONCOIN.slug]: 20_000_000_000n } } },
    },
  });
  await pause(50);
  expect(getChangeButton().textContent).toContain('$20');
  expect(callApi).not.toHaveBeenCalled();
});

it('includes staking-only holdings in the local 24-hour change', async () => {
  const global = getGlobal();
  setGlobal({
    ...global,
    byAccountId: {
      [MAIN_ACCOUNT_ID]: {
        balances: { bySlug: { [TONCOIN.slug]: 0n } },
        staking: { stateById: { liquid: { ...DEFAULT_STAKING_STATE, balance: 10_000_000_000n } } },
      },
    },
  });
  await renderCard();
  expect(getChangeButton().textContent).toContain('10%');
  expect(getChangeButton().textContent).toContain('$10');
  expect(callApi).not.toHaveBeenCalled();
});

it('keeps Portfolio navigation and its own history requests available', async () => {
  await renderCard();
  jest.mocked(callApi).mockClear();
  const history: ApiPortfolioHistoryResponse = {
    status: 'ok', base: 'USD', density: '1h', points: [[1000, 100], [2000, 110]],
  };
  jest.mocked(callApi)
    .mockResolvedValueOnce(history)
    .mockResolvedValueOnce(history)
    .mockResolvedValueOnce(history)
    .mockResolvedValueOnce({ status: 'ok', base: 'USD', amount: 55, percent: 50, startTs: 1000, endTs: 2000 });
  getChangeButton().click();
  await pause(50);
  expect(getGlobal().isPortfolioOpen).toBe(true);

  getActions().loadPortfolioHistory({ range: '1D' });
  await pause(50);
  expect(jest.mocked(callApi).mock.calls.map(([method]) => method)).toEqual([
    'fetchPortfolioNetWorthHistory',
    'fetchPortfolioPnlCumulativeHistory',
    'fetchPortfolioPnlHistory',
    'fetchPortfolioPnlChange',
  ]);
  expect(getGlobal().portfolio?.historyByAccountId?.[MAIN_ACCOUNT_ID]?.USD?.['1D']).toMatchObject({
    netWorth: history,
    pnlCumulative: history,
    pnl: history,
    pnlChange: { amount: 55, percent: 50 },
  });
  expect(getGlobal().portfolio?.error).toBeUndefined();
  expect(getChangeButton().textContent).toContain('10%');
  expect(getChangeButton().textContent).toContain('$10');
});
