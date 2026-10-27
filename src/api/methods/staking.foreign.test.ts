import { Address, beginCell } from '@ton/core';

import type { ApiForeignUnstakeDraft } from '../types';
import { ApiTransactionDraftError } from '../types';

import {
  checkForeignUnstakeDraft,
  fetchStakingForeign,
  submitForeignUnstake,
} from './staking';

const WALLET_ADDRESS = 'EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c';
const TOKEN_ADDRESS = 'EQC98_qAmNEptUtPc7W6xdHh_ZHrBUFpw5Ft_IzNU20QAJav';
const PROVIDER_WALLET = 'EQD2_4d91M4TVbEBVyBF8J1UwpMJc361LKVCz6bBlffMW05o';
const mockCallBackendGet = jest.fn();
const mockResolveTokenWalletAddress = jest.fn();
const mockCheckMultiTransactionDraft = jest.fn();
const mockSubmitMultiTransferWithMfa = jest.fn();
const mockActivities = jest.fn();
const mockPollForeignStakingPromotion = jest.fn();
const mockPublishMfa = jest.fn();
const mockRegisterMfa = jest.fn();
const mockSigner = {};

jest.mock('../chains', () => ({
  __esModule: true,
  default: { ton: { staking: { getCommonData: jest.fn() } } },
}));
jest.mock('../common/accounts', () => ({
  fetchStoredAccount: jest.fn().mockResolvedValue({
    type: 'mnemonic',
    byChain: { ton: { address: WALLET_ADDRESS, version: 'W5' } },
  }),
  fetchStoredChainAccount: jest.fn().mockResolvedValue({
    type: 'mnemonic',
    byChain: { ton: { address: WALLET_ADDRESS, version: 'W5' } },
  }),
  fetchStoredWallet: jest.fn().mockResolvedValue({ address: WALLET_ADDRESS }),
  fetchStoredAddress: jest.fn().mockResolvedValue(WALLET_ADDRESS),
  doesAccountHaveChain: (
    account: { byChain: Record<string, unknown> },
    chain: string,
  ) => Boolean(account.byChain[chain]),
}));
jest.mock('../common/backend', () => ({
  callBackendGet: (...args: unknown[]) => mockCallBackendGet(...args),
}));
jest.mock('../common/cache', () => ({}));
jest.mock('../chains/ton/util/signer', () => ({ getSigner: () => mockSigner }));
jest.mock('../chains/ton/util/tonCore', () => ({
  ...jest.requireActual('../chains/ton/util/tonCore'),
  resolveTokenWalletAddress: (...args: unknown[]) => mockResolveTokenWalletAddress(...args),
}));
jest.mock('../chains/ton/transfer', () => ({
  checkMultiTransactionDraft: (...args: unknown[]) => mockCheckMultiTransactionDraft(...args),
  submitMultiTransferWithMfa: (...args: unknown[]) => mockSubmitMultiTransferWithMfa(...args),
}));
jest.mock('./polling', () => ({ pollForeignStakingPromotion: () => mockPollForeignStakingPromotion() }));
jest.mock('./mfa', () => ({
  publishSignedMfaRequest: (...args: unknown[]) => mockPublishMfa(...args),
  registerMfaConfirmationHandler: (...args: unknown[]) => mockRegisterMfa(...args),
}));
jest.mock('./transfer', () => ({ createLocalTransactions: (...args: unknown[]) => mockActivities(...args) }));

const payload = beginCell()
  .storeUint(0x595f07bc, 32)
  .storeUint(0, 64)
  .storeCoins(500000000000n)
  .storeAddress(Address.parse(WALLET_ADDRESS))
  .storeMaybeRef(
    beginCell()
      .storeUint(0, 1)
      .storeUint(0, 1)
      .endCell(),
  )
  .endCell()
  .toBoc()
  .toString('base64');
const transfers = [{ toAddress: PROVIDER_WALLET, amount: 1050000000n, payload }];
const draft: ApiForeignUnstakeDraft = {
  amountNative: 100000000000n,
  transfers,
  fee: 1000000n,
  realFee: 1000000n,
  isInstant: true,
};

beforeEach(() => {
  jest.clearAllMocks();
  mockCallBackendGet.mockResolvedValue([{ chain: 'ton', providers: [{
    name: 'GRAM',
    provider: 'ts',
    amount: '500',
    amountNative: '100',
    apy: 3,
    unstake: { builder: 'ts', tokenAddress: TOKEN_ADDRESS, ownerAddress: WALLET_ADDRESS, instantAvailable: '100' },
  }, {
    name: 'future',
    provider: 'future',
    amount: '1',
    amountNative: '1',
    apy: 1,
    unstake: { builder: 'future', ownerAddress: WALLET_ADDRESS },
  }] }]);
  mockResolveTokenWalletAddress.mockResolvedValue(PROVIDER_WALLET);
  mockCheckMultiTransactionDraft.mockResolvedValue({
    emulation: {
      isFallback: false,
      networkFee: 1000000n,
      realFee: 1000000n,
      received: 0n,
      activities: [],
      traceOutputs: [],
    },
  });
  mockSubmitMultiTransferWithMfa.mockResolvedValue({ msgHashNormalized: 'unstake-hash' });
  mockActivities.mockReturnValue([{ id: 'activity-id' }]);
});

