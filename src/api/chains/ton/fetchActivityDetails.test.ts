import type { ParsedTrace } from './types';

import { TONCOIN } from '../../../config';
import { buildTxId } from '../../../util/activities';
import { logDebugError } from '../../../util/logs';
import { pause } from '../../../util/schedulers';
import { makeMockTransactionActivity } from '../../../../tests/mocks';
import { fetchStoredWallet } from '../../common/accounts';
import { fetchActivityDetails } from './activities';
import { fetchAndParseTrace } from './traces';

jest.mock('../../../util/logs');
jest.mock('../../../util/schedulers', () => ({
  ...jest.requireActual('../../../util/schedulers'),
  pause: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../common/accounts', () => ({
  fetchStoredWallet: jest.fn(),
}));
jest.mock('./traces', () => ({
  fetchAndParseTrace: jest.fn(),
}));

describe('fetchActivityDetails', () => {
  afterEach(() => {
    (fetchStoredWallet as jest.Mock).mockReset();
    (fetchAndParseTrace as jest.Mock).mockReset();
    (pause as jest.Mock).mockClear();
    (logDebugError as jest.Mock).mockReset();
  });

  it('stops retrying after the first successful trace parse', async () => {
    const actionId = 'qQsBZCbfq9e6Lq6VWAdwwmXuRthRZ9WUFMVhdatSpNU=';
    const activity = makeMockTransactionActivity({
      id: buildTxId('tNmaapaq05D9HndDF376vM5Scr+DP+phX39jQMTvp70=', `68322322000002-${actionId}`),
      externalMsgHashNorm: 'normalized-external-hash',
      fee: 0n,
      fromAddress: 'wallet-address',
      toAddress: 'recipient-address',
      isIncoming: false,
      normalizedAddress: 'recipient-address',
      amount: -1n,
      slug: TONCOIN.slug,
      shouldLoadDetails: true,
      status: 'completed',
    });

    const parsedTrace = {
      actions: [],
      traceDetail: {} as any,
      addressBook: {},
      traceOutputs: [{
        hashes: new Set<string>(),
        sent: 0n,
        received: 0n,
        networkFee: 0n,
        isSuccess: true,
        realFee: 123n,
        excess: 0n,
        walletActions: [{
          action: {
            action_id: actionId,
            details: {},
          } as any,
          activities: [activity],
        }],
      }],
      totalSent: 0n,
      totalReceived: 0n,
      totalNetworkFee: 0n,
    } satisfies ParsedTrace;

    (fetchStoredWallet as jest.Mock).mockResolvedValue({ address: 'wallet-address' });
    (fetchAndParseTrace as jest.Mock).mockResolvedValue(parsedTrace);

    const result = await fetchActivityDetails('1-mainnet', activity);

    expect(fetchAndParseTrace).toHaveBeenCalledTimes(1);
    expect(pause).not.toHaveBeenCalled();
    expect(logDebugError).not.toHaveBeenCalledWith('Trace unavailable for activity', activity.id);
    expect(result).toEqual({
      ...activity,
      fee: 123n,
      shouldLoadDetails: undefined,
    });
  });
});
