import type { ApiChain, ApiSubmitGasfullTransferOptions } from '../types';

import { swapCexSubmit } from './swap';

jest.mock('../chains', () => ({
  __esModule: true,
  default: {
    base: {
      submitGasfullTransfer: jest.fn().mockResolvedValue({ txId: '0xbase-deposit' }),
    },
  },
}));

jest.mock('../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../common/backend', () => ({
  callBackendGet: jest.fn(),
  callBackendPost: jest.fn(),
}));

jest.mock('../common/cache', () => ({
  getBackendConfigCache: jest.fn(),
}));

jest.mock('../common/swap', () => ({
  convertSwapItemToTrusted: jest.fn(),
  getSwapItemSlug: jest.fn(),
  patchSwapItem: jest.fn(),
  swapGetHistoryItem: jest.fn(),
  swapItemToActivity: jest.fn(),
}));

jest.mock('../hooks', () => ({
  callHook: jest.fn(),
}));

jest.mock('./mfa', () => ({
  publishSignedMfaRequest: jest.fn(),
}));

jest.mock('./other', () => ({
  getBackendAuthToken: jest.fn().mockResolvedValue('backend-auth-token'),
  getStoredBackendAuthToken: jest.fn(),
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const chains = require('../chains').default as {
  base: { submitGasfullTransfer: jest.Mock };
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchStoredWallet } = require('../common/accounts') as {
  fetchStoredWallet: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { patchSwapItem } = require('../common/swap') as {
  patchSwapItem: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { publishSignedMfaRequest } = require('./mfa') as {
  publishSignedMfaRequest: jest.Mock;
};

describe('swapCexSubmit', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    chains.base.submitGasfullTransfer.mockResolvedValue({ txId: '0xbase-deposit' });
    fetchStoredWallet.mockResolvedValue({ address: 'EQ-ton-history-owner' });
    publishSignedMfaRequest.mockResolvedValue({ mfaRequestHash: 'mfa-request-hash' });
  });

  it('patches CEX history by TON owner address after a non-TON deposit transfer', async () => {
    const transferOptions = {
      accountId: '0-mainnet',
      password: 'password',
      toAddress: '0xdeposit',
      amount: 1n,
      fee: 1n,
    } as unknown as ApiSubmitGasfullTransferOptions;

    await swapCexSubmit('base' as ApiChain, transferOptions, 'swap-id');

    expect(chains.base.submitGasfullTransfer).toHaveBeenCalledWith(transferOptions);
    expect(fetchStoredWallet).toHaveBeenCalledWith('0-mainnet', 'ton');
    expect(patchSwapItem).toHaveBeenCalledWith({
      address: 'EQ-ton-history-owner',
      authToken: 'backend-auth-token',
      msgHash: '0xbase-deposit',
      swapId: 'swap-id',
    });
  });

  it('prefers msgHashForCexSwap over txId when patching CEX history', async () => {
    chains.base.submitGasfullTransfer.mockResolvedValue({
      txId: '0xbase-deposit',
      msgHashForCexSwap: '0xbase-cex-hash',
    });
    const transferOptions = {
      accountId: '0-mainnet',
      password: 'password',
      toAddress: '0xdeposit',
      amount: 1n,
      fee: 1n,
    } as unknown as ApiSubmitGasfullTransferOptions;

    await swapCexSubmit('base' as ApiChain, transferOptions, 'swap-id');

    expect(patchSwapItem).toHaveBeenCalledWith(expect.objectContaining({
      msgHash: '0xbase-cex-hash',
    }));
  });

  it('publishes MFA requests instead of patching CEX history immediately', async () => {
    const mfaRequest = {
      payload: 'payload',
      signature: 'signature',
      transaction: 'transaction',
    };
    chains.base.submitGasfullTransfer.mockResolvedValue({ mfaRequest });
    const transferOptions = {
      accountId: '0-mainnet',
      password: 'password',
      toAddress: '0xdeposit',
      amount: 1n,
      fee: 1n,
    } as unknown as ApiSubmitGasfullTransferOptions;

    const result = await swapCexSubmit('base' as ApiChain, transferOptions, 'swap-id');

    expect(publishSignedMfaRequest).toHaveBeenCalledWith('0-mainnet', 'base', mfaRequest);
    expect(patchSwapItem).not.toHaveBeenCalled();
    expect(result).toEqual({ swapId: 'swap-id', mfaRequestHash: 'mfa-request-hash' });
  });
});
