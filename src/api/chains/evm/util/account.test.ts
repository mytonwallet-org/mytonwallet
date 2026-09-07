import type { ApiAccountAny } from '../../../types';

import { fetchStoredAccount } from '../../../common/accounts';
import { fetchEvmWallet } from './account';

jest.mock('../../../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
}));

const ACCOUNT_ID = '0-mainnet';
const ADDRESS = '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3';

const mockedFetchStoredAccount = jest.mocked(fetchStoredAccount);

function mockAccount(byChain: ApiAccountAny['byChain']) {
  mockedFetchStoredAccount.mockResolvedValue({ type: 'bip39', byChain } as ApiAccountAny);
}

describe('fetchEvmWallet', () => {
  beforeEach(() => {
    mockedFetchStoredAccount.mockReset();
  });

  it('returns the wallet of the requested chain', async () => {
    mockAccount({
      ethereum: { address: '0xethereum', index: 0 },
      base: { address: ADDRESS, index: 0 },
    });

    await expect(fetchEvmWallet(ACCOUNT_ID, 'base')).resolves.toEqual({ address: ADDRESS, index: 0 });
  });

  // An account created before a chain was added to the app has no entry for it, and the chains of
  // one standard share a wallet, so the standard chain answers for it
  it('falls back to the standard chain when the account has no entry for the chain', async () => {
    mockAccount({ ethereum: { address: ADDRESS, index: 0 } });

    await expect(fetchEvmWallet(ACCOUNT_ID, 'robinhood')).resolves.toEqual({ address: ADDRESS, index: 0 });
  });

  it('throws when the account has no EVM wallet at all', async () => {
    mockAccount({ ton: { address: 'UQ...', index: 0, type: 'ton', version: 'W5', isInitialized: true } as any });

    await expect(fetchEvmWallet(ACCOUNT_ID, 'robinhood')).rejects.toThrow('robinhood wallet missing');
  });
});
