import type { ApiSwapActivity } from '../../types';

import { fetchJson } from '../../../util/fetch';
import { fetchActivityDetails } from './activities';

jest.mock('../../../util/fetch', () => ({
  ...jest.requireActual('../../../util/fetch'),
  fetchJson: jest.fn(),
}));
jest.mock('../../environment', () => ({
  getEnvironment: () => ({ apiHeaders: {} }),
}));

const SIGNATURE = '361A9zqLCccnU5BSumtgqTwbwt9f5LHYMckGQwkVwkGZRfqXBPiKydYJ3v47EJz8vZQcKoVPTbSRuMVMae5CzEVB';

const swapRow: ApiSwapActivity = {
  id: '2600000::backend-swap',
  kind: 'swap',
  fromAddress: 'BMmB77RxSM9NxhijYxe8Vco8UTb8QRD8xWv5HTNmnuHa',
  timestamp: 1793708030000,
  from: 'solana-epjfwdd5au',
  fromAmount: '1',
  to: 'solana-xsqe9crrpz',
  toAmount: '0.00368102',
  networkFee: '0',
  swapFee: '0.011008',
  status: 'completed',
  hashes: [SIGNATURE],
  transactionIds: {},
  externalMsgHashNorm: SIGNATURE,
  shouldLoadDetails: true,
};

describe('fetchActivityDetails', () => {
  afterEach(() => {
    jest.mocked(fetchJson).mockReset();
  });

  it('takes the network fee of a swap row from its transaction', async () => {
    jest.mocked(fetchJson).mockResolvedValueOnce([{ signature: SIGNATURE, fee: 5020 }]);

    const detailed = await fetchActivityDetails('0-mainnet', swapRow);

    expect(detailed).toEqual({ ...swapRow, networkFee: '0.00000502', shouldLoadDetails: undefined });
    expect(jest.mocked(fetchJson).mock.calls[0][2]?.body).toBe(JSON.stringify({ transactions: [SIGNATURE] }));
  });

  it('adds nothing when the transaction is not found', async () => {
    jest.mocked(fetchJson).mockResolvedValueOnce([]);

    await expect(fetchActivityDetails('0-mainnet', swapRow)).resolves.toBeUndefined();
  });

  it('adds nothing when the transaction request fails', async () => {
    jest.mocked(fetchJson).mockRejectedValueOnce(new Error('HTTP Error 429'));

    await expect(fetchActivityDetails('0-mainnet', swapRow)).resolves.toBeUndefined();
  });

  it('rejects when the caller aborts the request', async () => {
    const controller = new AbortController();
    jest.mocked(fetchJson).mockImplementationOnce(() => {
      controller.abort();
      return Promise.reject(new Error('Aborted'));
    });

    await expect(fetchActivityDetails('0-mainnet', swapRow, controller.signal)).rejects.toBeDefined();
  });

  it('does not look up a swap sent from another chain', async () => {
    const swapFromBase = { ...swapRow, from: 'base-0x833589fc', externalMsgHashNorm: '0xabc' };

    await expect(fetchActivityDetails('0-mainnet', swapFromBase)).resolves.toBeUndefined();
    expect(fetchJson).not.toHaveBeenCalled();
  });

  it('does not look up a swap that waits for no details', async () => {
    const chainSwap = { ...swapRow, id: SIGNATURE, networkFee: '0.00000502', shouldLoadDetails: undefined };

    await expect(fetchActivityDetails('0-mainnet', chainSwap)).resolves.toBeUndefined();
    expect(fetchJson).not.toHaveBeenCalled();
  });
});
