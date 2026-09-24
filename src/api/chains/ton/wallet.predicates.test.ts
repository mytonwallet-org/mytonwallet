import { beginCell } from '@ton/core';

const mockGetAddressInfo = jest.fn();
const mockGetWalletInfos = jest.fn();

jest.mock('./util/tonCore', () => ({
  ...jest.requireActual('./util/tonCore'),
  getTonClient: () => ({ getAddressInfo: mockGetAddressInfo }),
}));

jest.mock('./toncenter', () => ({ getWalletInfos: (...args: unknown[]) => mockGetWalletInfos(...args) }));

// Only the case below needs this: no code can be written whose hash matches a contract the app already knows, so the
// lookup is asked to answer for one. Every other case goes through the real table.
const mockFindKnownContract = jest.fn();
jest.mock('./util/knownContracts', () => ({
  findKnownContract: (...args: unknown[]) => mockFindKnownContract(...args),
}));

const { findKnownContract } = jest.requireActual<typeof import('./util/knownContracts')>('./util/knownContracts');

import { fetchIsActiveNonWalletContract, fetchIsAddressInitialized } from './wallet';

const ADDRESS = 'EQDlXmO4ULcbj_WtROG4JxI3r68xkAsrbUEjNwe7WFuAkcRZ';

// The trampoline every Telegram wallet account holds. Its logic lives in the blockchain config, so the indexer has
// no wallet type for it and reports the account as an ordinary contract.
const TELEGRAM_CODE = 'te6cckEBAQEAGgAAMP8AIJgh10mDCLnyQN+Ahfgz0O0eIO1T2WlCfjk=';
const UNKNOWN_CODE = beginCell().storeUint(0xdeadbeef, 32).endCell().toBoc().toString('base64');

describe('fetchIsActiveNonWalletContract', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockFindKnownContract.mockImplementation(findKnownContract);
  });

  it('says no for a wallet the indexer cannot name', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: TELEGRAM_CODE, state: 'active' });

    // The NFT history calls a transfer to an active non-wallet contract a sale, so a wallet answering yes here is
    // reported to the sender as putting the NFT up for sale.
    expect(await fetchIsActiveNonWalletContract('mainnet', ADDRESS)).toBe(false);
  });

  it('says yes for an active contract that is not a wallet', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: UNKNOWN_CODE, state: 'active' });

    expect(await fetchIsActiveNonWalletContract('mainnet', ADDRESS)).toBe(true);
  });

  it('asks what the contract is, not merely whether it is known', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: UNKNOWN_CODE, state: 'active' });
    // A marketplace pTON wallet: the app knows this code and does not count it as a wallet
    mockFindKnownContract.mockReturnValue({ name: 'stonPtonWallet' });

    expect(await fetchIsActiveNonWalletContract('mainnet', ADDRESS)).toBe(true);
  });

  it('answers nothing for an address that holds no contract', async () => {
    mockGetAddressInfo.mockResolvedValue({ code: '', state: 'uninitialized' });

    // Undefined keeps the answer out of the cache, so it is asked again once something is deployed there
    expect(await fetchIsActiveNonWalletContract('mainnet', ADDRESS)).toBeUndefined();
  });
});

describe('fetchIsAddressInitialized', () => {
  beforeEach(() => jest.clearAllMocks());

  it('reports what the indexer says about the address', async () => {
    mockGetWalletInfos.mockResolvedValue({ [ADDRESS]: { isInitialized: true } });
    expect(await fetchIsAddressInitialized('mainnet', ADDRESS)).toBe(true);

    mockGetWalletInfos.mockResolvedValue({ [ADDRESS]: { isInitialized: false } });
    expect(await fetchIsAddressInitialized('mainnet', ADDRESS)).toBe(false);
  });
});
