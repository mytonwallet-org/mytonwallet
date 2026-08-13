/**
 * Nothing that comes back from `navigator.credentials` is guaranteed to be built by this realm's
 * globals. A browser extension may replace the API - 1Password does, and says so in the console -
 * and then the binaries arrive from its context, where `instanceof ArrayBuffer` is false, or from
 * across a bridge that dropped the type on the way. Reaching for `.buffer` on one of those throws
 * a TypeError far from the cause, so every value such an API hands over is normalized here, at the
 * boundary, and the rest of the enclave only ever holds an ArrayBuffer of this realm.
 *
 * Every rejection is deliberate. A value this module cannot read as a dense sequence of bytes is
 * refused rather than approximated: a secret that is quietly truncated, zero-filled or reinterpreted
 * would encrypt the wallet under a key nothing can reproduce, which is worse than one that fails
 * loudly at the boundary.
 */

/** Bounds the reconstruction loop below, the only path that allocates from an attacker-chosen count */
const MAX_INDEXED_BYTES = 1024;

/** Bounds the key walk in `countIndexKeys`: no honest byte sequence arrives with more keys than this */
const MAX_ENUMERATED_KEYS = 4096;

export function toArrayBuffer(value: unknown): ArrayBuffer | undefined {
  if (value instanceof ArrayBuffer) {
    return value;
  }

  // `isView` and the TypedArray constructor read internal slots rather than the prototype chain,
  // which is what keeps them working on a buffer minted in another realm
  if (ArrayBuffer.isView(value)) {
    return isByteWide(value)
      ? copyBytes(new Uint8Array(value.buffer, value.byteOffset, value.byteLength))
      : undefined;
  }

  if (isForeignArrayBuffer(value)) {
    return copyBytes(new Uint8Array(value));
  }

  const bytes = bytesFromIndexed(value);
  return bytes && copyBytes(bytes);
}

/**
 * A view of anything wider than a byte carries element semantics this module cannot honour: its
 * bytes are the platform-endian encoding of its elements, not the sequence the producer meant.
 * `DataView` declares no element width and is a byte view by definition.
 */
function isByteWide(view: ArrayBufferView) {
  const { BYTES_PER_ELEMENT } = view as { BYTES_PER_ELEMENT?: number };

  return BYTES_PER_ELEMENT === undefined || BYTES_PER_ELEMENT === 1;
}

/**
 * `slice` reads the internal slot every ArrayBuffer carries and no object can imitate, so it tells
 * a buffer minted in another realm apart from one merely shaped like it. A `Symbol.toStringTag` of
 * `ArrayBuffer` is writable by anyone, and an impostor carrying a `length` would pass through
 * `new Uint8Array(...)` as an array-like and come back zero-filled.
 */
function isForeignArrayBuffer(value: unknown): value is ArrayBuffer {
  try {
    ArrayBuffer.prototype.slice.call(value as ArrayBuffer, 0, 0);
    return true;
  } catch {
    return false;
  }
}

function copyBytes(bytes: Uint8Array): ArrayBuffer {
  return bytes.slice().buffer;
}

/**
 * A binary that lost its type on the way arrives as bytes under numeric keys: an Array, which is
 * what the 1Password extension hands back for PRF results (their FS-5593), or a bare
 * `{ "0": 12, "1": 240 }`, which is what JSON does to a typed array - note it keeps no length,
 * since `length` and `byteLength` are prototype getters that do not serialize.
 *
 * A declared length the keys do not fill, a gap in the keys, a key beyond them, a value outside a
 * byte: each means the value is not the dense byte sequence it was read as.
 */
function bytesFromIndexed(value: unknown): Uint8Array | undefined {
  if (!value || typeof value !== 'object') {
    return undefined;
  }

  const source = value as Record<number, unknown> & { length?: unknown; byteLength?: unknown };
  const declaredLength = typeof source.byteLength === 'number' ? source.byteLength
    : typeof source.length === 'number' ? source.length
      : undefined;

  if (declaredLength !== undefined
    && (!Number.isInteger(declaredLength) || declaredLength <= 0 || declaredLength > MAX_INDEXED_BYTES)) {
    return undefined;
  }

  const bytes: number[] = [];
  for (let i = 0; i <= MAX_INDEXED_BYTES; i++) {
    const byte = source[i];
    if (byte === undefined) break;

    if (!Number.isInteger(byte) || (byte as number) < 0 || (byte as number) > 0xFF) {
      return undefined;
    }

    bytes.push(byte as number);
  }

  if (!bytes.length || bytes.length > MAX_INDEXED_BYTES) {
    return undefined;
  }

  // Both counts are compared every time: a declared length that agrees says nothing about the keys
  // beyond it, and those keys are bytes the caller meant to hand over
  if (countIndexKeys(source, bytes.length) !== bytes.length
    || (declaredLength !== undefined && declaredLength !== bytes.length)) {
    return undefined;
  }

  return new Uint8Array(bytes);
}

/**
 * Counts without materializing the key list. Two stops bound the walk: the tally stops as soon as
 * the count of index keys can no longer match, and the enumeration itself gives up on an object
 * carrying more keys of any kind than a secret could explain - a value from a patched API is free
 * to arrive with millions of them, and walking those would stall the auth flow.
 */
function countIndexKeys(source: object, limit: number) {
  let count = 0;
  let visited = 0;

  for (const key in source) {
    if (++visited > MAX_ENUMERATED_KEYS) return -1;
    if (!Object.prototype.hasOwnProperty.call(source, key) || !/^\d+$/.test(key)) continue;
    if (++count > limit) break;
  }

  return count;
}
