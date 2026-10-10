export type JsonObject = Record<string, unknown>;

export class AgentV2ContractError extends Error {
  constructor(readonly path: string) {
    super(`Invalid Agent V2 contract at ${path}`);
    this.name = 'AgentV2ContractError';
  }
}

export class AgentV2CompatibilityError extends Error {
  constructor(
    readonly boundary: string,
    readonly discriminator?: string,
    readonly version?: number,
  ) {
    super(`Unsupported Agent V2 protocol at ${boundary}`);
    this.name = 'AgentV2CompatibilityError';
  }
}

export function fail(path: string): never {
  throw new AgentV2ContractError(path);
}

export function object(value: unknown, path: string): JsonObject {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(path);
  return value as JsonObject;
}

export function strictKeys(value: JsonObject, path: string, allowedKeys: readonly string[]) {
  const allowed = new Set(allowedKeys);
  const unknownKey = Object.keys(value).find((key) => !allowed.has(key));
  if (unknownKey) fail(`${path}.${unknownKey}`);
}

export function string(value: unknown, path: string, minLength = 1): string {
  if (typeof value !== 'string' || value.length < minLength) fail(path);
  return value;
}

export function boundedString(value: unknown, path: string, minLength: number, maxLength: number): string {
  const result = string(value, path, minLength);
  if ([...result].length > maxLength) fail(path);
  return result;
}

export function optionalString(value: unknown, path: string): string | undefined {
  return value === undefined ? undefined : string(value, path);
}

export function integer(value: unknown, path: string, minimum = 0): number {
  if (!Number.isInteger(value) || (value as number) < minimum) fail(path);
  return value as number;
}

export function boundedInteger(value: unknown, path: string, minimum: number, maximum: number): number {
  const result = integer(value, path, minimum);
  if (result > maximum) fail(path);
  return result;
}

export function boolean(value: unknown, path: string): boolean {
  if (typeof value !== 'boolean') fail(path);
  return value;
}

export function array(value: unknown, path: string, maxLength?: number): unknown[] {
  if (!Array.isArray(value) || (maxLength !== undefined && value.length > maxLength)) fail(path);
  return value;
}

export function filterUnsupportedItems(
  value: unknown,
  path: string,
  maxLength: number,
  validate: (item: unknown, itemPath: string) => void,
  minLength = 0,
  onInvalid?: (error: AgentV2ContractError) => void,
) {
  const items = array(value, path, maxLength);
  if (items.length < minLength) fail(path);
  return items.filter((item, index) => {
    try {
      validate(item, `${path}[${index}]`);
      return true;
    } catch (error) {
      if (error instanceof AgentV2CompatibilityError) return false;
      if (error instanceof AgentV2ContractError) {
        onInvalid?.(error);
        return false;
      }
      throw error;
    }
  });
}

export function literal<T extends string | number | boolean>(value: unknown, expected: T, path: string): T {
  if (value !== expected) fail(path);
  return expected;
}

export function oneOf<T extends string>(value: unknown, allowed: ReadonlySet<string>, path: string): T {
  if (typeof value !== 'string' || !allowed.has(value)) fail(path);
  return value as T;
}

export function extensibleOneOf<T extends string>(
  value: unknown,
  allowed: ReadonlySet<string>,
  path: string,
  maxLength = 64,
): T {
  const result = boundedString(value, path, 1, maxLength);
  if (!allowed.has(result)) throw new AgentV2CompatibilityError(path, result);
  return result as T;
}

// An unknown key means a newer shape that this client cannot act on, not a malformed one
export function extensibleKeys(value: JsonObject, path: string, knownKeys: readonly string[]) {
  const known = new Set(knownKeys);
  const unknownKey = Object.keys(value).find((key) => !known.has(key));
  if (unknownKey) throw new AgentV2CompatibilityError(`${path}.${unknownKey}`);
}

export function extensibleLiteral<T extends string | boolean>(value: unknown, expected: T, path: string): T {
  if (typeof expected === 'string') boundedString(value, path, 1, 64);
  else if (typeof value !== typeof expected) fail(path);
  if (value !== expected) {
    throw new AgentV2CompatibilityError(path, typeof value === 'string' ? value : undefined);
  }
  return expected;
}

export function extensibleVersion(value: unknown, supported: number, path: string): number {
  const result = integer(value, path, 1);
  if (result !== supported) throw new AgentV2CompatibilityError(path, undefined, result);
  return result;
}

export function timestamp(value: unknown, path: string): string {
  const result = string(value, path);
  if (!Number.isFinite(Date.parse(result))) fail(path);
  return result;
}
