import '../../../util/bigintPatch';

import { Address, Cell } from '@ton/core';

import type { ApiAccountWithChain, ApiNft } from '../../types';
import type { ApiTonWalletVersion } from './types';
import { ApiCommonError, ApiTransactionDraftError, ApiTransactionError } from '../../types';

import { getSigner } from './util/signer';
import { fetchStoredChainAccount } from '../../common/accounts';
import { checkNftTransferDraft, submitNftTransfers } from './nfts';
import { checkMultiTransactionDraft, checkToAddress, submitMultiTransferWithMfa } from './transfer';

jest.mock('../../common/accounts', () => ({ fetchStoredChainAccount: jest.fn() }));
jest.mock('./util/signer', () => ({ getSigner: jest.fn() }));
jest.mock('./transfer', () => ({
  checkMultiTransactionDraft: jest.fn(),
  checkToAddress: jest.fn(),
  submitMultiTransferWithMfa: jest.fn(),
  resolveTransactionError: () => 'UnsuccesfulTransfer',
}));

const ACCOUNT_ID = '0-mainnet';
const ADDRESS = new Address(0, Buffer.alloc(32, 1)).toString();
const SIGNER = {} as ReturnType<typeof getSigner>;

function makeAccount(version: ApiTonWalletVersion = 'v4R2'): ApiAccountWithChain<'ton'> {
  return {
    type: 'ton',
    byChain: { ton: { address: ADDRESS, version, publicKey: '00'.repeat(32), index: 0 } },
  };
}

function makeOptions(count: number) {
  return {
    accountId: ACCOUNT_ID,
    enclaveToken: 'test-token',
    toAddress: ADDRESS,
    nfts: Array.from({ length: count }, (_, index): ApiNft => {
      const hash = Buffer.alloc(32);
      hash.writeUInt32BE(index + 1, 28);
      return {
        chain: 'ton',
        address: new Address(0, hash).toString(),
        index,
        isOnSale: false,
        metadata: {},
        interface: 'default',
      };
    }),
  };
}

beforeEach(() => {
  jest.resetAllMocks();
  jest.mocked(fetchStoredChainAccount).mockResolvedValue(makeAccount());
  jest.mocked(getSigner).mockReturnValue(SIGNER);
  jest.mocked(checkToAddress).mockResolvedValue({
    resolvedAddress: ADDRESS, addressName: undefined, isMemoRequired: undefined, isScam: undefined, isBounceable: true,
  });
  jest.mocked(checkMultiTransactionDraft).mockImplementation((_accountId, messages) => Promise.resolve({
    emulation: { isFallback: true, networkFee: 100n + BigInt(messages.length) * 10n },
  }));
  jest.mocked(submitMultiTransferWithMfa).mockImplementation(({ messages }) => {
    const batchNumber = jest.mocked(submitMultiTransferWithMfa).mock.calls.length;
    return Promise.resolve({
      messages,
      seqno: 40 + batchNumber,
      msgHashNormalized: `hash-${batchNumber}`,
      msgHash: `hash-${batchNumber}`,
      amount: '0',
      boc: 'boc',
    });
  });
});

