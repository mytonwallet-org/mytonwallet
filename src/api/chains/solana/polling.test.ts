import type { ApiAccountWithChain } from '../../types';

import { BalanceStream } from '../../common/websocket/balanceStream';
import { MINUTE } from '../../constants';
import { setupActivePolling } from './polling';

jest.mock('../../common/accounts', () => ({
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../../common/swap', () => ({
  swapReplaceActivities: jest.fn(),
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
  getHeliusSocket: jest.fn(),
}));

jest.mock('./wallet', () => ({
  fetchAccountAssets: jest.fn(),
  getIsWalletActive: jest.fn(),
}));

describe('Solana polling', () => {
  it('forces active balance polling every 3 minutes in focus and 10 minutes in the background', () => {
    const account = {
      type: 'view',
      byChain: { solana: { address: 'solana-address', index: 0 } },
    } as ApiAccountWithChain<'solana'>;

    const stopPolling = setupActivePolling('0-mainnet', account, jest.fn(), jest.fn(), { 'solana-sol': 1 });

    expect(BalanceStream).toHaveBeenCalledWith(expect.objectContaining({
      fallbackPollingOptions: expect.objectContaining({
        forcedPollingPeriod: { focused: 3 * MINUTE, notFocused: 10 * MINUTE },
      }),
    }));

    stopPolling();
  });
});
