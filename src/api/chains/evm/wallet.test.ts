import { Contract } from 'ethers';

import type { EVMChain } from '../../types';
import type { ZerionPosition, ZerionPositionsResponse } from './types';

import { getChainConfig, getChainsByStandard } from '../../../util/chain';
import { fetchWithRetry } from '../../../util/fetch';
import { getEvmProvider } from './util/client';
import { updateTokensFetchedTogether } from '../../common/tokens';
import { getZerionChainByApiChain } from './constants';
import { fetchAccountAssets, fetchCrosschainAccountAssets, getErc20Balance, getWalletBalance } from './wallet';

jest.mock('ethers', () => ({
  ...jest.requireActual('ethers'),
  Contract: jest.fn(),
}));

jest.mock('../../../util/fetch', () => ({
  fetchWithRetry: jest.fn(),
  buildRequestUrl: jest.fn((url: string) => new URL(url)),
}));

jest.mock('./util/client', () => ({
  getEvmProvider: jest.fn(),
}));

jest.mock('../../common/tokens', () => ({
  buildTokenSlug: jest.fn((chain: string, address: string) => `${chain}-${address}`),
  updateTokensFetchedTogether: jest.fn((tokens: { chain: string; slug?: string; tokenAddress?: string }[]) => (
    Promise.resolve(tokens.map((token) => ({
      ...token,
      slug: token.tokenAddress ? `${token.chain}-${token.tokenAddress}` : token.slug,
    })))
  )),
}));

const mockedFetch = jest.mocked(fetchWithRetry);
const mockedGetEvmProvider = jest.mocked(getEvmProvider);
const mockedSend = jest.fn();

beforeEach(() => {
  mockedSend.mockReset().mockRejectedValue(new Error('RPC unavailable'));
  mockedGetEvmProvider.mockReset()
    .mockReturnValue({ send: mockedSend } as unknown as ReturnType<typeof getEvmProvider>);
});

/** The positions fetcher reads the body and the gateway's observation header off one response. */
function positionsResponse(body: ZerionPositionsResponse, snapshotAt?: string, date?: string) {
  const headers: Record<string, string | undefined> = { 'X-Snapshot-At': snapshotAt, Date: date };

  return {
    headers: { get: (name: string) => headers[name] },
    json: () => Promise.resolve(body),
  } as unknown as Response;
}

const NETWORK = 'mainnet';
const ADDRESS_A = '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3';
const ADDRESS_B = '0x1111111111111111111111111111111111111111';
const EVM_CHAINS = getChainsByStandard('ethereum') as EVMChain[];

const EMPTY_RESPONSE: ZerionPositionsResponse = {
  links: { self: 'https://example.com' },
  data: [],
};

/** Creates a manually controllable promise so a fetch can be held in-flight while a second call arrives. */
function createDeferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

