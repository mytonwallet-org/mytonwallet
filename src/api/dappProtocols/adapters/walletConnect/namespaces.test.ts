import { SOLANA_CHAIN_IDS } from './types';

import {
  filterCaip2sOnNetwork,
  hexToEip155Caip2,
  normalizeEip155HexChainId,
} from './namespaces';

describe('WalletConnect EIP-155 chain IDs', () => {
  it.each([
    ['4663', 'eip155:4663'],
    ['0x1237', 'eip155:4663'],
    ['0x4663', 'eip155:18019'],
  ])('converts %s to a CAIP-2 chain ID', (chainId, expected) => {
    expect(hexToEip155Caip2(chainId)).toBe(expected);
  });

  it.each([
    ['4663', '0x1237'],
    ['0x1237', '0x1237'],
    ['0x4663', '0x4663'],
  ])('normalizes %s to a hex chain ID', (chainId, expected) => {
    expect(normalizeEip155HexChainId(chainId)).toBe(expected);
  });

  it('rejects an empty chain ID', () => {
    expect(() => hexToEip155Caip2('')).toThrow('Invalid chain ID');
    expect(() => normalizeEip155HexChainId('')).toThrow('Invalid chain ID');
  });
});

describe('WalletConnect chains of a relay session', () => {
  const SOLANA_CAIP2S = Object.keys(SOLANA_CHAIN_IDS);

  it.each([
    ['mainnet', ['eip155:8453', 'eip155:324', ...SOLANA_CAIP2S]],
    ['testnet', ['eip155:84532', 'eip155:324', ...SOLANA_CAIP2S]],
  ] as const)('keeps the EVM chains of %s, the chains the wallet does not know and Solana', (network, expected) => {
    const caip2s = ['eip155:8453', 'eip155:84532', 'eip155:324', ...SOLANA_CAIP2S];

    expect(filterCaip2sOnNetwork(caip2s, network)).toEqual(expected);
  });
});
