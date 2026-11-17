import type { WorkerMessageData } from './PostMessageConnector';

import {
  decodeError, decodeExtensionMessage, encodeError, encodeExtensionMessage,
} from './extensionMessageSerializer';

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

  it('keeps the primitive Perps fields of the error through an extension port', () => {
    const error = Object.assign(new Error('PerpsAmountTooSmall'), {
      minimumAmount: '10.004',
      isMinimumExclusive: true,
      attempt: 2,
      requiredBalance: undefined,
      availableBalance: { amount: '1' },
      cause: new Error('nested'),
    });

    const response = decodeExtensionMessage<Extract<WorkerMessageData, { type: 'methodResponse' }>>(
      encodeExtensionMessage({ type: 'methodResponse', messageId: '1', error: encodeError(error) }),
    );
    const decoded = decodeError(response.error!);

    expect(response.error!.fields).toEqual({ minimumAmount: '10.004', isMinimumExclusive: true });
    expect(decoded).toMatchObject({ minimumAmount: '10.004', isMinimumExclusive: true });
    expect(decoded).not.toHaveProperty('attempt');
    expect(decoded).not.toHaveProperty('availableBalance');
    expect(decoded).not.toHaveProperty('cause');
  });

  it('never lets a field replace what the message carries on its own', () => {
    const decoded = decodeError({
      name: 'Error',
      message: 'boom',
      fields: {
        message: 'other', stack: 'other', session: 'secret', minimumAmount: { value: '1' }, requiredBalance: 1n,
      } as AnyLiteral,
    });

    expect(decoded.message).toBe('boom');
    expect(decoded.stack).not.toBe('other');
    expect(decoded).not.toHaveProperty('session');
    expect(decoded).not.toHaveProperty('minimumAmount');
    expect(decoded).not.toHaveProperty('requiredBalance');
  });

  it('decodes a message without fields, as an older sender posts it', () => {
    const decoded = decodeError({ name: 'EnclaveError', message: 'boom', code: 'auth_already_configured' });

    expect(decoded).toMatchObject({ name: 'EnclaveError', message: 'boom', code: 'auth_already_configured' });
  });
});
