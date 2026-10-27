import '../../../util/bigintPatch';

import { Address, beginCell } from '@ton/core';

import { ApiTransactionDraftError } from '../../types';

import { getSigner } from './util/signer';
import { fetchStoredChainAccount } from '../../common/accounts';
import { emulateTransaction } from './emulation';
import { checkMultiTransactionDraft } from './transfer';
import { getWalletInfo } from './wallet';

jest.mock('../../common/accounts', () => ({ fetchStoredChainAccount: jest.fn() }));
jest.mock('./util/signer', () => ({ getSigner: jest.fn() }));
jest.mock('./wallet', () => ({
  ...jest.requireActual('./wallet'),
  getWalletInfo: jest.fn(),
}));
jest.mock('./emulation', () => ({ emulateTransaction: jest.fn() }));

describe('multi-transaction draft affordability', () => {
  const address = new Address(0, Buffer.alloc(32, 1)).toString();
  const messages = [{ toAddress: address, amount: 100_000_000n }];

  beforeEach(() => {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue({
      type: 'ton',
      byChain: { ton: { address, version: 'v4R2', publicKey: '00'.repeat(32), index: 0 } },
    });
    jest.mocked(getSigner).mockReturnValue({
      isMock: true,
      signTransactions: jest.fn().mockResolvedValue([beginCell().endCell()]),
    } as unknown as ReturnType<typeof getSigner>);
    jest.mocked(getWalletInfo).mockResolvedValue({
      address, balance: 500_000_000n, seqno: 5, isInitialized: true,
    });
    jest.mocked(emulateTransaction).mockResolvedValue({
      networkFee: 1_000_000n,
    } as Awaited<ReturnType<typeof emulateTransaction>>);
  });

  it('rejects combined costs that exceed the balance even when the current batch fits', async () => {
    const single = await checkMultiTransactionDraft('0-mainnet', messages);
    expect(single).not.toHaveProperty('error');

    const combined = await checkMultiTransactionDraft('0-mainnet', messages, undefined, undefined, 400_000_000n);
    expect(combined).toHaveProperty('error', ApiTransactionDraftError.InsufficientBalance);
    expect(combined.emulation?.networkFee).toBe(single.emulation?.networkFee);
  });

  it('accepts the exact total balance including prior batch network fees', async () => {
    const single = await checkMultiTransactionDraft('0-mainnet', messages);
    const previousCost = 400_000_000n - single.emulation!.networkFee;
    const combined = await checkMultiTransactionDraft('0-mainnet', messages, undefined, undefined, previousCost);
    expect(combined).not.toHaveProperty('error');
  });
});
