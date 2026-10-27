import { Address, beginCell, Cell, loadMessage } from '@ton/core';

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

  it('asks the chain for the deployment state when the caller does not pass it', async () => {
    const client = {
      isContractDeployed: jest.fn().mockResolvedValue(false),
      sendFile: jest.fn().mockResolvedValue(undefined),
    } as unknown as TonClient;
    const wallet = {
      address: Address.parseRaw(`0:${'0'.repeat(64)}`),
      init: {
        code: beginCell().storeUint(1, 32).endCell(),
        data: beginCell().storeUint(2, 32).endCell(),
      },
    } as TonWallet;
    const message = beginCell().storeUint(0, 32).endCell();

    const { boc } = await sendExternal(client, wallet, message);

    expect(client.isContractDeployed).toHaveBeenCalledTimes(1);
    expect(loadMessage(Cell.fromBase64(boc).beginParse()).init).toBeDefined();
  });
});
