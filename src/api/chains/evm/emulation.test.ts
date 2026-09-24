/* eslint-disable no-null/no-null */

import { getAddress, Transaction } from 'ethers';

import type { AlchemyAssetChange } from './types';

import { getChainConfig } from '../../../util/chain';
import { fetchJson } from '../../../util/fetch';
import { getTokenBySlug } from '../../common/tokens';
import { buildTokenSlug } from '../../methods';
import { parseTokenOperation, parseTransactionForPreview } from './emulation';

jest.mock('../../../util/fetch', () => ({ fetchJson: jest.fn() }));
jest.mock('./util/metadata', () => ({ updateTokensMetadataByAddress: jest.fn() }));
jest.mock('./util/client', () => ({ getEvmProvider: jest.fn() }));
jest.mock('../../common/helpers', () => ({ updateActivityMetadata: (activity: unknown) => activity }));
jest.mock('../../common/tokens', () => ({
  ...jest.requireActual('../../common/tokens'),
  getTokenBySlug: jest.fn(),
}));
jest.mock('../../methods', () => ({
  buildTokenSlug: jest.requireActual('../../common/tokens').buildTokenSlug,
}));

const WALLET = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const ROUTER = '0x93fa28647b06ab40554d6905e4e9d8e8bb24380c';
const USDC = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
const ETH_AMOUNT = 2_000_000_000_000_000n;
const USDC_AMOUNT = 5_400_000n;
const nativeSlug = getChainConfig('ethereum').nativeToken.slug;
const usdcSlug = buildTokenSlug('ethereum', USDC);

function change(overrides: Partial<AlchemyAssetChange['changes'][number]> = {}): AlchemyAssetChange['changes'][number] {
  return {
    assetType: 'NATIVE',
    changeType: 'TRANSFER',
    from: WALLET,
    to: ROUTER,
    rawAmount: String(ETH_AMOUNT),
    amount: '0.002',
    contractAddress: null,
    tokenId: null,
    decimals: 18,
    symbol: 'ETH',
    name: 'Ethereum',
    logo: '',
    ...overrides,
  };
}

function simulation(changes: AlchemyAssetChange['changes']): AlchemyAssetChange {
  return { changes, gasUsed: '0x21285', error: null };
}

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(getTokenBySlug).mockReturnValue({ slug: usdcSlug, decimals: 6 } as never);
});

describe.each([WALLET, getAddress(WALLET)])('EVM previews for wallet %s', (walletAddress) => {
  it('recognizes the ETH sent by a 1inch deposit transaction', async () => {
    const result = await parseTokenOperation('mainnet', 'ethereum', simulation([change()]), walletAddress);

    expect(result).toMatchObject({
      isSwap: false,
      transfer: {
        fromAddress: getAddress(WALLET),
        toAddress: getAddress(ROUTER),
        amount: -ETH_AMOUNT,
        slug: nativeSlug,
        isIncoming: false,
      },
    });
  });

  it('recognizes an incoming transfer with checksummed simulation addresses', async () => {
    const result = await parseTokenOperation('mainnet', 'ethereum', simulation([
      change({ from: getAddress(ROUTER), to: getAddress(WALLET) }),
    ]), walletAddress);

    expect(result).toMatchObject({
      isSwap: false,
      transfer: { amount: ETH_AMOUNT, fromAddress: getAddress(ROUTER), isIncoming: true },
    });
  });

  it('recognizes both sides of an ETH to USDC swap', async () => {
    const result = await parseTokenOperation('mainnet', 'ethereum', simulation([
      change(),
      change({
        assetType: 'ERC20', contractAddress: USDC, from: getAddress(ROUTER), to: getAddress(WALLET),
        rawAmount: String(USDC_AMOUNT), amount: '5.4', decimals: 6, symbol: 'USDC',
      }),
    ]), walletAddress);

    expect(result).toMatchObject({
      isSwap: true,
      swap: { from: nativeSlug, fromAmount: '0.002', to: usdcSlug, toAmount: '5.4' },
    });
  });

  it('delivers an activity preview for an unsigned contract transaction', async () => {
    jest.mocked(fetchJson).mockResolvedValue({ result: simulation([change()]) });
    const rawTx = Transaction.from({
      chainId: 1, to: ROUTER, value: ETH_AMOUNT, data: '0x12345678', gasLimit: 160_000n, gasPrice: 1_000_000_000n,
    }).unsignedSerialized;

    const result = await parseTransactionForPreview('ethereum', rawTx, walletAddress, 'mainnet');

    expect(result.transfers[0].isDangerous).toBe(false);
    expect(result.emulation?.activities).toEqual([
      expect.objectContaining({ kind: 'transaction', amount: -ETH_AMOUNT, slug: nativeSlug }),
    ]);
  });
});

it('does not attribute another wallet’s transfers to the connected wallet', async () => {
  const result = await parseTokenOperation('mainnet', 'ethereum', simulation([
    change({ from: ROUTER, to: USDC }),
  ]), WALLET);

  expect(result).toBeUndefined();
});
