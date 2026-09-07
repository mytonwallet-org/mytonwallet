import { isValidAddress } from '../api/chains/evm/address';
import { ZERO_ADDRESS } from '../api/chains/evm/constants';
import { getChainConfig, getEvmChains, getIsSupportedChain } from './chain';

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
      expect(getIsSupportedChain('bitcoin')).toBe(false);
      expect(getIsSupportedChain('constructor')).toBe(false);
    } finally {
      Object.defineProperty(Object, 'hasOwn', descriptor);
    }
  });
});