describe('fetchAccountAssets in-flight coalescing', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('coalesces two concurrent identical fetches into a single request', async () => {
    const deferred = createDeferred<Response>();
    mockedFetch.mockReturnValue(deferred.promise as unknown as Promise<Response>);

    const sendUpdateTokens = jest.fn();
    const first = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    const second = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);

    deferred.resolve(positionsResponse(EMPTY_RESPONSE));

    const [firstResult, secondResult] = await Promise.all([first, second]);

    expect(mockedFetch).toHaveBeenCalledTimes(1);
    expect(secondResult).toBe(firstResult);
  });

  it('coalesces concurrent fetches for the same address in different casing', async () => {
    const deferred = createDeferred<Response>();
    mockedFetch.mockReturnValue(deferred.promise as unknown as Promise<Response>);

    const sendUpdateTokens = jest.fn();
    const checksummed = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    const lowercased = fetchAccountAssets('bnb', NETWORK, ADDRESS_A.toLowerCase(), sendUpdateTokens);

    deferred.resolve(positionsResponse(EMPTY_RESPONSE));

    const [firstResult, secondResult] = await Promise.all([checksummed, lowercased]);

    expect(mockedFetch).toHaveBeenCalledTimes(1);
    expect(secondResult).toBe(firstResult);
  });

  it('does not coalesce concurrent fetches for different addresses', async () => {
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE));

    const sendUpdateTokens = jest.fn();
    await Promise.all([
      fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens),
      fetchAccountAssets('bnb', NETWORK, ADDRESS_B, sendUpdateTokens),
    ]);

    expect(mockedFetch).toHaveBeenCalledTimes(2);
  });

  it('does not attach a signalled request to the shared UI in-flight request', async () => {
    const uiRequest = createDeferred<Response>();
    const agentRequest = createDeferred<Response>();
    mockedFetch
      .mockReturnValueOnce(uiRequest.promise as unknown as Promise<Response>)
      .mockReturnValueOnce(agentRequest.promise as unknown as Promise<Response>);

    const sendUpdateTokens = jest.fn();
    const uiPromise = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    const controller = new AbortController();
    const agentPromise = fetchAccountAssets(
      'bnb',
      NETWORK,
      ADDRESS_A,
      sendUpdateTokens,
      { signal: controller.signal },
    );

    uiRequest.resolve(positionsResponse(EMPTY_RESPONSE));
    agentRequest.resolve(positionsResponse(EMPTY_RESPONSE));
    await Promise.all([uiPromise, agentPromise]);

    expect(mockedFetch).toHaveBeenCalledTimes(2);
    expect(mockedFetch.mock.calls[0][1]).toBeUndefined();
    expect(mockedFetch.mock.calls[1][1]).toHaveProperty('signal', controller.signal);
  });

  it('re-invokes the request for a new call after the first one settles (not a result cache)', async () => {
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE));

    const sendUpdateTokens = jest.fn();
    await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    expect(mockedFetch).toHaveBeenCalledTimes(1);

    await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    expect(mockedFetch).toHaveBeenCalledTimes(2);
  });

  it('does not coalesce a single-chain ethereum fetch with a cross-chain fetch for the same address', async () => {
    const deferred = createDeferred<Response>();
    mockedFetch.mockReturnValue(deferred.promise as unknown as Promise<Response>);

    const sendUpdateTokens = jest.fn();
    const singleChain = fetchAccountAssets('ethereum', NETWORK, ADDRESS_A, sendUpdateTokens);
    const crossChain = fetchCrosschainAccountAssets(NETWORK, ADDRESS_A, sendUpdateTokens);

    deferred.resolve(positionsResponse(EMPTY_RESPONSE));
    await Promise.all([singleChain, crossChain]);

    expect(mockedFetch).toHaveBeenCalledTimes(2);
  });

  it('clears the key after a rejection so the next call retries', async () => {
    mockedFetch.mockRejectedValueOnce(new Error('network error'));

    const sendUpdateTokens = jest.fn();
    await expect(
      fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens),
    ).rejects.toThrow('network error');
    expect(mockedFetch).toHaveBeenCalledTimes(1);

    mockedFetch.mockResolvedValueOnce(positionsResponse(EMPTY_RESPONSE));
    await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    expect(mockedFetch).toHaveBeenCalledTimes(2);
  });
});

describe('fetchAccountAssets provenance', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // A test that fails mid-way must not leave fake timers behind for the next one.
  afterEach(() => {
    jest.useRealTimers();
  });

  it('reports the instant the gateway observed the page', async () => {
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE, '1787738529000'));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, jest.fn());

    expect(result.asOf).toBe(1787738529000);
  });

  it('reports no instant when the gateway states none', async () => {
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_B, jest.fn());

    expect(result.asOf).toBeUndefined();
    expect(result.blockBySlug).toEqual({});
  });

  it('reports no instant when the stated one sits beyond the tolerated clock skew', async () => {
    const farFuture = String(Date.now() + 60 * 60 * 1000);
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE, farFuture));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, jest.fn());

    expect(result.asOf).toBeUndefined();
  });

  it('reports no instant when the stated one is not a positive number', async () => {
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE, '0'));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_B, jest.fn());

    expect(result.asOf).toBeUndefined();
  });

  it('states the instant on this device\'s clock when the gateway clock runs behind it', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-08-26T12:00:00.000Z'));

    // The gateway is ten minutes behind this device and served a page it observed 30s earlier.
    const gatewayNow = Date.now() - 10 * 60_000;
    mockedFetch.mockResolvedValue(positionsResponse(
      EMPTY_RESPONSE,
      String(gatewayNow - 30_000),
      new Date(gatewayNow).toUTCString(),
    ));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, jest.fn());

    expect(result.asOf).toBe(Date.now() - 30_000);
  });

  it('states the instant on this device\'s clock when the gateway clock runs ahead of it', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-08-26T12:00:00.000Z'));

    // The same page, from a gateway whose clock is an hour ahead: uncorrected it would outrank
    // every socket delta, and the far-future guard would throw the instant away entirely.
    const gatewayNow = Date.now() + 60 * 60_000;
    mockedFetch.mockResolvedValue(positionsResponse(
      EMPTY_RESPONSE,
      String(gatewayNow - 30_000),
      new Date(gatewayNow).toUTCString(),
    ));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_B, jest.fn());

    expect(result.asOf).toBe(Date.now() - 30_000);
  });
});

