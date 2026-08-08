import nacl from 'tweetnacl';

// `MyTonWallet` is here for backward compatibility reasons
export const BACKEND_AUTH_SIGN_MESSAGE = new TextEncoder().encode('MyTonWallet_AuthToken_n6i0k4w8pb');

/**
 * Builds the backend auth token: the wallet key's Ed25519 signature over a constant message.
 * The signature is deterministic, so eager and lazy generation produce the same token.
 */
export function buildBackendAuthToken(secretKey: Uint8Array) {
  return Buffer.from(nacl.sign.detached(BACKEND_AUTH_SIGN_MESSAGE, secretKey)).toString('base64');
}
