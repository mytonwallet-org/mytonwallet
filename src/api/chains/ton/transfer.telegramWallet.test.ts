import type { ApiAccountWithChain } from '../../types';
import { ApiTransactionError } from '../../types';

import { getSigner } from './util/signer';
import { fetchStoredChainAccount, updateStoredAccount } from '../../common/accounts';
import { withoutTransferConcurrency } from '../../common/preventTransferConcurrency';
import { signTransfers } from './transfer';
import { getTonWallet, getWalletSeqno } from './wallet';

jest.mock('../../common/accounts', () => ({
  fetchStoredChainAccount: jest.fn(),
  updateStoredAccount: jest.fn(),
}));

jest.mock('../../common/preventTransferConcurrency', () => ({
  withoutTransferConcurrency: jest.fn((_network, _address, fn) => fn()),
}));

jest.mock('./util/signer', () => ({
  getSigner: jest.fn(),
}));

jest.mock('./wallet', () => ({
  ...jest.requireActual('./wallet'),
  getTonWallet: jest.fn(),
  getWalletSeqno: jest.fn(),
}));

const TELEGRAM_ACCOUNT: ApiAccountWithChain<'ton'> = {
  type: 'bip39',
  byChain: {
    ton: {
      address: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
      publicKey: '1a4e0b6f3d8c2957e4b1a0d6c3f89e5271b4a8d0e6c2f39571a4e0b6f3d8c295',
      version: 'telegram',
      index: 0,
    },
  },
};

describe('Telegram Wallet signing degradation', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.mocked(fetchStoredChainAccount).mockResolvedValue(TELEGRAM_ACCOUNT);
    jest.mocked(getTonWallet).mockReturnValue({} as ReturnType<typeof getTonWallet>);
    jest.mocked(getWalletSeqno).mockResolvedValue(7);
    jest.mocked(updateStoredAccount).mockResolvedValue(undefined);
    jest.mocked(getSigner).mockReturnValue({
      isMock: true,
      signTransactions: jest.fn().mockResolvedValue({
        error: ApiTransactionError.TelegramWalletPublicKeyMismatch,
      }),
    } as unknown as ReturnType<typeof getSigner>);
  });

  it('degrades an imported Telegram Wallet to view-only when the signing key changed on-chain', async () => {
    await expect(signTransfers('0-mainnet', [{
      toAddress: TELEGRAM_ACCOUNT.byChain.ton.address,
      amount: 1n,
    }], 'enclave-token')).resolves.toEqual({
      error: ApiTransactionError.TelegramWalletPublicKeyMismatch,
    });

    expect(withoutTransferConcurrency).toHaveBeenCalled();
    expect(updateStoredAccount).toHaveBeenCalledWith('0-mainnet', { type: 'view' });
  });
});
