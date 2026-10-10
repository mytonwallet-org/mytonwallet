import type {
  AgentErrorCodeV2,
} from '../types';
import type {
  JsonObject,
} from '../wireReader';

import { AGENT_ERROR_CODES, AGENT_RETRYABLE_ERROR_CODES } from '../../generated/constants';
import {
  AgentV2CompatibilityError,
  array,
  fail,
  integer,
  oneOf,
  string,
} from '../wireReader';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FOLLOWUP_UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

export const ERROR_CODES: ReadonlySet<string> = new Set(AGENT_ERROR_CODES);

export const RETRYABLE_ERROR_CODES: ReadonlySet<string> = new Set(AGENT_RETRYABLE_ERROR_CODES);

export function uuid(value: unknown, path: string): string {
  const result = string(value, path);
  if (!UUID_PATTERN.test(result)) fail(path);
  return result;
}

export function followupUuid(value: unknown, path: string): string {
  const result = string(value, path);
  if (!FOLLOWUP_UUID_PATTERN.test(result)) fail(path);
  return result;
}

export function protocol(value: JsonObject, path: string) {
  const version = integer(value.protocolVersion, `${path}.protocolVersion`, 1);
  if (version !== 3) throw new AgentV2CompatibilityError(`${path}.protocolVersion`, undefined, version);
}

export function validateEnumArray(value: unknown, path: string, limit: number, allowed: string[]) {
  const items = array(value, path, limit);
  if (new Set(items).size !== items.length) fail(path);
  items.forEach((item, index) => oneOf(item, new Set(allowed), `${path}[${index}]`));
}

export function validateErrorTiming(code: AgentErrorCodeV2, error: JsonObject, path: string) {
  const hasTiming = error.retryAfterMs !== undefined || error.resetAt !== undefined;
  const isUserRateLimit = code === 'device_token_rate_limited'
    || code === 'rate_limited'
    || code === 'user_quota_exhausted';
  if (isUserRateLimit && !hasTiming) fail(`${path}.retryAfterMs`);
  if (hasTiming && !isUserRateLimit && code !== 'agent_capacity_exhausted') fail(`${path}.code`);
}
