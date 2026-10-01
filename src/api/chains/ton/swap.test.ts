import { Address, beginCell, Cell } from '@ton/core';

import type { ApiAccountWithChain, ApiSwapBuildTransactionRequest } from '../../types';
import type { ApiSubmitOnchainSwapTransferOptions } from '../../types/swap';

import { JettonOpCode } from './constants';
import { submitOnchainSwapTransfer, validateDexSwapTransfers } from './swap';

const mockResolveTokenAddress = jest.fn();
const mockResolveTokenWalletAddress = jest.fn();
const mockGetTokenByAddress = jest.fn();
const mockGetContractInfo = jest.fn();

jest.mock('../../common/accounts', () => ({
  fetchStoredChainAccount: jest.fn(),
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../../common/swap', () => ({ patchSwapItem: jest.fn() }));
jest.mock('../../common/tokens', () => ({
  ...jest.requireActual('../../common/tokens'),
  getTokenByAddress: (...args: unknown[]) => mockGetTokenByAddress(...args),
}));
jest.mock('../../hooks', () => ({ callHook: jest.fn() }));
jest.mock('./transfer', () => ({
  checkMultiTransactionDraft: jest.fn(),
  submitMultiTransferWithMfa: jest.fn(),
}));
jest.mock('./util/tonCore', () => ({
  ...jest.requireActual('./util/tonCore'),
  resolveTokenAddress: (...args: unknown[]) => mockResolveTokenAddress(...args),
  resolveTokenWalletAddress: (...args: unknown[]) => mockResolveTokenWalletAddress(...args),
}));
jest.mock('./wallet', () => ({
  getContractInfo: (...args: unknown[]) => mockGetContractInfo(...args),
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchStoredChainAccount, fetchStoredWallet } = require('../../common/accounts') as {
  fetchStoredChainAccount: jest.Mock;
  fetchStoredWallet: jest.Mock;
};
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { submitMultiTransferWithMfa } = require('./transfer') as {
  submitMultiTransferWithMfa: jest.Mock;
};

const OWNER_ADDRESS = `0:${'1'.repeat(64)}`;
const TOKEN_ADDRESS = `0:${'2'.repeat(64)}`;
const TOKEN_WALLET_ADDRESS = `0:${'3'.repeat(64)}`;
const SWAP_ADDRESS = `0:${'4'.repeat(64)}`;

describe('submitOnchainSwapTransfer', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fetchStoredWallet.mockResolvedValue({ address: 'EQ-wallet' });
    fetchStoredChainAccount.mockResolvedValue({ byChain: { ton: {} } });
    submitMultiTransferWithMfa.mockResolvedValue({
      msgHash: 'raw-boc-hash',
      msgHashNormalized: 'normalized-external-hash',
      messages: [{}],
      withW5Gasless: true,
    });
  });

  it('keeps local reconciliation metadata after a successful TON submit', async () => {
    const onUpdate = jest.fn();
    const localSwap = {
      id: 'swap-id::local',
      kind: 'swap',
      timestamp: 1,
      from: 'TON',
      fromAmount: '1',
      to: 'ton-token',
      toAmount: '2',
      networkFee: '0',
      swapFee: '0',
      ourFee: '0',
      status: 'pendingTrusted',
      hashes: [],
      transactionIds: {},
      extra: {
        reconciliation: {
          operationId: 'swap:swap-id',
          sourceActionIds: ['swap-id::local'],
          hiddenSourceActionIds: [],
          reason: 'local-intent',
        },
      },
    } as const;
    const options = {
      accountId: '0-mainnet',
      enclaveToken: 'enclave-token',
      transfers: [{
        amount: '1',
        payload: Cell.EMPTY.toBoc().toString('base64'),
        toAddress: 'EQ-destination',
      }],
      historyItem: { from: 'TON' },
      isGasless: false,
      authToken: 'auth-token',
      localSwap,
      swapId: 'swap-id',
    } as unknown as ApiSubmitOnchainSwapTransferOptions;

    const result = await submitOnchainSwapTransfer(options, onUpdate);

    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({
      type: 'newLocalActivities',
      activities: [expect.objectContaining({
        externalMsgHashNorm: 'normalized-external-hash',
        extra: expect.objectContaining({
          withW5Gasless: true,
          reconciliation: expect.objectContaining({
            operationId: 'swap:swap-id',
            reason: 'local-intent',
          }),
        }),
      })],
    }));
    expect(result).toEqual({
      activityId: 'swap-id::local',
      submittedHashes: ['raw-boc-hash', 'normalized-external-hash'],
    });
  });
});

describe('validateDexSwapTransfers', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockResolveTokenAddress.mockRejectedValue(new Error('Token wallet is not deployed'));
    mockResolveTokenWalletAddress.mockResolvedValue(TOKEN_WALLET_ADDRESS);
    mockGetTokenByAddress.mockReturnValue({
      decimals: 9,
      tokenAddress: TOKEN_ADDRESS,
    });
    mockGetContractInfo.mockResolvedValue({
      isSwapAllowed: true,
      codeHash: 'code-hash',
    });
  });

  it('accepts a valid transfer payload before a mintless token wallet is deployed', async () => {
    const payload = beginCell()
      .storeUint(JettonOpCode.Transfer, 32)
      .storeUint(1n, 64)
      .storeCoins(2n)
      .storeAddress(Address.parse(SWAP_ADDRESS))
      .storeAddress(Address.parse(OWNER_ADDRESS))
      .storeMaybeRef(undefined)
      .storeCoins(0n)
      .storeBit(0)
      .endCell();
    const request = {
      from: 'ton-token',
      fromAmount: '1',
    } as ApiSwapBuildTransactionRequest;
    const account = {
      type: 'mnemonic',
      byChain: { ton: { version: 'W5' } },
    } as unknown as ApiAccountWithChain<'ton'>;

    await expect(validateDexSwapTransfers('mainnet', OWNER_ADDRESS, request, [{
      toAddress: TOKEN_WALLET_ADDRESS,
      amount: 1n,
      payload,
    }], account)).resolves.toBeUndefined();

    expect(mockResolveTokenAddress).not.toHaveBeenCalled();
  });
});
