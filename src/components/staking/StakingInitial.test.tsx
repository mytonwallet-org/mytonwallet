// Imports schedule layout work, so they must share the test clock.
import '../../../tests/initFakeTimers';

import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { ApiLiquidStakingState } from '../../api/types';
import type { AmountInputStateOutput } from '../ui/hooks/useAmountInputState';

import { TONCOIN } from '../../config';
import { INITIAL_STATE } from '../../global/initialState';
import { fromDecimal, toDecimal } from '../../util/decimals';
import { getTonStakingFees } from '../../util/fee/getTonOperationFees';

import AmountInput from '../ui/AmountInput';
import StakingInitial from './StakingInitial';

const mockActions: Record<string, jest.Mock> = {};

jest.mock('../../global', () => {
  const getActions = () => new Proxy(mockActions, {
    get: (actions, name: string) => (actions[name] ??= jest.fn()),
  });

  return {
    ...jest.requireActual('../../global'),
    getActions,
    getPromiseActions: getActions,
    withGlobal: () => (Component: unknown) => Component,
  };
});
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en', isRtl: false }),
}));
jest.mock('../ui/AmountInput', () => {
  const { default: Teact } = jest.requireActual('../../lib/teact/teact');

  return {
    __esModule: true,
    default: jest.fn(({ inputValue }: AmountInputStateOutput) => (
      Teact.createElement('input', { value: inputValue ?? '' })
    )),
  };
});
jest.mock('../common/InfoBanner', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../ui/Button', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../ui/Fee', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../ui/Modal', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../ui/ModalFooter', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../ui/Transition', () => ({ __esModule: true, default: () => undefined }));
jest.mock('./StakingDetails', () => ({ __esModule: true, default: () => undefined }));

const RESTAKE_AMOUNT = fromDecimal('10', TONCOIN.decimals);
const INITIAL_BALANCE = fromDecimal('5', TONCOIN.decimals);
const FUNDED_BALANCE = fromDecimal('20', TONCOIN.decimals);
const STAKING_STATE: ApiLiquidStakingState = {
  id: 'liquid',
  type: 'liquid',
  tokenSlug: TONCOIN.slug,
  annualYield: 4,
  yieldType: 'APY',
  balance: 0n,
  tokenBalance: 0n,
  pool: 'pool',
  instantAvailable: 0n,
  start: 0,
  end: 0,
  tvl: 0n,
  totalStakers: 0,
};
const TON_TOKEN = { ...TONCOIN, percentChange24h: 0 };

describe('StakingInitial restake amount', () => {
  let root: HTMLDivElement;

  beforeAll(async () => {
    await import('../../../tests/initGlobal');
  });

  afterAll(() => {
    jest.useRealTimers();
  });

  beforeEach(() => {
    jest.clearAllMocks();
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    await jest.runAllTimersAsync();
    root.remove();
  });

  it('follows the growing maximum up to the restake amount until the user edits it', async () => {
    await renderForm(0n, RESTAKE_AMOUNT);
    expect(getInput().value).toBe('');

    const maxAmount = INITIAL_BALANCE - getTonStakingFees('liquid').stake.gas * 2n;
    await renderForm(INITIAL_BALANCE, RESTAKE_AMOUNT);
    expect(getInput().value).toBe(toDecimal(maxAmount, TONCOIN.decimals));

    await renderForm(FUNDED_BALANCE, RESTAKE_AMOUNT);
    expect(getInput().value).toBe(toDecimal(RESTAKE_AMOUNT, TONCOIN.decimals));

    await changeAmount('3');
    expect(getInput().value).toBe('3');
    await renderForm(FUNDED_BALANCE * 2n, RESTAKE_AMOUNT);
    expect(getInput().value).toBe('3');
  });

  it('preserves the user amount when the balance changes after a restake prefill', async () => {
    await renderForm(FUNDED_BALANCE, RESTAKE_AMOUNT);
    expect(getInput().value).toBe(toDecimal(RESTAKE_AMOUNT, TONCOIN.decimals));

    await changeAmount('7');
    expect(getInput().value).toBe('7');

    await renderForm(FUNDED_BALANCE * 2n, RESTAKE_AMOUNT);
    expect(getInput().value).toBe('7');
  });

  it('applies a restake amount arriving after user input until the user edits it again', async () => {
    await renderForm(FUNDED_BALANCE);
    await changeAmount('3');
    expect(getInput().value).toBe('3');

    await renderForm(FUNDED_BALANCE, RESTAKE_AMOUNT);
    expect(getInput().value).toBe(toDecimal(RESTAKE_AMOUNT, TONCOIN.decimals));

    await changeAmount('7');
    expect(getInput().value).toBe('7');
    await renderForm(FUNDED_BALANCE * 2n, RESTAKE_AMOUNT);
    expect(getInput().value).toBe('7');
  });

  async function renderForm(balance: bigint, restakeAmount?: bigint) {
    const props = {
      isViewMode: false,
      baseCurrency: 'USD' as const,
      currencyRates: INITIAL_STATE.currencyRates,
      stakingState: STAKING_STATE,
      states: [STAKING_STATE],
      tokenBySlug: { [TONCOIN.slug]: TON_TOKEN },
      tokens: [{
        ...TONCOIN,
        amount: balance,
        price: TONCOIN.priceUsd,
        change24h: 0,
        totalValue: '0',
      }],
      restakeAmount,
      isStakingBannerLoading: false,
    };

    TeactDOM.render(<StakingInitial {...props} />, root);
    await jest.advanceTimersByTimeAsync(100);
  }

  async function changeAmount(value: string) {
    jest.mocked(AmountInput).mock.calls.at(-1)![0].onInputChange(value);
    await jest.advanceTimersByTimeAsync(100);
  }

  function getInput() {
    return root.querySelector('input')!;
  }
});
