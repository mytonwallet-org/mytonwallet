import { decodeError, encodeError } from './extensionMessageSerializer';

describe('error encoding', () => {
  it('keeps the failure code across the hop', () => {
    const error = Object.assign(new Error('Enclave: auth is already configured'), {
      name: 'EnclaveError',
      code: 'auth_already_configured',
    });

    const decoded = decodeError(encodeError(error)) as Error & { code?: string };

    expect(decoded.name).toBe('EnclaveError');
    expect(decoded.code).toBe('auth_already_configured');
  });

  it('drops a code that is not a string', () => {
    const error = Object.assign(new Error('quota'), { name: 'QuotaExceededError', code: 22 });

    const decoded = decodeError(encodeError(error)) as Error & { code?: unknown };

    expect(decoded.code).toBeUndefined();
  });

  it('leaves an error without a code alone', () => {
    const decoded = decodeError(encodeError(new Error('boom'))) as Error & { code?: string };

    expect(decoded.message).toBe('boom');
    expect(decoded.code).toBeUndefined();
  });
});
