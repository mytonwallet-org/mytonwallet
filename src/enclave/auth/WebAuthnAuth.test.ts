import type { SimpleStorage } from '../types';

import WebAuthnAuth from './WebAuthnAuth';

function createStorageHolding(credentialParams: string | undefined) {
  return { getItem: () => Promise.resolve(credentialParams) } as unknown as SimpleStorage;
}

describe('WebAuthnAuth', () => {
  it('names credential params that are not stored', async () => {
    await expect(new WebAuthnAuth(createStorageHolding(undefined)).authorize())
      .rejects.toMatchObject({ code: 'auth_not_configured' });
  });

  it('keeps unreadable credential params apart from missing ones', async () => {
    const error = await new WebAuthnAuth(createStorageHolding('{')).authorize().catch((err: unknown) => err);

    expect(error).toMatchObject({ message: 'WebAuthnAuth: Corrupted credential params' });
    expect(error).not.toHaveProperty('code');
  });
});
