import type { ApiTransactionActivity } from '../../types';
import type { EmulationResponse } from './toncenter/emulation';

import { parseEmulation } from './emulation';

describe('parseEmulation', () => {
  // How to get the input data:
  // 1. Open a transaction confirmation modal in the app (TON Connect or send form),
  // 2. Get the emulation JSON from the `/api/emulate/v1/emulateTrace` response in the Network tab of the DevTools.

  const testCases: {
    name: string;
    walletAddress: string;
    emulationResponse: EmulationResponse;
    expectedExcess: bigint;
    expectedRealFee: bigint;
  }[] = [
    {
      name: 'contract call with excess accounted',
      walletAddress: 'UQAXt7U0eHXLZhcngXzALAryEm_dtkTevqFfa2zc7UfcciR8',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      emulationResponse: require('./testData/isExcessAccountedEmulateTraceResponse.json'),
      expectedExcess: 220241200n,
      expectedRealFee: 9002187n,
    },
    {
      name: 'push transfer',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      emulationResponse: require('./testData/pushTransferEmulateTraceResponse.json'),
      expectedExcess: 14810689n,
      expectedRealFee: 87414171n,
    },
  ];

  test.each(testCases)('$name', (params) => {
    const {
      walletAddress,
      emulationResponse,
      expectedExcess,
      expectedRealFee,
    } = params;

    const result = parseEmulation('mainnet', walletAddress, emulationResponse, {});

    const excess = (result.activities.find((activity) => (
      activity.kind === 'transaction' && activity.type === 'excess'
    )) as ApiTransactionActivity)?.amount;

    expect(excess).toBe(expectedExcess);
    expect(result.realFee).toBe(expectedRealFee);
  });
});
