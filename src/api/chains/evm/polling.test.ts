import type { ApiAccountWithChain, ApiActivity, OnApiUpdate, OnUpdatingStatusChange } from '../../types';

import { NftStream } from './util/nftStream';
import { fetchStoredWallet } from '../../common/accounts';
import { BalanceStream } from '../../common/websocket/balanceStream';
import { getTokenActivitySlice } from './activities';
import { setupActivePolling } from './polling';

jest.mock('../../common/accounts', () => ({
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../../common/tokens', () => ({
  sendUpdateTokens: jest.fn(),
}));

jest.mock('../../common/txCallbacks', () => ({
  txCallbacks: { runCallbacks: jest.fn() },
}));

jest.mock('../../common/websocket/balanceStream', () => ({
  BalanceStream: jest.fn().mockImplementation(() => ({
    onUpdate: jest.fn(),
    onLoadingChange: jest.fn(),
    start: jest.fn(),
    destroy: jest.fn(),
    markWalletActiveAndForcePoll: jest.fn(),
  })),
}));

jest.mock('./activities', () => ({
  getTokenActivitySlice: jest.fn(),
}));

jest.mock('./util/nftStream', () => ({
  NftStream: jest.fn().mockImplementation(() => ({
    onUpdate: jest.fn(),
    destroy: jest.fn(),
  })),
}));

jest.mock('./util/socket', () => ({
  getAlchemySocket: jest.fn(() => ({
    watchWallets: jest.fn(() => ({ isConnected: false, destroy: jest.fn() })),
  })),
}));

jest.mock('./wallet', () => ({
  fetchAccountAssets: jest.fn(),
  fetchCrosschainAccountAssets: jest.fn(),
  getIsWalletActive: jest.fn(),
}));

const ADDRESS = '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3';

const mockedFetchStoredWallet = jest.mocked(fetchStoredWallet);
const mockedGetTokenActivitySlice = jest.mocked(getTokenActivitySlice);
const MockedBalanceStream = jest.mocked(BalanceStream);
const MockedNftStream = jest.mocked(NftStream);

type MockedBalanceStreamInstance = jest.Mocked<{
  onUpdate: jest.Mock;
  onLoadingChange: jest.Mock;
  start: jest.Mock;
  destroy: jest.Mock;
  markWalletActiveAndForcePoll: jest.Mock;
}>;

function getBalanceStreamInstance() {
  return MockedBalanceStream.mock.results[0].value as MockedBalanceStreamInstance;
}

describe('EVM polling', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedFetchStoredWallet.mockResolvedValue({ address: ADDRESS, index: 0 });
  });

  it('forces balance polling when initial activity catch-up finds an EVM transaction', async () => {
    const activity = {
      id: '0xactivity',
      timestamp: 1_773_000_000_000,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [activity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

    expect(MockedBalanceStream).toHaveBeenCalledTimes(1);
    expect(MockedNftStream).toHaveBeenCalledTimes(1);
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();

    expect(getBalanceStreamInstance().markWalletActiveAndForcePoll).toHaveBeenCalledTimes(1);
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'initialActivities',
      chain: 'bnb',
      accountId: '0-mainnet',
      mainActivities: [activity],
    }));
  });

  it('forces balance polling when balance updates trigger catch-up that finds a new EVM transaction', async () => {
    const activity = {
      id: '0xnew-activity',
      timestamp: 1_773_000_010_000,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [activity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, { bnb: 1_773_000_000_000 });

    const balanceUpdate = getBalanceStreamInstance().onUpdate.mock.calls[0][0] as (
      balances: Record<string, bigint>,
      source: 'poll' | 'socket',
    ) => void;
    balanceUpdate({ bnb: 1n }, 'poll');

    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();

    expect(getBalanceStreamInstance().markWalletActiveAndForcePoll).toHaveBeenCalledTimes(1);
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'newActivities',
      chain: 'bnb',
      accountId: '0-mainnet',
      activities: [activity],
    }));
  });
});
