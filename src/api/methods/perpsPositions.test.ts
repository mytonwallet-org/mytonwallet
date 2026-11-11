import type { ApiAccountAny, ApiPerpsPosition } from '../types';

import { setIsAppFocused } from '../../util/focusAwareDelay';
import { fetchStoredChainAccount } from '../common/accounts';
import { MINUTE, SEC } from '../constants';
import { getEnvironment } from '../environment';
import { perpsGetAssets, perpsGetPositions } from './perps';
import {
  initPerpsPositions,
  perpsRefreshPositions,
  requestPerpsPositionsRefresh,
  setupPerpsPositionsPolling,
} from './perpsPositions';

jest.mock('../environment', () => ({ getEnvironment: jest.fn() }));
jest.mock('../common/accounts', () => ({
  ...jest.requireActual('../common/accounts'),
  fetchStoredChainAccount: jest.fn(),
}));
jest.mock('../chains', () => ({ chains: {} }));
jest.mock('./perps', () => ({
  getPerpsWallet: jest.requireActual('./perps').getPerpsWallet,
  perpsGetAssets: jest.fn(),
  perpsGetPositions: jest.fn(),
}));

const ADDRESS = '0x00000000000000000000000000000000000000aa';
const asset = {
  id: 'hyperliquid:hl:BTC', index: 0, wireAssetIndex: 0, name: 'BTC', symbol: 'BTC', dex: '', chain: 'hyperliquid',
  provider: 'hyperliquid', szDecimals: 5, maxLeverage: 40, context: { markPx: '100', prevDayPx: '100' },
};
const account = { type: 'mnemonic', byChain: { arbitrum: { address: ADDRESS } } } as unknown as ApiAccountAny;
const onUpdate = jest.fn();
let serial = 0;
let accountId: string;

function position(unrealizedPnl: string): ApiPerpsPosition {
  return {
    coin: 'BTC', entryPx: '100', liquidationPx: '50', leverage: { type: 'isolated', value: 2 },
    marginUsed: '55', positionValue: '110', returnOnEquity: '0.1', szi: '1', unrealizedPnl,
  } as ApiPerpsPosition;
}

function respondWith(...positions: ApiPerpsPosition[]) {
  const assetPositions = positions.map((value) => ({ position: value, type: 'oneWay' }));
  jest.mocked(perpsGetPositions).mockResolvedValue({
    positionsByChain: {
      hyperliquid: { withdrawable: '10', spendableUsdcByDex: { '': '10', xyz: '0' }, assetPositions },
    },
  } as any);
}

function publishedUpdates() {
  return onUpdate.mock.calls.map(([update]) => update).filter((update) => update.type === 'updatePerpsPositions');
}

beforeEach(() => {
  jest.useFakeTimers();
  jest.clearAllMocks();
  setIsAppFocused(true);
  accountId = `${++serial}-mainnet`;
  initPerpsPositions(onUpdate);
  jest.mocked(getEnvironment).mockReturnValue({ isIosApp: true } as any);
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({ ...account, byChain: account.byChain } as any);
  jest.mocked(perpsGetAssets).mockResolvedValue({
    assetsByChain: { hyperliquid: [asset] }, sections: [], limitsByChain: {},
  } as any);
  respondWith(position('10'));
});

afterEach(() => {
  jest.useRealTimers();
});

test('a read is published only when something but its read time changed', async () => {
  await perpsRefreshPositions(accountId);
  jest.setSystemTime(Date.now() + 5 * SEC);
  await perpsRefreshPositions(accountId);
  expect(publishedUpdates()).toHaveLength(1);
  expect(publishedUpdates()[0]).toMatchObject({
    accountId, totalEquity: '55', totalPnl: '10', unavailableDexs: [],
    spendableUsdcByDex: { '': '10', xyz: '0' },
    balanceWithdrawal: { balance: '10', amount: '9.97', bridgeFee: '0.2', receiveAmount: '9.77' },
    positions: [{ id: `${accountId}/${asset.id}`, side: 'long' }],
  });

  respondWith(position('12'));
  await perpsRefreshPositions(accountId);
  expect(publishedUpdates()).toHaveLength(2);
  expect(publishedUpdates()[1]).toMatchObject({ accountId, totalPnl: '12' });
});

test('a withdrawal that empties the balance publishes the snapshot without its preview', async () => {
  await perpsRefreshPositions(accountId);
  jest.mocked(perpsGetPositions).mockResolvedValue({
    positionsByChain: {
      hyperliquid: {
        withdrawable: '0.03',
        spendableUsdcByDex: { '': '10', xyz: '0' },
        assetPositions: [{ position: position('10'), type: 'oneWay' }],
      },
    },
  } as any);
  await perpsRefreshPositions(accountId);
  expect(publishedUpdates()).toHaveLength(2);
  expect(publishedUpdates()[1].balanceWithdrawal).toBeUndefined();
});

