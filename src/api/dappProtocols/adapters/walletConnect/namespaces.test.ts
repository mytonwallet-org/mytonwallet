import {
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