describe('fetchAccountAssets position blocks', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it.each([false, true])('reports native and token blocks with cross-chain mode %s', async (isCrossChain) => {
    const data = [
      buildPosition('ethereum', 'eth', 100),
      buildPosition('ethereum', 'token', 101, ADDRESS_B),
    ];
    if (isCrossChain) {
      data.push(buildPosition('base', 'eth', 200), buildPosition('base', 'token', 201, ADDRESS_B));
    }
    mockedFetch.mockResolvedValue(positionsResponse({ ...EMPTY_RESPONSE, data }));

    const result = await fetchAccountAssets('ethereum', NETWORK, ADDRESS_A, jest.fn(), { isCrossChain });

    expect(result.blockBySlug).toEqual({
      [getChainConfig('ethereum').nativeToken.slug]: 100,
      [`ethereum-${ADDRESS_B}`]: 101,
      ...(isCrossChain && {
        [getChainConfig('base').nativeToken.slug]: 200,
        [`base-${ADDRESS_B}`]: 201,
      }),
    });
  });

  it.each([0, NaN, '105'])('omits invalid position block %s', async (block) => {
    mockedFetch.mockResolvedValue(positionsResponse({
      ...EMPTY_RESPONSE,
      data: [
        buildPosition('ethereum', 'eth', block as number),
        buildPosition('ethereum', 'token', block as number, ADDRESS_B),
      ],
    }));

    const result = await fetchAccountAssets('ethereum', NETWORK, ADDRESS_A, jest.fn());

    expect(result.blockBySlug).toEqual({});
  });

  it('clears the block when a later position overwrites the same slug without a valid block', async () => {
    const firstPosition = buildPosition('ethereum', 'token', 100, ADDRESS_B);
    const laterPosition = buildPosition('ethereum', 'token', 0, ADDRESS_B);
    laterPosition.attributes.quantity.int = '2000';
    mockedFetch.mockResolvedValue(positionsResponse({
      ...EMPTY_RESPONSE,
      data: [firstPosition, laterPosition],
    }));

    const result = await fetchAccountAssets('ethereum', NETWORK, ADDRESS_A, jest.fn());

    expect(result.balances[`ethereum-${ADDRESS_B}`]).toBe(2000n);
    expect(result.blockBySlug).not.toHaveProperty(`ethereum-${ADDRESS_B}`);
  });
});

