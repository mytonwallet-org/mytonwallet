import type { OriginMessageData, WorkerMessageData, WorkerMessageError } from './PostMessageConnector';

import { BIGINT_PREFIX } from './bigint';

export const UNDEFINED_PREFIX = 'undefined:';

function extensionMessageReplacer(this: any, key: string, value: any) {
  if (value === undefined) {
    return `${UNDEFINED_PREFIX}marker`;
  }

  // Bigint is replaced by patching `toJSON` method

  return value;
}

function extensionMessageReviver(this: any, key: string, value: any) {
  // Handle bigint values
  if (typeof value === 'string' && value.startsWith(BIGINT_PREFIX)) {
    return BigInt(value.slice(BIGINT_PREFIX.length));
  }

  // Handle undefined values
  if (typeof value === 'string' && value.startsWith(UNDEFINED_PREFIX)) {
    return undefined;
  }

  return value;
}

export function encodeExtensionMessage(data: OriginMessageData | WorkerMessageData) {
  return JSON.stringify(data, extensionMessageReplacer);
}

export function decodeExtensionMessage<T extends OriginMessageData | WorkerMessageData>(data: string | T): T {
  if (typeof data === 'string') {
    return JSON.parse(data, extensionMessageReviver);
  }
  return data;
}

export function encodeError(error: Error): WorkerMessageError {
  if (error instanceof Error) {
    // `DOMException` and friends carry a numeric `code`, which would break branching on the string one
    const { code } = error as Error & { code?: unknown };

    return {
      name: error.name,
      message: error.message,
      stack: error.stack,
      code: typeof code === 'string' ? code : undefined,
    };
  }

  // Just in case
  return {
    name: 'Error',
    message: String(error),
  };
}

export function decodeError({ name, message, stack, code }: WorkerMessageError): Error {
  const error = new Error(message);
  error.name = name;
  if (stack) {
    error.stack = stack;
  }
  if (code !== undefined) {
    (error as Error & { code?: string }).code = code;
  }
  return error;
}
