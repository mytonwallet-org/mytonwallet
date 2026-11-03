/* eslint-disable no-null/no-null */

import { getAddress, Transaction } from 'ethers';

import type { AlchemyAssetChange } from './types';

import { getChainConfig } from '../../../util/chain';
import { fetchJson } from '../../../util/fetch';
import { updateTokensMetadataByAddress } from './util/metadata';
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
const USDT = '0xdac17f958d2ee523a2206206994597c13d831ec7';
const DAI = '0x6b175474e89094c44da98b954eedeac495271d0f';
const RECIPIENT = '0x2222222222222222222222222222222222222222';
const OTHER_RECIPIENT = '0x3333333333333333333333333333333333333333';
const ETH_AMOUNT = 2_000_000_000_000_000n;
const USDC_AMOUNT = 5_400_000n;
const USDT_AMOUNT = 3_000_000n;
const nativeSlug = getChainConfig('ethereum').nativeToken.slug;
const usdcSlug = buildTokenSlug('ethereum', USDC);
const usdtSlug = buildTokenSlug('ethereum', USDT);

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

async function preview(changes: AlchemyAssetChange['changes'], walletAddress: string) {
  jest.mocked(fetchJson).mockResolvedValue({ result: simulation(changes) });
  const rawTx = Transaction.from({
    chainId: 1, to: ROUTER, value: ETH_AMOUNT, data: '0x12345678', gasLimit: 160_000n, gasPrice: 1_000_000_000n,
  }).unsignedSerialized;

  return parseTransactionForPreview('ethereum', rawTx, walletAddress, 'mainnet');
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
      transfers: [{
        fromAddress: getAddress(WALLET),
        toAddress: getAddress(ROUTER),
        amount: -ETH_AMOUNT,
        slug: nativeSlug,
        isIncoming: false,
      }],
    });
  });

  it('recognizes an incoming transfer with checksummed simulation addresses', async () => {
    const result = await parseTokenOperation('mainnet', 'ethereum', simulation([
      change({ from: getAddress(ROUTER), to: getAddress(WALLET) }),
    ]), walletAddress);

    expect(result).toMatchObject({
      isSwap: false,
      transfers: [{ amount: ETH_AMOUNT, fromAddress: getAddress(ROUTER), isIncoming: true }],
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

  it('previews every sent asset with its own recipient and loads token metadata', async () => {
    const result = await preview([
      change({
        assetType: 'ERC20', contractAddress: USDC, to: RECIPIENT,
        rawAmount: String(USDC_AMOUNT), amount: '5.4', decimals: 6, symbol: 'USDC',
      }),
      change(),
      change({
        assetType: 'ERC20', contractAddress: USDT, to: OTHER_RECIPIENT,
        rawAmount: String(USDT_AMOUNT), amount: '3', decimals: 6, symbol: 'USDT',
      }),
    ], walletAddress);

    expect(result.transfers).toEqual([expect.objectContaining({ isDangerous: false })]);
    expect(result.emulation?.activities).toEqual([
      expect.objectContaining({
        id: '0', kind: 'transaction', amount: -USDC_AMOUNT, slug: usdcSlug, isIncoming: false,
        fromAddress: getAddress(WALLET), toAddress: RECIPIENT, normalizedAddress: RECIPIENT,
      }),
      expect.objectContaining({
        id: '1', kind: 'transaction', amount: -ETH_AMOUNT, slug: nativeSlug, isIncoming: false,
        fromAddress: getAddress(WALLET), toAddress: getAddress(ROUTER), normalizedAddress: getAddress(ROUTER),
      }),
      expect.objectContaining({
        id: '2', kind: 'transaction', amount: -USDT_AMOUNT, slug: usdtSlug, isIncoming: false,
        fromAddress: getAddress(WALLET), toAddress: OTHER_RECIPIENT, normalizedAddress: OTHER_RECIPIENT,
      }),
    ]);
    expect(updateTokensMetadataByAddress).toHaveBeenCalledWith('mainnet', 'ethereum', [USDC, USDT]);
  });

  it('previews every received asset with its own sender and loads token metadata', async () => {
    const result = await preview([
      change({
        assetType: 'ERC20', contractAddress: USDC, from: getAddress(ROUTER), to: getAddress(WALLET),
        rawAmount: String(USDC_AMOUNT), amount: '5.4', decimals: 6, symbol: 'USDC',
      }),
      change({
        assetType: 'ERC20', contractAddress: USDT, from: RECIPIENT, to: WALLET,
        rawAmount: String(USDT_AMOUNT), amount: '3', decimals: 6, symbol: 'USDT',
      }),
    ], walletAddress);

    expect(result.transfers).toEqual([expect.objectContaining({ isDangerous: false })]);
    expect(result.emulation?.activities).toEqual([
      expect.objectContaining({
        id: '0', kind: 'transaction', amount: USDC_AMOUNT, slug: usdcSlug, isIncoming: true,
        fromAddress: getAddress(ROUTER), toAddress: getAddress(WALLET), normalizedAddress: getAddress(ROUTER),
      }),
      expect.objectContaining({
        id: '1', kind: 'transaction', amount: USDT_AMOUNT, slug: usdtSlug, isIncoming: true,
        fromAddress: RECIPIENT, toAddress: getAddress(WALLET), normalizedAddress: RECIPIENT,
      }),
    ]);
    expect(updateTokensMetadataByAddress).toHaveBeenCalledWith('mainnet', 'ethereum', [USDC, USDT]);
  });

  it.each(['sent', 'received'] as const)('marks a swap with multiple %s assets as dangerous', async (side) => {
    const changes = [
      change(),
      change({
        assetType: 'ERC20', contractAddress: USDC,
        from: side === 'sent' ? WALLET : ROUTER, to: side === 'sent' ? ROUTER : WALLET,
        rawAmount: String(USDC_AMOUNT), amount: '5.4', decimals: 6, symbol: 'USDC',
      }),
      change({ assetType: 'ERC20', contractAddress: DAI, from: ROUTER, to: WALLET, symbol: 'DAI' }),
    ];
    const result = await preview(changes, walletAddress);

    expect(result.emulation).toBeUndefined();
    expect(result.transfers).toEqual([expect.objectContaining({ isDangerous: true })]);
    expect(await parseTokenOperation('mainnet', 'ethereum', simulation(changes), walletAddress)).toBeUndefined();
  });

  it.each([
    ['ERC721', false], ['ERC721', true], ['ERC1155', false], ['ERC1155', true],
  ] as const)('marks outgoing %s as dangerous (with ERC20: %s)', async (assetType, withErc20) => {
    const changes = [change({
      assetType, contractAddress: RECIPIENT, tokenId: '1', rawAmount: '1', amount: '1', decimals: 0,
      from: walletAddress === WALLET ? getAddress(WALLET) : WALLET,
    })];
    if (withErc20) {
      changes.push(change({
        assetType: 'ERC20', contractAddress: USDC,
        rawAmount: String(USDC_AMOUNT), amount: '5.4', decimals: 6, symbol: 'USDC',
      }));
    }
    const result = await preview(changes, walletAddress);

    expect(result.emulation).toBeUndefined();
    expect(result.transfers).toEqual([expect.objectContaining({ isDangerous: true })]);
    expect(await parseTokenOperation('mainnet', 'ethereum', simulation(changes), walletAddress)).toBeUndefined();
  });

  it('previews ETH paid for an incoming NFT without marking the mint as dangerous', async () => {
    const result = await preview([
      change(),
      change({
        assetType: 'ERC721', contractAddress: RECIPIENT, from: '0x0000000000000000000000000000000000000000',
        to: getAddress(WALLET), tokenId: '1', rawAmount: '1', amount: '1', decimals: 0,
      }),
    ], walletAddress);

    expect(result.transfers).toEqual([expect.objectContaining({ isDangerous: false })]);
    expect(result.emulation?.activities).toEqual([
      expect.objectContaining({ kind: 'transaction', amount: -ETH_AMOUNT, slug: nativeSlug, isIncoming: false }),
    ]);
  });
});

it('marks an outgoing SPECIAL_NFT alongside USDC as dangerous', async () => {
  const changes = [
    change({
      assetType: 'SPECIAL_NFT', contractAddress: RECIPIENT, from: getAddress(WALLET),
      tokenId: '1', rawAmount: '1', amount: '1', decimals: 0,
    }),
    change({
      assetType: 'ERC20', contractAddress: USDC,
      rawAmount: String(USDC_AMOUNT), amount: '5.4', decimals: 6, symbol: 'USDC',
    }),
  ];
  const result = await preview(changes, WALLET);

  expect(result.emulation).toBeUndefined();
  expect(result.transfers).toEqual([expect.objectContaining({ isDangerous: true })]);
  expect(await parseTokenOperation('mainnet', 'ethereum', simulation(changes), WALLET)).toBeUndefined();
});

it('marks a sent-only token transfer to different recipients as dangerous', async () => {
  const changes = [
    change({
      assetType: 'ERC20', contractAddress: USDC,
      rawAmount: '1000000', amount: '1', decimals: 6, symbol: 'USDC',
    }),
    change({
      assetType: 'ERC20', contractAddress: USDC, to: RECIPIENT,
      rawAmount: '1000000000', amount: '1000', decimals: 6, symbol: 'USDC',
    }),
  ];
  const result = await preview(changes, WALLET);

  expect(result.emulation).toBeUndefined();
  expect(result.transfers).toEqual([expect.objectContaining({ isDangerous: true })]);
  expect(await parseTokenOperation('mainnet', 'ethereum', simulation(changes), WALLET)).toBeUndefined();
});

it('sums sent-only token transfers to the same normalized recipient into one safe activity', async () => {
  const result = await preview([
    change({
      assetType: 'ERC20', contractAddress: USDC,
      rawAmount: '1000000', amount: '1', decimals: 6, symbol: 'USDC',
    }),
    change({
      assetType: 'ERC20', contractAddress: USDC, to: getAddress(ROUTER),
      rawAmount: '1000000000', amount: '1000', decimals: 6, symbol: 'USDC',
    }),
  ], WALLET);

  expect(result.transfers).toEqual([expect.objectContaining({ isDangerous: false })]);
  expect(result.emulation?.activities).toEqual([
    expect.objectContaining({
      kind: 'transaction', amount: -1_001_000_000n, slug: usdcSlug,
      fromAddress: getAddress(WALLET), toAddress: getAddress(ROUTER), isIncoming: false,
    }),
  ]);
});

it('does not attribute another wallet’s transfers to the connected wallet', async () => {
  const result = await parseTokenOperation('mainnet', 'ethereum', simulation([
    change({ from: ROUTER, to: USDC }),
  ]), WALLET);

  expect(result).toBeUndefined();
});
