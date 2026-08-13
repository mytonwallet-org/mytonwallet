import { runInNewContext } from 'vm';

import { toArrayBuffer } from './untrustedBuffer';

const BYTES = [0, 1, 127, 128, 255];

function readBytes(buffer: ArrayBuffer | undefined) {
  return buffer && Array.from(new Uint8Array(buffer));
}

/** A buffer built by another realm's globals, exactly as an extension that patches the API returns one */
function foreignArrayBuffer(bytes: number[]): ArrayBuffer {
  return runInNewContext('new Uint8Array(bytes).buffer', { bytes });
}

describe('toArrayBuffer', () => {
  it('keeps the bytes of a plain buffer', () => {
    expect(readBytes(toArrayBuffer(new Uint8Array(BYTES).buffer))).toEqual(BYTES);
  });

  it('copies the bytes of a view, honouring its offset', () => {
    const view = new Uint8Array([255, ...BYTES, 255]).subarray(1, 1 + BYTES.length);

    expect(readBytes(toArrayBuffer(view))).toEqual(BYTES);
  });

  it('adopts a buffer from another realm, where instanceof does not hold', () => {
    const foreign = foreignArrayBuffer(BYTES);

    expect(foreign instanceof ArrayBuffer).toBe(false);
    expect(readBytes(toArrayBuffer(foreign))).toEqual(BYTES);
  });

  it('adopts a view from another realm', () => {
    const foreign: Uint8Array = runInNewContext('new Uint8Array(bytes)', { bytes: BYTES });

    expect(readBytes(toArrayBuffer(foreign))).toEqual(BYTES);
  });

  it('adopts a view from another realm that carries an offset', () => {
    const foreign: Uint8Array = runInNewContext(
      'new Uint8Array([255, ...bytes, 255]).subarray(1, 1 + bytes.length)',
      { bytes: BYTES },
    );

    expect(readBytes(toArrayBuffer(foreign))).toEqual(BYTES);
  });

  it('adopts a DataView, which declares no element width', () => {
    expect(readBytes(toArrayBuffer(new DataView(new Uint8Array(BYTES).buffer)))).toEqual(BYTES);
  });

  // The shape the 1Password extension returns for PRF results, against the spec (their FS-5593)
  it('rebuilds an array of bytes', () => {
    expect(readBytes(toArrayBuffer(BYTES))).toEqual(BYTES);
  });

  // What JSON does to a typed array: the length getters live on the prototype and do not survive
  it('rebuilds indexed bytes that carry no length', () => {
    const bridged = JSON.parse(JSON.stringify(new Uint8Array(BYTES)));

    expect(bridged.length).toBeUndefined();
    expect(readBytes(toArrayBuffer(bridged))).toEqual(BYTES);
  });

  it('rebuilds indexed bytes that declare a byteLength', () => {
    expect(readBytes(toArrayBuffer({ ...BYTES, byteLength: BYTES.length }))).toEqual(BYTES);
  });

  it.each([
    ['undefined', undefined],
    // eslint-disable-next-line no-null/no-null -- the WebAuthn API returns null for an absent userHandle
    ['null', null],
    ['a boolean returned in place of a secret', true],
    ['a base64 string', 'AQIDBA'],
    ['an empty object', {}],
    ['an object whose declared length outruns its keys', { 0: 1, byteLength: 4 }],
    ['an object with a key past its declared length', { 0: 1, 1: 2, byteLength: 1 }],
    ['a gap in the keys', { 0: 1, 2: 3 }],
    ['non-numeric values', { 0: 'ff', 1: 'ee', byteLength: 2 }],
    ['values that are not bytes', { 0: 258, 1: 5, length: 2 }],
    ['a fractional value', { 0: 1.5, length: 1 }],
    ['a length no secret could have', { byteLength: 2 ** 30 }],
    // The declared length is consistent with the keys the loop reads, and there are keys past it
    ['bytes stranded past a declared length', { 0: 1, 1: 2, 5: 9, length: 2 }],
    // `new Uint8Array(value)` reads an array-like off anything and zero-fills what it cannot find,
    // so a tag alone must not be enough to be read as a buffer
    ['an object that only tags itself as a buffer', { [Symbol.toStringTag]: 'ArrayBuffer', length: 3 }],
    ['a view whose elements are wider than a byte', new Float64Array([1])],
    ['a view of 16-bit elements', new Uint16Array(BYTES)],
  ])('refuses %s', (_name, value) => {
    expect(toArrayBuffer(value)).toBeUndefined();
  });

  // A value from a patched API carries whatever keys its author chose, and counting them must not
  // cost more than reading the bytes would have
  it('refuses a dense prefix buried in far more index keys than a secret could hold', () => {
    const swarm: Record<number, number> = { 0: 1, 1: 2 };
    for (let i = 5; i < 200000; i++) swarm[i] = 0;

    expect(toArrayBuffer(swarm)).toBeUndefined();
  });

  // Non-index keys never advance the tally, so the walk itself carries the bound for them
  it('refuses a dense prefix buried in far more non-index keys than a secret could hold', () => {
    const swarm: Record<string, number> = { 0: 1, 1: 2 };
    for (let i = 0; i < 200000; i++) swarm[`k${i}`] = 0;

    expect(toArrayBuffer(swarm)).toBeUndefined();
  });

  it('does not mistake an empty buffer for a secret', () => {
    // Passed through as-is rather than refused - it is a real buffer, and rejecting a secret of no
    // bytes belongs to the caller that asked for one
    expect(toArrayBuffer(new ArrayBuffer(0))?.byteLength).toBe(0);
  });
});