test('a read that answers after a newer one neither publishes nor returns its older positions', async () => {
  let answerOlderRead: (() => void) | undefined;
  const olderResponse = await new Promise((resolve) => {
    respondWith(position('10'));
    resolve(jest.mocked(perpsGetPositions)({} as any));
  });
  jest.mocked(perpsGetPositions).mockImplementationOnce(() => new Promise((resolve) => {
    answerOlderRead = () => resolve(olderResponse as any);
  }));
  const olderRead = perpsRefreshPositions(accountId);
  await jest.advanceTimersByTimeAsync(0);

  respondWith(position('12'));
  const newest = await perpsRefreshPositions(accountId);
  answerOlderRead!();

  expect(await olderRead).toBe(newest);
  expect(publishedUpdates()).toHaveLength(1);
  expect(publishedUpdates()[0]).toMatchObject({ accountId, totalPnl: '12' });
});

test('polling publishes the first read after activation, then reads at the focused cadence', async () => {
  await perpsRefreshPositions(accountId);
  const polling = setupPerpsPositionsPolling(accountId, account)!;
  await jest.advanceTimersByTimeAsync(0);
  expect(perpsGetPositions).toHaveBeenCalledTimes(2);
  expect(publishedUpdates()).toHaveLength(2);

  await jest.advanceTimersByTimeAsync(20 * SEC);
  expect(perpsGetPositions).toHaveBeenCalledTimes(3);
  expect(publishedUpdates()).toHaveLength(2);
  polling.stop();
});

test('a minute of failed reads reports positions unavailable once, and the next read publishes again', async () => {
  const unavailable = () => onUpdate.mock.calls.map(([update]) => update)
    .filter((update) => update.type === 'updatePerpsPositionsUnavailable');
  const polling = setupPerpsPositionsPolling(accountId, account)!;
  await jest.advanceTimersByTimeAsync(0);
  expect(publishedUpdates()).toHaveLength(1);

  jest.mocked(perpsGetPositions).mockRejectedValue(new Error('offline'));
  await jest.advanceTimersByTimeAsync(40 * SEC);
  expect(unavailable()).toHaveLength(0);
  await jest.advanceTimersByTimeAsync(40 * SEC);
  expect(unavailable()).toEqual([{ type: 'updatePerpsPositionsUnavailable', accountId }]);
  await jest.advanceTimersByTimeAsync(60 * SEC);
  expect(unavailable()).toHaveLength(1);

  respondWith(position('10'));
  await jest.advanceTimersByTimeAsync(20 * SEC);
  expect(publishedUpdates()).toHaveLength(2);
  polling.stop();
});

test('while the app is idle, positions are read at the idle cadence', async () => {
  const polling = setupPerpsPositionsPolling(accountId, account)!;
  await jest.advanceTimersByTimeAsync(0);
  expect(perpsGetPositions).toHaveBeenCalledTimes(1);
  setIsAppFocused(false);

  await jest.advanceTimersByTimeAsync(MINUTE);
  expect(perpsGetPositions).toHaveBeenCalledTimes(1);
  await jest.advanceTimersByTimeAsync(5 * MINUTE);
  expect(perpsGetPositions).toHaveBeenCalledTimes(2);
  polling.stop();
});

test('an operation refreshes its active account right away and any other account once', async () => {
  const polling = setupPerpsPositionsPolling(accountId, account)!;
  await jest.advanceTimersByTimeAsync(0);
  respondWith(position('20'));

  await jest.advanceTimersByTimeAsync(2 * SEC);
  requestPerpsPositionsRefresh(accountId);
  await jest.advanceTimersByTimeAsync(0);
  expect(perpsGetPositions).toHaveBeenCalledTimes(2);
  expect(publishedUpdates().at(-1)).toMatchObject({ accountId, totalPnl: '20' });

  const other = `${++serial}-mainnet`;
  requestPerpsPositionsRefresh(other);
  await jest.advanceTimersByTimeAsync(0);
  expect(publishedUpdates().at(-1)).toMatchObject({ accountId: other });
  polling.stop();
});

test('clients without a positions screen and unsupported accounts do not poll', async () => {
  expect(setupPerpsPositionsPolling(`${++serial}-testnet`, account)).toBeUndefined();
  expect(setupPerpsPositionsPolling(accountId, { ...account, byChain: {} } as ApiAccountAny)).toBeUndefined();
  jest.mocked(getEnvironment).mockReturnValue({ isIosApp: false } as any);
  expect(setupPerpsPositionsPolling(accountId, account)).toBeUndefined();
  requestPerpsPositionsRefresh(accountId);
  await jest.advanceTimersByTimeAsync(MINUTE);
  expect(perpsGetPositions).not.toHaveBeenCalled();
});