describe('fetchAccountAssets native RPC balances', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('uses the RPC native balance and block instead of a stale Zerion position', async () => {
    mockedSend.mockImplementation((method: string) => Promise.resolve(method === 'eth_blockNumber' ? '0x69' : '0x7d0'));
    mockedFetch.mockResolvedValue(positionsResponse({
      ...EMPTY_RESPONSE,
      data: [buildPosition('ethereum', 'eth', 100), buildPosition('ethereum', 'token', 101, ADDRESS_B)],
    }));

    const result = await fetchAccountAssets('ethereum', NETWORK, ADDRESS_A, jest.fn());

    expect(result.balances[getChainConfig('ethereum').nativeToken.slug]).toBe(2000n);
    expect(result.blockBySlug).toEqual({
      [getChainConfig('ethereum').nativeToken.slug]: 105,
      [`ethereum-${ADDRESS_B}`]: 101,
    });
    expect(mockedSend.mock.calls).toEqual([
      ['eth_blockNumber', []],
      ['eth_getBalance', [ADDRESS_A, '0x69']],
    ]);
  });

  it('falls back to Zerion when the balance cannot be read at the RPC block', async () => {
    mockedSend.mockImplementation((method: string, params: unknown[]) => {
      if (method === 'eth_blockNumber') return Promise.resolve('0x69');
      // A node still behind block 0x69 answers `latest` with an older balance and rejects the block itself
      return params[1] === 'latest' ? Promise.resolve('0x7d0') : Promise.reject(new Error('header not found'));
    });
    mockedFetch.mockResolvedValue(positionsResponse({
      ...EMPTY_RESPONSE,
      data: [buildPosition('ethereum', 'eth', 100)],
    }));

    const result = await fetchAccountAssets('ethereum', NETWORK, ADDRESS_A, jest.fn());

    const { slug } = getChainConfig('ethereum').nativeToken;
    expect(result.balances[slug]).toBe(1000n);
    expect(result.blockBySlug?.[slug]).toBe(100);
  });

  it.each(['none', 'rejection', 'invalid balance', 'invalid block'])(
    'reads every cross-chain native balance with per-chain RPC failure: %s',
    async (failure) => {
      const sendByChain: Partial<Record<EVMChain, jest.Mock>> = {};
      mockedGetEvmProvider.mockImplementation((_network, chain) => {
        const index = EVM_CHAINS.indexOf(chain);
        const send = jest.fn((method: string) => {
          if (chain === 'base') {
            if (failure === 'rejection') return Promise.reject(new Error('RPC unavailable'));
            if ((failure === 'invalid balance' && method === 'eth_getBalance')
              || (failure === 'invalid block' && method === 'eth_blockNumber')) {
              return Promise.resolve('0xinvalid');
            }
          }
          return Promise.resolve(`0x${(method === 'eth_blockNumber' ? 105 + index : 2000 + index).toString(16)}`);
        });
        sendByChain[chain] = send;
        return { send } as unknown as ReturnType<typeof getEvmProvider>;
      });
      mockedFetch.mockResolvedValue(positionsResponse({
        ...EMPTY_RESPONSE,
        data: EVM_CHAINS.map((chain) => buildPosition(
          getZerionChainByApiChain(chain), getChainConfig(chain).nativeToken.slug, 100,
        )),
      }));

      const result = await fetchCrosschainAccountAssets(NETWORK, ADDRESS_A, jest.fn());

      expect(EVM_CHAINS).toHaveLength(11);
      EVM_CHAINS.forEach((chain, index) => {
        const { slug } = getChainConfig(chain).nativeToken;
        const shouldFallback = chain === 'base' && failure !== 'none';
        expect(result.balances[slug]).toBe(shouldFallback ? 1000n : BigInt(2000 + index));
        expect(result.blockBySlug?.[slug]).toBe(shouldFallback ? 100 : 105 + index);
        const isBalanceRead = !(chain === 'base' && (failure === 'rejection' || failure === 'invalid block'));
        expect(mockedGetEvmProvider).toHaveBeenCalledWith(NETWORK, chain);
        expect(sendByChain[chain]?.mock.calls).toEqual([
          ['eth_blockNumber', []],
          ...(isBalanceRead ? [['eth_getBalance', [ADDRESS_A, `0x${(105 + index).toString(16)}`]]] : []),
        ]);
      });
    },
  );

  it('falls back for a stalled native RPC without blocking other chains', async () => {
    jest.useFakeTimers();
    try {
      const stalledRpc = createDeferred<string>();
      mockedGetEvmProvider.mockImplementation((_network, chain) => ({
        send: jest.fn((method: string) => {
          if (chain === 'base') return stalledRpc.promise;
          const index = EVM_CHAINS.indexOf(chain);
          return Promise.resolve(`0x${(method === 'eth_blockNumber' ? 105 + index : 2000 + index).toString(16)}`);
        }),
      } as unknown as ReturnType<typeof getEvmProvider>));
      mockedFetch.mockResolvedValue(positionsResponse({
        ...EMPTY_RESPONSE,
        data: EVM_CHAINS.map((chain) => buildPosition(
          getZerionChainByApiChain(chain), getChainConfig(chain).nativeToken.slug, 100,
        )),
      }));

      let hasSettled = false;
      const pending = fetchCrosschainAccountAssets(NETWORK, ADDRESS_A, jest.fn()).then((result) => {
        hasSettled = true;
        return result;
      });
      await jest.advanceTimersByTimeAsync(9_999);
      expect(hasSettled).toBe(false);
      await jest.advanceTimersByTimeAsync(1);

      expect(hasSettled).toBe(true);
      const result = await pending;
      EVM_CHAINS.forEach((chain, index) => {
        const { slug } = getChainConfig(chain).nativeToken;
        expect(result.balances[slug]).toBe(chain === 'base' ? 1000n : BigInt(2000 + index));
        expect(result.blockBySlug?.[slug]).toBe(chain === 'base' ? 100 : 105 + index);
      });
    } finally {
      jest.useRealTimers();
    }
  });

  it('reads the native balance at the RPC block before the Zerion response arrives', async () => {
    const positions = createDeferred<Response>();
    mockedFetch.mockReturnValue(positions.promise);
    mockedSend.mockImplementation((method: string) => Promise.resolve(method === 'eth_blockNumber' ? '0x69' : '0x7d0'));

    const pending = fetchAccountAssets('ethereum', NETWORK, ADDRESS_A, jest.fn());
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(mockedSend.mock.calls).toEqual([
      ['eth_blockNumber', []],
      ['eth_getBalance', [ADDRESS_A, '0x69']],
    ]);
    positions.resolve(positionsResponse(EMPTY_RESPONSE));
    await pending;
  });

  it('aborts while native RPC calls are pending without updating tokens', async () => {
    const rpc = createDeferred<string>();
    mockedSend.mockReturnValue(rpc.promise);
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE));
    const controller = new AbortController();

    const pending = fetchAccountAssets('ethereum', NETWORK, ADDRESS_A, jest.fn(), { signal: controller.signal });
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(mockedSend).toHaveBeenCalledTimes(1);
    const reason = new DOMException('Cancelled', 'AbortError');
    controller.abort(reason);
    await expect(pending).rejects.toBe(reason);
    rpc.resolve('0x69');
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(updateTokensFetchedTogether).not.toHaveBeenCalled();
  });
});

