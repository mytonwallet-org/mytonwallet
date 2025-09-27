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
    return {
      name: error.name,
      message: error.message,
      stack: error.stack,
    };
  }

  // Just in case
  return {
    name: 'Error',
    message: String(error),
  };
}

export function decodeError({ name, message, stack }: WorkerMessageError): Error {
  const error = new Error(message);
  error.name = name;
  if (stack) {
    error.stack = stack;
  }
  return error;
}
