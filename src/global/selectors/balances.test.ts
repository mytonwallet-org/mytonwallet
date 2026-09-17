import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../../api/types';
import type { AccountSettings, GlobalState } from '../types';

import { TONCOIN } from '../../config';
import { INITIAL_STATE } from '../initialState';
import { selectMultipleAccountsBalances } from './balances';

const ACCOUNT_A = 'mainnet-0';
const ACCOUNT_B = 'mainnet-1';
const ONE_TON = 1_000_000_000n; // 1 TON, 9 decimals

const TOKEN_INFO = {
  bySlug: {
    [TONCOIN.slug]: { ...TONCOIN, priceUsd: 5, percentChange24h: 0 },
  },
} as GlobalState['tokenInfo'];

const SETTINGS: Record<string, AccountSettings> = {};
const STAKING_STATES: Record<string, ApiStakingState[] | undefined> = {};
const CURRENCY_RATES = { ...INITIAL_STATE.currencyRates, USD: '1' } as ApiCurrencyRates;
const BASE_CURRENCY: ApiBaseCurrency = 'USD';

function buildByAccountId(tonByAccount: Record<string, bigint>) {
  const byAccountId: Record<string, unknown> = {};
  for (const accountId of Object.keys(tonByAccount)) {
    byAccountId[accountId] = { balances: { bySlug: { [TONCOIN.slug]: tonByAccount[accountId] } } };
  }
  return byAccountId as GlobalState['byAccountId'];
}

function select(accountIds: string[], byAccountId: GlobalState['byAccountId']) {
  return selectMultipleAccountsBalances(
    accountIds,
    byAccountId,
    TOKEN_INFO,
    SETTINGS,
    STAKING_STATES,
    BASE_CURRENCY,
    CURRENCY_RATES,
  );
}

describe('selectMultipleAccountsBalances', () => {
  it('computes per-account values and the total', () => {
    const byAccountId = buildByAccountId({ [ACCOUNT_A]: ONE_TON, [ACCOUNT_B]: 2n * ONE_TON });
    const { balancesByAccountId, totalBalance } = select([ACCOUNT_A, ACCOUNT_B], byAccountId);

    expect(balancesByAccountId[ACCOUNT_A].value).toBe('5');
    expect(balancesByAccountId[ACCOUNT_A].currencySymbol).toBe('$');
    expect(balancesByAccountId[ACCOUNT_B].value).toBe('10');
    expect(totalBalance).toBe('$15');
  });

  it('keeps each per-account balance referentially stable when inputs are unchanged', () => {
    const byAccountId = buildByAccountId({ [ACCOUNT_A]: ONE_TON, [ACCOUNT_B]: 2n * ONE_TON });

    const first = select([ACCOUNT_A, ACCOUNT_B], byAccountId);
    const second = select([ACCOUNT_A, ACCOUNT_B], byAccountId);

    expect(second.balancesByAccountId[ACCOUNT_A]).toBe(first.balancesByAccountId[ACCOUNT_A]);
    expect(second.balancesByAccountId[ACCOUNT_B]).toBe(first.balancesByAccountId[ACCOUNT_B]);
  });

  it('recomputes only the account whose balance changed', () => {
    const byAccountId1 = buildByAccountId({ [ACCOUNT_A]: ONE_TON, [ACCOUNT_B]: 2n * ONE_TON });
    const first = select([ACCOUNT_A, ACCOUNT_B], byAccountId1);

    // New top-level reference; account B keeps its previous `balances.bySlug` object, A changes.
    const byAccountId2 = {
      [ACCOUNT_A]: { balances: { bySlug: { [TONCOIN.slug]: 3n * ONE_TON } } },
      [ACCOUNT_B]: byAccountId1[ACCOUNT_B],
    } as GlobalState['byAccountId'];
    const second = select([ACCOUNT_A, ACCOUNT_B], byAccountId2);

    expect(second.balancesByAccountId[ACCOUNT_B]).toBe(first.balancesByAccountId[ACCOUNT_B]);
    expect(second.balancesByAccountId[ACCOUNT_A]).not.toBe(first.balancesByAccountId[ACCOUNT_A]);
    expect(second.balancesByAccountId[ACCOUNT_A].value).toBe('15');
  });
});