describe('wallet-aware NFT batches', () => {
  it.each<[ApiTonWalletVersion, number, number[]]>([
    ['v4R2', 4, [4]],
    ['v4R2', 5, [4, 1]],
    ['v4R2', 9, [4, 4, 1]],
    ['v4R2', 13, [4, 4, 4, 1]],
    ['W5', 17, [17]],
    ['W5', 255, [255]],
    ['W5', 256, [255, 1]],
    ['telegram', 256, [255, 1]],
  ])('%s with %i NFTs validates and submits the same batches', async (version, count, batchSizes) => {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue(makeAccount(version));
    const options = makeOptions(count);
    const draft = await checkNftTransferDraft(options);
    const result = await submitNftTransfers(options);

    const checkedBatchSizes = jest.mocked(checkMultiTransactionDraft).mock.calls.map(([, messages]) => messages.length);
    const sentBatchSizes = jest.mocked(submitMultiTransferWithMfa).mock.calls.map(([{ messages }]) => messages.length);
    expect(checkedBatchSizes).toEqual(batchSizes);
    expect(sentBatchSizes).toEqual(batchSizes);
    let previousCost = 0n;
    expect(jest.mocked(checkMultiTransactionDraft).mock.calls.map((args) => args[4])).toEqual(batchSizes.map((size) => {
      const cost = previousCost;
      previousCost += BigInt(size) * 100_000_000n + 100n + BigInt(size) * 10n;
      return cost;
    }));
    const networkFee = BigInt(batchSizes.length) * 100n + BigInt(count) * 10n;
    expect(draft.explainedFee?.fullFee?.nativeSum).toBe(networkFee + BigInt(count) * 100_000_000n);
    expect(draft.explainedFee?.realFee?.nativeSum).toBe(networkFee + BigInt(count) * 5_000_000n);
    expect(result).not.toHaveProperty('error');
    expect(result).toHaveProperty('transfers', options.nfts.map((nft, index) => ({
      toAddress: nft.address,
      msgHashNormalized: `hash-${Math.floor(index / batchSizes[0]) + 1}`,
    })));
    expect(getSigner).toHaveBeenCalledTimes(1);
    expect(jest.mocked(submitMultiTransferWithMfa).mock.calls.every(([{ signer }]) => signer === SIGNER)).toBe(true);
    expect(jest.mocked(submitMultiTransferWithMfa).mock.calls.map(([{ previousSeqno }]) => previousSeqno))
      .toEqual(batchSizes.map((_, index) => (index ? 40 + index : undefined)));
  });

  it.each<[ApiTonWalletVersion, number, string]>([
    ['v4R2', 5, 'Gift 🎁'],
    ['v4R2', 5, 'Подарок 🎁 '.repeat(30)],
    ['W5', 256, 'Gift 🎁'],
    ['W5', 256, 'Подарок 🎁 '.repeat(30)],
  ])('preserves comments on every NFT in %s batches', async (version, count, comment) => {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue(makeAccount(version));
    const options = { ...makeOptions(count), comment };

    await checkNftTransferDraft(options);
    await submitNftTransfers(options);

    const checkedMessages = jest.mocked(checkMultiTransactionDraft).mock.calls.flatMap(([, messages]) => messages);
    const sentMessages = jest.mocked(submitMultiTransferWithMfa).mock.calls.flatMap(([{ messages }]) => messages);
    for (const messages of [checkedMessages, sentMessages]) {
      expect(messages).toHaveLength(count);
      for (const { payload } of messages) {
        const slice = Cell.fromBoc((payload as Cell).toBoc())[0].beginParse();
        expect(slice.loadUint(32)).toBe(0x5fcc3d14);
        slice.loadUintBig(64);
        expect(slice.loadAddress().toString()).toBe(options.toAddress);
        expect(slice.loadAddress().toString()).toBe(ADDRESS);
        expect(slice.loadBit()).toBe(false);
        expect(slice.loadCoins()).toBeGreaterThan(0n);
        const forwardPayload = slice.loadBit() ? slice.loadRef().beginParse() : slice;
        expect(forwardPayload.loadUint(32)).toBe(0);
        expect(forwardPayload.loadStringTail()).toBe(comment);
      }
    }
  });

  it('validates an NFT in the final batch instead of extrapolating the first batch', async () => {
    jest.mocked(checkMultiTransactionDraft)
      .mockResolvedValueOnce({ emulation: { isFallback: true, networkFee: 140n } })
      .mockResolvedValueOnce({ error: ApiTransactionDraftError.InvalidToAddress });

    const result = await checkNftTransferDraft(makeOptions(5));

    expect(result.error).toBe(ApiTransactionDraftError.InvalidToAddress);
    expect(result.explainedFee).toBeUndefined();
  });

  it('preserves fee estimates when a batch has insufficient balance', async () => {
    jest.mocked(checkMultiTransactionDraft).mockResolvedValueOnce({
      error: ApiTransactionDraftError.InsufficientBalance,
      emulation: { isFallback: true, networkFee: 140n },
    });

    const result = await checkNftTransferDraft(makeOptions(5));

    expect(result.error).toBe(ApiTransactionDraftError.InsufficientBalance);
    expect(result.explainedFee?.fullFee?.nativeSum).toBe(500_000_250n);
  });

  it.each([false, true])('stops after a later batch fails (throws: %s) and retains sent hashes', async (doesThrow) => {
    jest.mocked(submitMultiTransferWithMfa).mockResolvedValueOnce({
      messages: makeOptions(4).nfts.map((nft) => ({ toAddress: nft.address, amount: 100_000_000n })),
      seqno: 41, msgHashNormalized: 'first-hash', msgHash: 'hash', amount: '0', boc: 'boc',
    });
    if (doesThrow) {
      jest.mocked(submitMultiTransferWithMfa).mockRejectedValueOnce(new Error('Connection lost'));
    } else {
      jest.mocked(submitMultiTransferWithMfa).mockResolvedValueOnce({ error: ApiTransactionError.UnsuccesfulTransfer });
    }

    const result = await submitNftTransfers(makeOptions(9));

    expect(submitMultiTransferWithMfa).toHaveBeenCalledTimes(2);
    expect(result).toEqual({
      error: ApiTransactionError.UnsuccesfulTransfer,
      transfers: makeOptions(4).nfts.map((nft) => ({ toAddress: nft.address, msgHashNormalized: 'first-hash' })),
    });
  });

  it('keeps the MFA limit at four and rejects larger requests before signing or emulation', async () => {
    const account = makeAccount('W5');
    account.byChain.ton.mfa = { address: ADDRESS } as NonNullable<typeof account.byChain.ton.mfa>;
    jest.mocked(fetchStoredChainAccount).mockResolvedValue(account);

    const draft = await checkNftTransferDraft(makeOptions(5));
    expect(draft).toHaveProperty('error', ApiTransactionDraftError.MfaNftBatchLimit);
    expect(await submitNftTransfers(makeOptions(5))).toEqual({ error: ApiTransactionDraftError.MfaNftBatchLimit });
    expect(checkMultiTransactionDraft).not.toHaveBeenCalled();
    expect(getSigner).not.toHaveBeenCalled();
  });

  it('retains single-NFT Ledger transactions', async () => {
    const account = { ...makeAccount(), type: 'ledger' } as ApiAccountWithChain<'ton'>;
    jest.mocked(fetchStoredChainAccount).mockResolvedValue(account);

    await checkNftTransferDraft(makeOptions(2));
    await submitNftTransfers(makeOptions(2));

    expect(jest.mocked(checkMultiTransactionDraft).mock.calls.map(([, messages]) => messages.length)).toEqual([1, 1]);
    expect(jest.mocked(submitMultiTransferWithMfa).mock.calls.map(([{ messages }]) => messages.length)).toEqual([1, 1]);
  });

  it('rejects empty selections before fee calculation or signing', async () => {
    expect(await checkNftTransferDraft(makeOptions(0))).toHaveProperty('error', ApiCommonError.Unexpected);
    expect(await submitNftTransfers(makeOptions(0))).toEqual({ error: ApiCommonError.Unexpected });
    expect(checkMultiTransactionDraft).not.toHaveBeenCalled();
    expect(getSigner).not.toHaveBeenCalled();
  });
});
