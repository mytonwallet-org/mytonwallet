import type { OriginMessageData, WorkerMessageData, WorkerMessageError } from './PostMessageConnector';

import { BIGINT_PREFIX } from './bigint';
import { PERPS_ERROR_FIELD_KEYS } from './perpsErrorFields';

export const UNDEFINED_PREFIX = 'undefined:';

const ERROR_FIELD_TYPES = new Set(['string', 'number', 'boolean']);

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
      fields: pickErrorFields(error),
    };
  }

  // Just in case
  return {
    name: 'Error',
    message: String(error),
  };
}

export function decodeError({ name, message, stack, code, fields }: WorkerMessageError): Error {
  const error = new Error(message);
  if (fields) {
    Object.assign(error, pickErrorFields(fields));
  }
  error.name = name;
  if (stack) {
    error.stack = stack;
  }
  if (code !== undefined) {
    (error as Error & { code?: string }).code = code;
  }
  return error;
}

// Only the fields the Perps screens read cross the boundary, and only as primitives, which survive both the structured
// clone of a worker and the JSON of an extension port. The decoding side filters them again, since a JSON message
// turns `NaN` into `null` and a prefixed string into a bigint.
function pickErrorFields(source: object): WorkerMessageError['fields'] {
  const entries = Object.entries(source)
    .filter(([key, value]) => PERPS_ERROR_FIELD_KEYS.has(key) && ERROR_FIELD_TYPES.has(typeof value));

  return entries.length ? Object.fromEntries(entries) : undefined;
}
