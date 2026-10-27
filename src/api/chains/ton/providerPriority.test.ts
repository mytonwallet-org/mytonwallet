import { Address, beginCell } from '@ton/core';

import type { FetchDemand } from '../../../util/fetchDemand';

import { createUrgentFetchDemand } from '../../../util/fetchDemand';
import { resetThrottledProviderFetchers } from '../../../util/ThrottledFetcher';
import { getTokenBalance, getTonClient, resolveTokenWallet } from './util/tonCore';
import { fetchEmulateTrace } from './toncenter/emulation';
import { callToncenterV3 } from './toncenter/other';
import { getWalletInfo } from './wallet';

jest.mock('../../environment', () => ({
  getEnvironment: () => ({
    apiHeaders: undefined,
    byNetwork: { mainnet: {}, testnet: {} },
  }),
}));

const NETWORK = 'mainnet';
const WALLET_ADDRESS = Address.parse(`0:${'1'.repeat(64)}`).toString();
const TOKEN_WALLET_ADDRESS = Address.parse(`0:${'2'.repeat(64)}`).toString();
const OWNER_ADDRESS = Address.parse(`0:${'3'.repeat(64)}`);
const MINTER_ADDRESS = Address.parse(`0:${'4'.repeat(64)}`);

function toStackSlice(address: Address) {
  return ['slice', { bytes: beginCell().storeAddress(address).endCell().toBoc().toString('base64') }];
}

/** Names a provider request the way the test expects to see it: the v2 method or get method, or the v3 path */
function describeRequest(input: string, init?: RequestInit) {
  const url = new URL(input);
  if (url.pathname.endsWith('/jsonRPC')) {
    const { method, params } = JSON.parse(init!.body as string);
    return method === 'runGetMethod' ? `v2 ${params.method}` : `v2 ${method}`;
  }

  return url.pathname.replace(/^\/api/, '');
}

function respondTo(name: string) {
  switch (name) {
    case 'v2 getAddressInformation':
      return {
        result: {
          balance: '0',
          state: 'active',
          code: '',
          data: '',
          last_transaction_id: { lt: '1', hash: '' },
        },
      };
    case 'v2 get_wallet_data':
      return {
        result: {
          exit_code: 0,
          gas_used: 0,
          stack: [
            ['num', '0x1'],
            ['cell', { bytes: beginCell().storeAddress(OWNER_ADDRESS).endCell().toBoc().toString('base64') }],
            ['cell', { bytes: beginCell().storeAddress(MINTER_ADDRESS).endCell().toBoc().toString('base64') }],
            ['cell', { bytes: beginCell().endCell().toBoc().toString('base64') }],
          ],
        },
      };
    case 'v2 get_wallet_address':
      return {
        result: {
          exit_code: 0,
          gas_used: 0,
          stack: [toStackSlice(Address.parse(TOKEN_WALLET_ADDRESS))],
        },
      };
    case '/v3/walletStates':
      return { wallets: [], address_book: {} };
    default:
      return {};
  }
}

describe('provider request priority', () => {
  let requests: string[];

  beforeEach(() => {
    jest.useFakeTimers();
    resetThrottledProviderFetchers();
    requests = [];
    global.fetch = jest.fn((input: string, init?: RequestInit) => {
      const name = describeRequest(input, init);
      requests.push(name);
      return Promise.resolve({
        ok: true,
        status: 200,
        headers: { get: () => undefined },
        json: () => Promise.resolve(respondTo(name)),
      } as unknown as Response);
    }) as unknown as typeof fetch;
  });

  afterEach(() => {
    jest.useRealTimers();
    resetThrottledProviderFetchers();
  });

  function queueBackground(index: number) {
    return callToncenterV3(NETWORK, `/background-${index}`);
  }

  it('sends urgent requests through every provider wrapper ahead of queued background ones', async () => {
    const urgent = createUrgentFetchDemand();

    await queueBackground(0);
    const background = [queueBackground(1), queueBackground(2), queueBackground(3)];
    const urgentCalls = [
      getWalletInfo(NETWORK, WALLET_ADDRESS, undefined, urgent),
      getTonClient(NETWORK, urgent).getAddressInfo(WALLET_ADDRESS),
      fetchEmulateTrace(NETWORK, 'boc', undefined, urgent),
      // A contract opened through a client bound to the demand: its state, then its get method
      getTokenBalance(NETWORK, TOKEN_WALLET_ADDRESS, urgent),
    ];

    await jest.advanceTimersByTimeAsync(1000);
    await Promise.all([...background, ...urgentCalls]);

    expect(requests).toEqual([
      '/v3/background-0',
      '/v3/walletStates',
      'v2 getAddressInformation',
      '/emulate/v1/emulateTrace',
      'v2 getAddressInformation',
      'v2 get_wallet_data',
      '/v3/background-1',
      '/v3/background-2',
      '/v3/background-3',
    ]);
  });

  it('moves both requests of a token wallet lookup started by polling ahead for an urgent caller', async () => {
    const urgent: FetchDemand = createUrgentFetchDemand();

    await queueBackground(0);
    const background = [queueBackground(1), queueBackground(2)];
    const fromPolling = resolveTokenWallet(NETWORK, TOKEN_WALLET_ADDRESS);
    background.push(queueBackground(3));
    const fromDapp = resolveTokenWallet(NETWORK, TOKEN_WALLET_ADDRESS, urgent);

    await jest.advanceTimersByTimeAsync(1000);
    const [polled, requested] = await Promise.all([fromPolling, fromDapp, ...background]);

    expect(polled).toEqual(requested);
    expect(requests).toEqual([
      '/v3/background-0',
      'v2 get_wallet_data',
      'v2 get_wallet_address',
      '/v3/background-1',
      '/v3/background-2',
      '/v3/background-3',
    ]);
  });
});
