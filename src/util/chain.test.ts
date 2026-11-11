import { getBase58Decoder } from '@solana/kit';

import { isValidAddress } from '../api/chains/evm/address';
import { ZERO_ADDRESS } from '../api/chains/evm/constants';
import { getChainConfig, getEvmChains, getIsSupportedChain } from './chain';

describe('Solana address matching', () => {
  it('excludes TRON recipients from Solana token selection', () => {
    const address = 'TVQ1BBt6WEQ1gcbkLNaJAWumuQrfDo1MgW';

    expect(getChainConfig('tron').addressRegex.test(address)).toBe(true);
    expect(getChainConfig('solana').addressRegex.test(address)).toBe(false);
  });

  it.each([1, 255])('accepts 32-byte addresses with leading zero bytes and remaining bytes %i', (value) => {
    const decoder = getBase58Decoder();
    const { addressRegex } = getChainConfig('solana');

    for (let leadingZeroBytes = 0; leadingZeroBytes <= 32; leadingZeroBytes++) {
      const bytes = new Uint8Array(32).fill(value).fill(0, 0, leadingZeroBytes);

      expect(addressRegex.test(decoder.decode(bytes))).toBe(true);
    }
  });
});

describe('feeCheckAddress', () => {
  // A zero probe address reverts in every OpenZeppelin-derived ERC20 before the gas is measured.
  it.each(getEvmChains())('is a valid, non-zero account on %s', (chain) => {
    const address = getChainConfig(chain).feeCheckAddress;

    expect(address).not.toBe(ZERO_ADDRESS);
    expect(isValidAddress(address)).toBe(true);
  });

  it('is the same account on every EVM chain, so estimates agree across chains', () => {
    const addresses = new Set(getEvmChains().map((chain) => getChainConfig(chain).feeCheckAddress));

    expect(addresses.size).toBe(1);
  });
});

describe('getIsSupportedChain', () => {
  it('recognizes configured chains in the legacy browser baseline', () => {
    const descriptor = Object.getOwnPropertyDescriptor(Object, 'hasOwn')!;
    Object.defineProperty(Object, 'hasOwn', { ...descriptor, value: undefined });

    try {
      expect(getIsSupportedChain('ton')).toBe(true);
      expect(getIsSupportedChain('robinhood')).toBe(true);
      expect(getIsSupportedChain('bitcoin')).toBe(true);
      expect(getIsSupportedChain('constructor')).toBe(false);
    } finally {
      Object.defineProperty(Object, 'hasOwn', descriptor);
    }
  });
});
