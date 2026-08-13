import type { CredentialParams } from './webAuthn';

import { authorize, setup } from './webAuthn';

const BYTES = [0, 1, 127, 128, 255];

function readBytes(buffer: ArrayBuffer | undefined) {
  return buffer && Array.from(new Uint8Array(buffer));
}

function mockCredentials(value: unknown) {
  Object.defineProperty(navigator, 'credentials', { configurable: true, value });
}

function assertionOf(extensionResults: unknown, userHandle?: unknown) {
  return Promise.resolve({
    getClientExtensionResults: () => extensionResults,
    response: { userHandle },
  });
}

describe('authorize', () => {
  const CREDENTIAL = { credentialId: 'ab', transports: [] as AuthenticatorTransport[] };

  function mockAssertion(extensionResults: unknown, userHandle?: unknown) {
    mockCredentials({ get: () => assertionOf(extensionResults, userHandle) });
  }

  afterEach(() => {
    // @ts-expect-error The property is restored by deletion, since it was defined on the instance
    delete navigator.credentials;
  });

  it('accepts a PRF result that arrived as a plain array, as 1Password returns it', async () => {
    mockAssertion({ prf: { results: { first: BYTES } } });

    const secret = await authorize({ ...CREDENTIAL, secretMethod: 'prf' });

    expect(readBytes(secret)).toEqual(BYTES);
  });

  it('refuses to derive a key from an unusable PRF result', async () => {
    mockAssertion({ prf: { results: { first: {} } } });

    await expect(authorize({ ...CREDENTIAL, secretMethod: 'prf' })).rejects.toThrow('PRF output not found');
  });

  it('refuses an empty user handle', async () => {
    mockAssertion({}, new ArrayBuffer(0));

    await expect(authorize({ ...CREDENTIAL, secretMethod: 'userHandle' })).rejects.toThrow('User handle not found');
  });

  // The spec lets `get` resolve null, and a patched API may resolve anything at all
  it('names an assertion the API did not return', async () => {
    // eslint-disable-next-line no-null/no-null -- the value the spec allows
    mockCredentials({ get: () => Promise.resolve(null) });

    await expect(authorize({ ...CREDENTIAL, secretMethod: 'prf' })).rejects.toThrow('Assertion not returned');
  });

  it('names an assertion that reports no extension results', async () => {
    mockCredentials({ get: () => Promise.resolve({ response: {} }) });

    await expect(authorize({ ...CREDENTIAL, secretMethod: 'prf' })).rejects.toThrow('PRF output not found');
  });

  it('asks the authenticator to time out', async () => {
    let requested: CredentialRequestOptions | undefined;
    mockCredentials({
      get: (options: CredentialRequestOptions) => {
        requested = options;
        return assertionOf({ prf: { results: { first: BYTES } } });
      },
    });

    await authorize({ ...CREDENTIAL, secretMethod: 'prf' });

    expect(requested?.publicKey?.timeout).toBeGreaterThan(0);
  });
});

describe('setup', () => {
  const persisted: CredentialParams[] = [];
  const calls: string[] = [];

  function persist(params: CredentialParams) {
    persisted.push(params);
    calls.push('persist');
    return Promise.resolve();
  }

  function mockRegistration(createResults: unknown, assertionResults?: unknown) {
    mockCredentials({
      create: () => Promise.resolve({
        rawId: new Uint8Array([0xAB]).buffer,
        response: {},
        getClientExtensionResults: () => createResults,
      }),
      get: () => {
        calls.push('get');
        return assertionOf(assertionResults);
      },
    });
  }

  beforeEach(() => {
    persisted.length = 0;
    calls.length = 0;
  });

  afterEach(() => {
    // @ts-expect-error The property is restored by deletion, since it was defined on the instance
    delete navigator.credentials;
  });

  it('takes the PRF output the registration already produced', async () => {
    mockRegistration({ prf: { enabled: true, results: { first: BYTES } } });

    const secret = await setup(persist);

    expect(persisted[0].secretMethod).toBe('prf');
    expect(readBytes(secret)).toEqual(BYTES);
    expect(calls).toEqual(['persist']);
  });

  // `enabled` says the PRF may be used with this credential, not that it was evaluated now
  it('evaluates the PRF in an assertion when registration enabled it without an output', async () => {
    mockRegistration({ prf: { enabled: true } }, { prf: { results: { first: BYTES } } });

    const secret = await setup(persist);

    expect(persisted[0].secretMethod).toBe('prf');
    expect(readBytes(secret)).toEqual(BYTES);
    expect(calls).toEqual(['persist', 'get']);
  });

  it('claims the PRF from an output that arrived without `enabled`', async () => {
    mockRegistration({ prf: { results: { first: BYTES } } });

    const secret = await setup(persist);

    expect(persisted[0].secretMethod).toBe('prf');
    expect(readBytes(secret)).toEqual(BYTES);
  });

  // `hmacGetSecret` is an assertion output and cannot be present at registration
  it('evaluates the HMAC secret in an assertion', async () => {
    mockRegistration({ hmacCreateSecret: true }, { hmacGetSecret: { output1: BYTES } });

    const secret = await setup(persist);

    expect(persisted[0].secretMethod).toBe('hmacSecret');
    expect(readBytes(secret)).toEqual(BYTES);
  });

  // `getCredBlob` is likewise an assertion output; registration only reports the blob was stored
  it('reads the cred blob in an assertion', async () => {
    mockRegistration({ credBlob: true }, { getCredBlob: BYTES });

    const secret = await setup(persist);

    expect(persisted[0].secretMethod).toBe('credBlob');
    expect(readBytes(secret)).toEqual(BYTES);
  });

  it('fails by name when the PRF yields nothing either way', async () => {
    mockRegistration({ prf: { enabled: true } }, { prf: {} });

    await expect(setup(persist)).rejects.toThrow('PRF output not found');
  });

  it('records the credential before asking for a second prompt', async () => {
    mockRegistration({ prf: { enabled: true } }, { prf: {} });

    await expect(setup(persist)).rejects.toThrow();

    expect(calls).toEqual(['persist', 'get']);
    expect(persisted).toHaveLength(1);
  });

  it('does not reach for an assertion when no extension named a method', async () => {
    mockRegistration({});

    const secret = await setup(persist);

    expect(persisted[0].secretMethod).toBe('userHandle');
    expect(secret.byteLength).toBe(32);
    expect(calls).toEqual(['persist']);
  });

  it('falls back to the user handle when the API reports no extension results at all', async () => {
    mockCredentials({
      create: () => Promise.resolve({ rawId: new Uint8Array([0xAB]).buffer, response: {} }),
    });

    const secret = await setup(persist);

    expect(persisted[0].secretMethod).toBe('userHandle');
    expect(secret.byteLength).toBe(32);
  });

  it('names a credential the API did not return', async () => {
    // eslint-disable-next-line no-null/no-null -- the value the spec allows
    mockCredentials({ create: () => Promise.resolve(null) });

    await expect(setup(persist)).rejects.toThrow('Credential not returned');
    expect(persisted).toHaveLength(0);
  });

  it('names a credential that carries no id', async () => {
    mockCredentials({ create: () => Promise.resolve({ response: {} }) });

    await expect(setup(persist)).rejects.toThrow('Credential id not found');
  });
});