it('fetches foreign staking through the SDK method and keeps the backend contract chain-agnostic', async () => {
  expect(await fetchStakingForeign('0-mainnet')).toEqual([{ chain: 'ton', providers: [
    expect.objectContaining({
      name: 'GRAM',
      amount: 500000000000n,
      amountNative: 100000000000n,
      unstake: {
        builder: 'ts', tokenAddress: TOKEN_ADDRESS, ownerAddress: WALLET_ADDRESS, instantAvailable: 100000000000n,
      },
    }),
    expect.objectContaining({
      name: 'future',
      provider: 'future',
      unstake: { builder: 'future', ownerAddress: WALLET_ADDRESS },
    }),
  ] }]);
  expect(mockCallBackendGet).toHaveBeenCalledWith('/staking/foreign', { address: WALLET_ADDRESS, live: '1' });
});

it('checks a supported provider by building the unstake transaction on the client', async () => {
  expect(await checkForeignUnstakeDraft('0-mainnet', 'ton', 'GRAM')).toEqual(draft);
  expect(mockCallBackendGet).toHaveBeenCalledWith('/staking/foreign', { address: WALLET_ADDRESS, live: '1' });
  expect(mockResolveTokenWalletAddress).toHaveBeenCalledWith('mainnet', WALLET_ADDRESS, TOKEN_ADDRESS);
  expect(mockCheckMultiTransactionDraft).toHaveBeenCalledWith('0-mainnet', [
    expect.objectContaining({ toAddress: PROVIDER_WALLET, amount: 1050000000n }),
  ]);
  expect(mockSubmitMultiTransferWithMfa).not.toHaveBeenCalled();
});

it.each([
  ['99.999999999', false],
  [undefined, false],
])('expects a delayed payout when the provider can pay out %s instantly', async (instantAvailable, isInstant) => {
  mockCallBackendGet.mockResolvedValue([{ chain: 'ton', providers: [{
    name: 'GRAM',
    provider: 'ts',
    amount: '500',
    amountNative: '100',
    apy: 3,
    unstake: { builder: 'ts', tokenAddress: TOKEN_ADDRESS, ownerAddress: WALLET_ADDRESS, instantAvailable },
  }] }]);
  expect(await checkForeignUnstakeDraft('0-mainnet', 'ton', 'GRAM')).toEqual({ ...draft, isInstant });
});

it.each([
  ['jetton', { tokenAddress: PROVIDER_WALLET, ownerAddress: WALLET_ADDRESS }],
  ['owner', { tokenAddress: TOKEN_ADDRESS, ownerAddress: PROVIDER_WALLET }],
])('refuses to build a burn for a backend-reported %s it does not expect', async (_, addresses) => {
  mockCallBackendGet.mockResolvedValue([{ chain: 'ton', providers: [{
    name: 'GRAM',
    provider: 'ts',
    amount: '500',
    amountNative: '100',
    apy: 3,
    unstake: { builder: 'ts', ...addresses },
  }] }]);
  await expect(checkForeignUnstakeDraft('0-mainnet', 'ton', 'GRAM')).rejects.toThrow();
  expect(mockCheckMultiTransactionDraft).not.toHaveBeenCalled();
});

it('submits only the reviewed transaction and refreshes the active promotion', async () => {
  expect(await submitForeignUnstake('0-mainnet', 'ton', 'GRAM', draft, 'enclave')).toEqual({
    activityIds: ['activity-id'],
  });
  const options = mockSubmitMultiTransferWithMfa.mock.calls[0][0];
  expect(options).toMatchObject({ accountId: '0-mainnet', signer: mockSigner });
  expect(options.messages[0].amount).toBe(1050000000n);
  expect(options.messages[0].payload.toBoc().toString('base64')).toBe(payload);
  expect(mockPollForeignStakingPromotion).toHaveBeenCalledTimes(1);
});

it('rejects unsupported or changed provider data before signing', async () => {
  const changed = { ...draft, transfers: [{ ...transfers[0], toAddress: WALLET_ADDRESS }] };
  await expect(checkForeignUnstakeDraft('0-mainnet', 'ton', 'future')).rejects.toThrow();
  expect(await submitForeignUnstake('0-mainnet', 'ton', 'GRAM', changed, 'enclave')).toEqual({
    error: 'Unexpected',
  });
  mockCheckMultiTransactionDraft.mockResolvedValue({ error: ApiTransactionDraftError.InsufficientBalance });
  expect(await submitForeignUnstake('0-mainnet', 'ton', 'GRAM', draft, 'enclave')).toEqual({
    error: ApiTransactionDraftError.InsufficientBalance,
  });
  expect(mockSubmitMultiTransferWithMfa).not.toHaveBeenCalled();
});
