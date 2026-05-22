import { Address, beginCell } from '@ton/core';

import type { TonClient } from './TonClient';
import type { TonWallet } from './tonCore';

import { sendExternal } from './sendExternal';

describe('sendExternal', () => {
  it('sends an accepted BOC only once', async () => {
    const client = {
      sendFile: jest.fn()
        .mockResolvedValueOnce(undefined)
        .mockRejectedValue(new Error('Too old seqno')),
    } as unknown as TonClient;
    const wallet = {
      address: Address.parseRaw(`0:${'0'.repeat(64)}`),
    } as TonWallet;
    const message = beginCell().storeUint(0, 32).endCell();

    await sendExternal(client, wallet, message, undefined, true);

    expect(client.sendFile).toHaveBeenCalledTimes(1);
  });
});
