import '../../../util/bigintPatch';

import { Address, Cell, internal, SendMode } from '@ton/core';
import { keyPairFromSeed, signVerify } from '@ton/crypto';
import { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import type { EmulationResponse } from './toncenter/emulation';
import { ApiTransactionError } from '../../types';

import { createMfaForwardMessage } from './util/signer';
import { getTonClient } from './util/tonCore';
import { getMfaFees, resolveMfaExtensionAddress } from './contracts/util';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { createMfaRequest } from '../../common/mfa';
import { fetchEmulateTrace } from './toncenter/emulation';
import { fetchPrivateKey } from './auth';
import { registerMfaRefillQuote, signDappTransfers } from './dapp';
import { emulateTransaction } from './emulation';
import { prepareMfaRefillBundle } from './mfaRefill';
import { checkTransactionDraft, signTransfers } from './transfer';
import { getWalletInfo } from './wallet';

// RPC boundaries: the real preparation/encoding consumes the supplied chain state and traces.
jest.mock('./contracts/util', () => ({
  resolveMfaExtensionAddress: jest.fn(), getMfaFees: jest.fn(() => Promise.resolve(100n)),
  getMfaExtensionSeqno: () => Promise.resolve(4),
}));
jest.mock('../../common/accounts', () => ({ fetchStoredChainAccount: jest.fn(), fetchStoredWallet: jest.fn() }));
jest.mock('../../common/mfa', () => ({ createMfaRequest: jest.fn() }));
jest.mock('./auth', () => ({ fetchPrivateKey: jest.fn() }));
jest.mock('./wallet', () => ({
  ...jest.requireActual('./wallet'), getWalletInfo: jest.fn(), getWalletSeqno: () => Promise.resolve(7),
  getContractInfo: () => Promise.resolve({ isInitialized: true }),
}));
jest.mock('./address', () => ({
  resolveAddress: (_network: string, address: string) => Promise.resolve({ address }),
}));
jest.mock('./emulation', () => ({ emulateTransaction: jest.fn() }));
jest.mock('./util/signer', () => ({
  ...jest.requireActual('./util/signer'),
  createMfaForwardMessage: jest.fn(jest.requireActual('./util/signer').createMfaForwardMessage),
}));
jest.mock('./toncenter/emulation', () => ({ fetchEmulateTrace: jest.fn() }));
jest.mock('./util/tonCore', () => ({
  ...jest.requireActual('./util/tonCore'), getTonClient: jest.fn(),
}));

const extension = new Address(0, Buffer.alloc(32, 1));
const recipient = new Address(0, Buffer.alloc(32, 2));
const keys = keyPairFromSeed(Buffer.alloc(32, 3));
const wallet = WalletContractV5R1.create({ publicKey: keys.publicKey, walletId: { networkGlobalId: -239 } });
const messages = [internal({ to: recipient, value: 10n }), internal({ to: recipient, value: 20n })];
const transaction = { messages, seqno: 7, sendMode: SendMode.PAY_GAS_SEPARATELY | SendMode.IGNORE_ERRORS };
const MAX_DRAFT_BALANCE = 1_001_464_057n;
const MAX_DRAFT_FORWARDED_FEE = 10_000_000n;
const MAX_DRAFT_ACCOUNT = {
  type: 'bip39' as const,
  byChain: { ton: {
    address: wallet.address.toString(), version: 'W5' as const, publicKey: keys.publicKey.toString('hex'),
    index: 0, mfa: { address: extension.toString() },
  } },
};

function trace(balance: bigint, debit: bigint): EmulationResponse {
  const description = {
    compute_ph: { success: true, exit_code: 0 }, action: { success: true, skipped_actions: 0 },
  };
  const forwarded = {
    source: extension.toRawString(), destination: wallet.address.toRawString(), hash: 'forwarded',
  };
  return {
    transactions: {
      extension: {
        account: extension.toRawString(), in_msg: { source: undefined }, out_msgs: [forwarded], description,
        account_state_before: { balance: balance.toString() },
        account_state_after: { balance: (balance - debit).toString() },
      },
      wallet: {
        account: wallet.address.toRawString(), in_msg: forwarded, description, total_fees: '300',
        out_msgs: [{ fwd_fee: '40' }, { fwd_fee: '60' }],
      },
    },
  } as unknown as EmulationResponse;
}

it.each([
  { balance: 100_000_001n, amount: 17_051_400n },
  { balance: 100_000_000n, amount: 117_051_400n },
  { balance: 99_999_999n, amount: 117_051_400n },
])('prepares one refill of $amount for two recipients at balance $balance', async ({ balance, amount }) => {
  jest.mocked(resolveMfaExtensionAddress).mockResolvedValue(extension.toString());
  jest.mocked(getTonClient).mockReturnValue({
    getAddressInfo: () => Promise.resolve({ balance: balance.toString() }),
  } as unknown as ReturnType<typeof getTonClient>);
  // Mark's TVM example: the initial 50% margin covers the added message without repricing the refill.
  jest.mocked(fetchEmulateTrace).mockReset()
    .mockResolvedValueOnce(trace(balance, 11_367_600n))
    .mockResolvedValue(trace(balance, 11_892_400n));

  const result = await prepareMfaRefillBundle('mainnet', wallet, { address: extension.toString() },
    [transaction], [100n], 4);

  expect(result?.refills).toEqual([amount]);
  expect(result?.finalNetworkFees).toEqual([400n]);
  const finalMessages = result!.transactions[0].messages;
  expect(finalMessages).toHaveLength(3);
  expect(finalMessages.slice(0, 2)).toEqual(messages);
  const info = finalMessages[2].info;
  expect(info.type).toBe('internal');
  if (info.type !== 'internal') throw new Error('Expected internal refill');
  expect(info.dest.equals(extension)).toBe(true);
  expect(info.value.coins).toBe(amount);
  expect(finalMessages[2].body.equals(Cell.EMPTY)).toBe(true);
});

it('rejects the final bundle when the fixed refill does not cover its extension debit', async () => {
  const balance = 100_000_001n;
  jest.mocked(resolveMfaExtensionAddress).mockResolvedValue(extension.toString());
  jest.mocked(getTonClient).mockReturnValue({
    getAddressInfo: () => Promise.resolve({ balance: balance.toString() }),
  } as unknown as ReturnType<typeof getTonClient>);
  jest.mocked(fetchEmulateTrace).mockReset()
    .mockResolvedValueOnce(trace(balance, 11_367_600n))
    .mockResolvedValue(trace(balance, 17_051_401n));

  expect(await prepareMfaRefillBundle('mainnet', wallet, { address: extension.toString() },
    [transaction], [100n], 4)).toBeUndefined();
});

describe('native MFA Max draft fees', () => {
  beforeEach(() => {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue(MAX_DRAFT_ACCOUNT);
    jest.mocked(getWalletInfo).mockResolvedValue({
      address: wallet.address.toString(), balance: MAX_DRAFT_BALANCE, seqno: 7, isInitialized: true,
    });
    jest.mocked(getMfaFees).mockResolvedValue(MAX_DRAFT_FORWARDED_FEE);
    jest.mocked(resolveMfaExtensionAddress).mockResolvedValue(extension.toString());
    jest.mocked(getTonClient).mockReturnValue({
      getAddressInfo: () => Promise.resolve({ balance: '100000000' }),
    } as unknown as ReturnType<typeof getTonClient>);
    jest.mocked(createMfaForwardMessage).mockClear();
    jest.mocked(fetchPrivateKey).mockClear();
    jest.mocked(createMfaRequest).mockClear();
    jest.mocked(fetchEmulateTrace).mockReset().mockImplementation(() => {
      const prepared = jest.mocked(createMfaForwardMessage).mock.calls.at(-1)![0];
      const totalAmount = prepared.messages.reduce((total, message) => (
        total + (message.info.type === 'internal' ? message.info.value.coins : 0n)
      ), 0n);
      const response = trace(100_000_000n, 2_000_001n);
      const walletTransaction = response.transactions.wallet;
      walletTransaction.description = {
        ...walletTransaction.description,
        action: {
          ...walletTransaction.description.action,
          skipped_actions: totalAmount + 400n > MAX_DRAFT_BALANCE + MAX_DRAFT_FORWARDED_FEE ? 1 : 0,
        },
      };
      return Promise.resolve(response);
    });
    jest.mocked(emulateTransaction).mockReset().mockResolvedValue({
      networkFee: 400n,
    } as Awaited<ReturnType<typeof emulateTransaction>>);
  });

  afterEach(() => {
    jest.mocked(getMfaFees).mockResolvedValue(100n);
  });

  it('returns the refill cost for Max and validates the amount after reserving that fee', async () => {
    const options = { accountId: '0-mainnet', toAddress: recipient.toString(), amount: MAX_DRAFT_BALANCE };
    const draft = await checkTransactionDraft(options);
    expect(draft.explainedFee?.fullFee).toBeDefined();
    const fullFee = draft.explainedFee!.fullFee!.nativeSum;

    expect(draft.error).toBe(ApiTransactionError.InsufficientBalance);
    expect(fullFee).toBe(103_000_422n);
    expect(draft.explainedFee!.canTransferFullBalance).toBe(false);

    const adjustedAmount = MAX_DRAFT_BALANCE - fullFee;
    const adjustedDraft = await checkTransactionDraft({ ...options, amount: adjustedAmount });
    expect(adjustedDraft.error).toBeUndefined();
    expect(adjustedDraft.explainedFee!.fullFee!.nativeSum).toBe(fullFee);
    const prepared = jest.mocked(createMfaForwardMessage).mock.calls.at(-1)![0];
    const transfer = prepared.messages[0].info;
    expect(transfer.type === 'internal' && transfer.value.coins).toBe(adjustedAmount);
    expect(prepared.sendMode & SendMode.CARRY_ALL_REMAINING_BALANCE).toBe(0);
    expect(fetchPrivateKey).not.toHaveBeenCalled();
    expect(createMfaRequest).not.toHaveBeenCalled();
  });

  it('preserves failed refill validation even when probing Max', async () => {
    const failedTrace = trace(100_000_000n, 2_000_001n);
    const walletTransaction = failedTrace.transactions.wallet;
    walletTransaction.description = {
      ...walletTransaction.description,
      action: { ...walletTransaction.description.action, skipped_actions: 1 },
    };
    jest.mocked(fetchEmulateTrace)
      .mockResolvedValueOnce(trace(100_000_000n, 2_000_001n))
      .mockResolvedValueOnce(failedTrace);
    const draft = await checkTransactionDraft({
      accountId: '0-mainnet', toAddress: recipient.toString(), amount: MAX_DRAFT_BALANCE,
    });
    expect(draft.error).toBe(ApiTransactionError.InsufficientBalance);
    expect(draft.explainedFee).toBeUndefined();
    expect(fetchPrivateKey).not.toHaveBeenCalled();
  });

  it('does not replace a contract call amount with a fee probe', async () => {
    const draft = await checkTransactionDraft({
      accountId: '0-mainnet', toAddress: recipient.toString(), amount: MAX_DRAFT_BALANCE,
      payload: { type: 'comment', text: 'deposit' },
    });
    expect(draft.error).toBe(ApiTransactionError.InsufficientBalance);
    expect(draft.explainedFee).toBeUndefined();
    const transfer = jest.mocked(createMfaForwardMessage).mock.calls[0][0].messages[0].info;
    expect(transfer.type === 'internal' && transfer.value.coins).toBe(MAX_DRAFT_BALANCE);
  });

  it('preserves full-balance native transfers without MFA', async () => {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue({
      ...MAX_DRAFT_ACCOUNT, byChain: { ton: { ...MAX_DRAFT_ACCOUNT.byChain.ton, mfa: undefined } },
    });
    const draft = await checkTransactionDraft({
      accountId: '0-mainnet', toAddress: recipient.toString(), amount: MAX_DRAFT_BALANCE,
    });
    expect(draft.error).toBeUndefined();
    expect(draft.explainedFee!.canTransferFullBalance).toBe(true);
    expect(emulateTransaction).toHaveBeenCalledTimes(1);
    expect(fetchEmulateTrace).not.toHaveBeenCalled();
  });
});

describe('TonConnect MFA signing of the approved refill', () => {
  const messagesToSign = [
    { toAddress: recipient.toString(), amount: 10n },
    { toAddress: recipient.toString(), amount: 20n },
  ];

  beforeEach(() => {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue({
      type: 'bip39', byChain: { ton: {
        address: wallet.address.toString(), version: 'W5', publicKey: keys.publicKey.toString('hex'),
        index: 0, mfa: { address: extension.toString() },
      } },
    });
    jest.mocked(fetchPrivateKey).mockReset().mockResolvedValue(keys.secretKey);
    jest.mocked(fetchStoredWallet).mockResolvedValue({
      address: wallet.address.toString(), version: 'W5', publicKey: keys.publicKey.toString('hex'), index: 0,
      authToken: 'synthetic-wallet-auth',
    });
    jest.mocked(createMfaRequest).mockReset().mockResolvedValue({ reqId: 'synthetic-request' });
    jest.mocked(getWalletInfo).mockResolvedValue({
      address: wallet.address.toString(), balance: 1_000_000_000n, seqno: 7, isInitialized: true,
    });
    jest.mocked(resolveMfaExtensionAddress).mockResolvedValue(extension.toString());
    jest.mocked(getTonClient).mockReturnValue({
      getAddressInfo: () => Promise.resolve({ balance: '100000000' }),
    } as unknown as ReturnType<typeof getTonClient>);
    jest.mocked(fetchEmulateTrace).mockReset().mockResolvedValue(trace(100_000_000n, 2_000_001n));
  });

  function approvedTransfers() {
    return [...messagesToSign, { toAddress: extension.toString(), amount: 103_000_002n }]
      .map((message) => ({
        ...message, chain: 'ton' as const, isDangerous: false, normalizedAddress: message.toAddress,
        displayedToAddress: message.toAddress, networkFee: 0n,
      }));
  }

  it('publishes the exact consented refill with valid wallet authentication despite later fee drift', async () => {
    const transfers = approvedTransfers();
    const release = registerMfaRefillQuote('0-mainnet', transfers, 103_000_002n);
    jest.mocked(fetchEmulateTrace).mockResolvedValue(trace(100_000_000n, 2_000_002n));
    try {
      const result = await signDappTransfers('0-mainnet', transfers, { enclaveToken: 'synthetic-enclave-token' });
      expect(result).toEqual({ mfaRequestHash: 'synthetic-request' });
      const published = jest.mocked(createMfaRequest).mock.calls[0][0];
      expect(published.mfaRefillAmount).toBe(103_000_002n);
      expect(published.authToken).toBeTruthy();
      expect(signVerify(Cell.fromBoc(published.payload)[0].hash(), published.signature, keys.publicKey)).toBe(true);
    } finally {
      release();
    }
  });

  it('rejects a recipient changed after consent before requesting the private key', async () => {
    const transfers = approvedTransfers();
    const release = registerMfaRefillQuote('0-mainnet', transfers, 103_000_002n);
    try {
      transfers[0] = { ...transfers[0], toAddress: wallet.address.toString() };
      expect(await signDappTransfers('0-mainnet', transfers)).toEqual({
        error: ApiTransactionError.ConcurrentTransaction,
      });
      expect(fetchPrivateKey).not.toHaveBeenCalled();
    } finally {
      release();
    }
  });

  it('rejects an unquoted transfer to the extension before requesting the private key', async () => {
    const transfers = [...messagesToSign, { toAddress: extension.toString(), amount: 103_000_002n }]
      .map((message) => ({
        ...message, chain: 'ton' as const, isDangerous: false, normalizedAddress: message.toAddress,
        displayedToAddress: message.toAddress, networkFee: 0n,
      }));
    const result = await signDappTransfers('0-mainnet', transfers, { enclaveToken: 'synthetic-enclave-token' });
    expect(result).toEqual({ error: ApiTransactionError.ConcurrentTransaction });
    expect(fetchPrivateKey).not.toHaveBeenCalled();
  });

  it('rejects a refill that the wallet cannot afford before requesting the private key', async () => {
    jest.mocked(getWalletInfo).mockResolvedValue({
      address: wallet.address.toString(), balance: 100_000_000n, seqno: 7, isInitialized: true,
    });
    const result = await signTransfers('0-mainnet', messagesToSign, 'synthetic-enclave-token',
      undefined, undefined, true, 103_000_002n);
    expect(result).toEqual({ error: ApiTransactionError.InsufficientBalance });
    expect(fetchPrivateKey).not.toHaveBeenCalled();
  });
});
