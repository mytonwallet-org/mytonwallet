import { fetchJson } from '../../../util/fetch';
import { getEvmProvider } from './util/client';
import { inactiveWallets } from './util/inactiveWallets';
import { getIsWalletActive } from './wallet';

jest.mock('../../../util/fetch', () => ({
  ...jest.requireActual('../../../util/fetch'),
  fetchJson: jest.fn(),
}));

jest.mock('./util/client', () => ({
  getEvmProvider: jest.fn(),
}));

const mockedFetchJson = jest.mocked(fetchJson);
const mockedGetEvmProvider = jest.mocked(getEvmProvider);

const getBalance = jest.fn();
const getTransactionCount = jest.fn();

function noTransfers() {
  mockedFetchJson.mockResolvedValue({ result: { transfers: [] } } as never);
}

describe('getIsWalletActive', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    inactiveWallets.reset();
    mockedGetEvmProvider.mockReturnValue({ getBalance, getTransactionCount } as never);
    getBalance.mockResolvedValue(0n);
    getTransactionCount.mockResolvedValue(0);
  });

  it('answers no and remembers it when the address has neither balance nor transfers', async () => {
    noTransfers();

    await expect(getIsWalletActive('mainnet', 'base', '0xa1')).resolves.toBe(false);
    expect(inactiveWallets.has('mainnet', 'base', '0xa1')).toBe(true);
  });

  it('skips the transfer probe for an address already known to be inactive', async () => {
    noTransfers();

    await getIsWalletActive('mainnet', 'base', '0xa2');
    expect(mockedFetchJson).toHaveBeenCalledTimes(1);

    await expect(getIsWalletActive('mainnet', 'base', '0xa2')).resolves.toBe(false);
    expect(mockedFetchJson).toHaveBeenCalledTimes(1);
  });

  // The balance read has to run before the registry is consulted. `BalanceStream` asks this once
  // per stream and keeps the answer for the stream's lifetime, so an address funded after a
  // negative verdict must be recognised on the next check rather than whenever the TTL lapses.
  it('recognises funds arriving on an address already marked inactive', async () => {
    noTransfers();
    await getIsWalletActive('mainnet', 'base', '0xa3');
    expect(inactiveWallets.has('mainnet', 'base', '0xa3')).toBe(true);

    getBalance.mockResolvedValue(1n);

    await expect(getIsWalletActive('mainnet', 'base', '0xa3')).resolves.toBe(true);
    expect(inactiveWallets.has('mainnet', 'base', '0xa3')).toBe(false);
  });

  // The case a balance read alone cannot see: an address that received funds and spent them all
  // reads as empty, and the inbound probe misses it too because `internal` is not among the
  // categories asked for outside Ethereum. Its nonce is what survives.
  it('answers yes for an address that spent everything it received', async () => {
    noTransfers();
    getTransactionCount.mockResolvedValue(1);

    await expect(getIsWalletActive('mainnet', 'base', '0xb1')).resolves.toBe(true);
    // The nonce settles it before the expensive probe, so that address never pays for one.
    expect(mockedFetchJson).not.toHaveBeenCalled();
  });

  it('answers yes on a transfer even with a zero balance', async () => {
    mockedFetchJson.mockResolvedValue({ result: { transfers: [{ hash: '0x1' }] } } as never);

    await expect(getIsWalletActive('mainnet', 'base', '0xa4')).resolves.toBe(true);
    expect(inactiveWallets.has('mainnet', 'base', '0xa4')).toBe(false);
  });
});
