import nacl from 'tweetnacl';

import { BACKEND_AUTH_SIGN_MESSAGE, buildBackendAuthToken } from './backendAuth';

describe('buildBackendAuthToken', () => {
  it('produces a deterministic signature that verifies against the wallet public key', () => {
    const { publicKey, secretKey } = nacl.sign.keyPair();

    const authToken = buildBackendAuthToken(secretKey);
    const signature = new Uint8Array(Buffer.from(authToken, 'base64'));

    expect(signature.length).toBe(nacl.sign.signatureLength);
    expect(nacl.sign.detached.verify(BACKEND_AUTH_SIGN_MESSAGE, signature, publicKey)).toBe(true);
    expect(buildBackendAuthToken(secretKey)).toBe(authToken);
  });

  it('does not verify against a foreign public key', () => {
    const { secretKey } = nacl.sign.keyPair();
    const foreign = nacl.sign.keyPair();

    const signature = new Uint8Array(Buffer.from(buildBackendAuthToken(secretKey), 'base64'));

    expect(nacl.sign.detached.verify(BACKEND_AUTH_SIGN_MESSAGE, signature, foreign.publicKey)).toBe(false);
  });
});
