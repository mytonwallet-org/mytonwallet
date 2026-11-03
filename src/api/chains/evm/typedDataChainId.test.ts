import type { EVMChain } from '../../types';

import { isTypedDataDomainOnChain } from './typedDataChainId';

describe('isTypedDataDomainOnChain', () => {
  it.each([8453, '8453', '0x2105', 8453n])('matches Base mainnet for %p', (chainId) => {
    expect(isTypedDataDomainOnChain({ chainId }, 'mainnet', 'base')).toBe(true);
  });

  it('matches the testnet id on testnet', () => {
    expect(isTypedDataDomainOnChain({ chainId: 84532 }, 'testnet', 'base')).toBe(true);
    expect(isTypedDataDomainOnChain({ chainId: 8453 }, 'testnet', 'base')).toBe(false);
  });

  // eslint-disable-next-line no-null/no-null -- typed data arrives as JSON
  it.each([undefined, null])('accepts an absent chainId (%p)', (chainId) => {
    expect(isTypedDataDomainOnChain({ name: 'Token', chainId }, 'mainnet', 'ethereum')).toBe(true);
    expect(isTypedDataDomainOnChain({ name: 'Token' }, 'mainnet', 'ethereum')).toBe(true);
  });

  it.each(['abc', '', '0x', ' 1', '1.0', 1.5, -1, -1n, true, {}, [1]])('rejects unparseable chainId %p', (chainId) => {
    expect(isTypedDataDomainOnChain({ chainId }, 'mainnet', 'ethereum')).toBe(false);
  });

  it('rejects a chainId when the expected id is unknown', () => {
    expect(isTypedDataDomainOnChain({ chainId: 1 }, 'mainnet', 'unknown' as EVMChain)).toBe(false);
  });
});
