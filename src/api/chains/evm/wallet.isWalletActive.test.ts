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

  it('answers no on mainnet without the nonce and without remembering the verdict', async () => {
    noTransfers();

    await expect(getIsWalletActive('mainnet', 'base', '0xa1')).resolves.toBe(false);
    expect(inactiveWallets.has('mainnet', 'base', '0xa1')).toBe(false);
    // The gateway answering the probe consults the nonce itself, so reading it here pays twice.
    expect(getTransactionCount).not.toHaveBeenCalled();
  });

  // An address that received native funds and spent them all while unwatched reads empty, and only the
  // gateway's nonce check sees it, so an earlier negative verdict must not answer in its place.
  it('asks the gateway again on mainnet after a negative verdict', async () => {
    noTransfers();
    await getIsWalletActive('mainnet', 'base', '0xa2');

    mockedFetchJson.mockResolvedValue({ result: { transfers: [{ hash: '0x1' }] } } as never);

    await expect(getIsWalletActive('mainnet', 'base', '0xa2')).resolves.toBe(true);
    expect(mockedFetchJson).toHaveBeenCalledTimes(2);
  });

  it('asks the gateway on mainnet even when the address is remembered as inactive', async () => {
    noTransfers();
    inactiveWallets.mark('mainnet', 'base', '0xa6');

    await expect(getIsWalletActive('mainnet', 'base', '0xa6')).resolves.toBe(false);
    expect(mockedFetchJson).toHaveBeenCalledTimes(1);
  });

  it('skips the transfer probe on testnet for an address already known to be inactive', async () => {
    noTransfers();

    await getIsWalletActive('testnet', 'base', '0xa5');
    expect(mockedFetchJson).toHaveBeenCalledTimes(1);

    await expect(getIsWalletActive('testnet', 'base', '0xa5')).resolves.toBe(false);
    expect(mockedFetchJson).toHaveBeenCalledTimes(1);
  });

  // The balance read has to run before the remembered verdict is consulted. `BalanceStream` asks this
  // once per stream and keeps the answer for the stream's lifetime, so an address funded after a
  // negative verdict must be recognised on the next check rather than whenever the TTL lapses.
  it('recognises funds arriving on an address already marked inactive', async () => {
    noTransfers();
    await getIsWalletActive('testnet', 'base', '0xa3');
    expect(inactiveWallets.has('testnet', 'base', '0xa3')).toBe(true);

    getBalance.mockResolvedValue(1n);

    await expect(getIsWalletActive('testnet', 'base', '0xa3')).resolves.toBe(true);
    expect(inactiveWallets.has('testnet', 'base', '0xa3')).toBe(false);
  });

  // Testnet has no gateway in front of the probe, and the probe misses `internal` transfers outside
  // Ethereum, so the nonce is the only trace of an address that spent everything it received.
  it('answers yes on testnet for an address that spent everything it received', async () => {
    noTransfers();
    getTransactionCount.mockResolvedValue(1);

    await expect(getIsWalletActive('testnet', 'base', '0xb1')).resolves.toBe(true);
    expect(mockedFetchJson).not.toHaveBeenCalled();
  });

  it('answers yes on a transfer even with a zero balance', async () => {
    mockedFetchJson.mockResolvedValue({ result: { transfers: [{ hash: '0x1' }] } } as never);

    await expect(getIsWalletActive('mainnet', 'base', '0xa4')).resolves.toBe(true);
    expect(inactiveWallets.has('mainnet', 'base', '0xa4')).toBe(false);
  });
});
