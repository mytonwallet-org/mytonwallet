import { ApiServerError, isWalletDiscoveryRecoverableTransportError } from './errors';

/** Shapes an error the way ethers does: a plain `Error` carrying a string `code`. */
function ethersError(code: string, message = 'server response 403') {
  return Object.assign(new Error(message), { code });
}

describe('isWalletDiscoveryRecoverableTransportError', () => {
  it('treats ethers transport codes as recoverable', () => {
    for (const code of ['SERVER_ERROR', 'NETWORK_ERROR', 'TIMEOUT']) {
      expect(isWalletDiscoveryRecoverableTransportError(ethersError(code))).toBe(true);
    }
  });

  it('does not treat an on-chain verdict as a transport failure', () => {
    // A reverted call is an answer from the chain. Swallowing it would hide the verdict behind a default wallet.
    for (const code of ['CALL_EXCEPTION', 'BAD_DATA', 'INSUFFICIENT_FUNDS', 'UNSUPPORTED_OPERATION']) {
      expect(isWalletDiscoveryRecoverableTransportError(ethersError(code))).toBe(false);
    }
  });

  it('keeps recognising the non-ethers transport failures', () => {
    expect(isWalletDiscoveryRecoverableTransportError(new ApiServerError('boom'))).toBe(true);
    expect(isWalletDiscoveryRecoverableTransportError(new TypeError('Failed to fetch'))).toBe(true);
    expect(isWalletDiscoveryRecoverableTransportError(new TypeError('Load failed'))).toBe(true);
  });

  it('ignores errors that carry no usable code', () => {
    expect(isWalletDiscoveryRecoverableTransportError(new Error('SERVER_ERROR'))).toBe(false);
    expect(isWalletDiscoveryRecoverableTransportError(new TypeError('Something else'))).toBe(false);
    expect(isWalletDiscoveryRecoverableTransportError(Object.assign(new Error('x'), { code: 500 }))).toBe(false);
    expect(isWalletDiscoveryRecoverableTransportError({ code: 'SERVER_ERROR' })).toBe(false);
    expect(isWalletDiscoveryRecoverableTransportError(undefined)).toBe(false);
  });
});