describe('balance reads at a specific block', () => {
  const mockedBalanceOf = jest.fn();

  beforeEach(() => {
    mockedBalanceOf.mockReset().mockResolvedValue(2000n);
    jest.mocked(Contract).mockReset()
      .mockReturnValue({ balanceOf: mockedBalanceOf } as unknown as Contract);
  });

  it('passes the native balance block to the provider', async () => {
    const getBalance = jest.fn().mockResolvedValue(2000n);
    mockedGetEvmProvider.mockReturnValue({ getBalance } as unknown as ReturnType<typeof getEvmProvider>);

    await expect(getWalletBalance('ethereum', NETWORK, ADDRESS_A, 105)).resolves.toBe(2000n);

    expect(getBalance).toHaveBeenCalledWith(ADDRESS_A, 105);
  });

  it('passes the ERC-20 block as an override and preserves calls without a block', async () => {
    await expect(getErc20Balance(NETWORK, 'ethereum', ADDRESS_A, ADDRESS_B, 105)).resolves.toBe(2000n);
    await expect(getErc20Balance(NETWORK, 'ethereum', ADDRESS_A, ADDRESS_B)).resolves.toBe(2000n);
    await expect(getErc20Balance(NETWORK, 'ethereum', ADDRESS_A, ADDRESS_B, 'latest')).resolves.toBe(2000n);

    expect(mockedBalanceOf.mock.calls).toEqual([
      [ADDRESS_A, { blockTag: 105 }],
      [ADDRESS_A],
      [ADDRESS_A, { blockTag: 'latest' }],
    ]);
  });

  it.each(['CALL_EXCEPTION', 'BAD_DATA'])('rethrows %s at a pinned block and returns zero for latest', async (code) => {
    const error = Object.assign(new Error('Historical balance unavailable'), { code });
    mockedBalanceOf.mockRejectedValue(error);

    await expect(getErc20Balance(NETWORK, 'ethereum', ADDRESS_A, ADDRESS_B, 105)).rejects.toBe(error);
    await expect(getErc20Balance(NETWORK, 'ethereum', ADDRESS_A, ADDRESS_B)).resolves.toBe(0n);
    await expect(getErc20Balance(NETWORK, 'ethereum', ADDRESS_A, ADDRESS_B, 'latest')).resolves.toBe(0n);
  });
});

function buildPosition(chain: string, fungibleId: string, block: number, address?: string): ZerionPosition {
  return {
    type: 'positions',
    id: `${chain}-${fungibleId}`,
    attributes: {
      parent: '',
      protocol: '',
      name: fungibleId,
      position_type: 'wallet',
      quantity: { int: '1000', decimals: 18, float: 0, numeric: '0' },
      value: 0,
      price: 0,
      changes: { absolute_1d: 0, percent_1d: 0 },
      fungible_info: {
        name: fungibleId,
        symbol: fungibleId,
        icon: { url: '' },
        flags: { verified: true },
        implementations: address ? [{ chain_id: chain, address, decimals: 18 }] : [],
      },
      flags: { displayable: true, is_trash: false },
      updated_at: '2026-11-02T00:00:00Z',
      updated_at_block: block,
    },
    relationships: {
      chain: { links: { related: '' }, data: { type: 'chains', id: chain } },
      fungible: { links: { related: '' }, data: { type: 'fungibles', id: fungibleId } },
    },
  };
}
