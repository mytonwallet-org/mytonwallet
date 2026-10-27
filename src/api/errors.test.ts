import {
  SOLANA_ERROR__JSON_RPC__INVALID_PARAMS,
  SOLANA_ERROR__RPC__TRANSPORT_HTTP_ERROR,
  SolanaError,
} from '@solana/kit';

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

  it('treats a Solana RPC that answered non-2xx as recoverable', () => {
    // Built with the real class, so a @solana/kit upgrade that reshapes the error fails here rather than in an import
    const rateLimited = new SolanaError(SOLANA_ERROR__RPC__TRANSPORT_HTTP_ERROR, {
      headers: new Headers(),
      message: 'Too Many Requests',
      statusCode: 429,
    });

    expect(isWalletDiscoveryRecoverableTransportError(rateLimited)).toBe(true);
  });

  it('does not treat a Solana JSON-RPC answer as a transport failure', () => {
    const invalidParams = new SolanaError(SOLANA_ERROR__JSON_RPC__INVALID_PARAMS, { __serverMessage: 'Invalid param' });

    expect(isWalletDiscoveryRecoverableTransportError(invalidParams)).toBe(false);
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
