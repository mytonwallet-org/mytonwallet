import { getBigInt, TypedDataEncoder } from 'ethers';

import { getSignedTypedDataDomain, getSignedTypedDataMessage } from './typedDataMessage';

type Types = Record<string, Array<{ name: string; type: string }>>;

const CASES = 40_000;
const DOMAIN_CASES = 6000;
const TYPE_NAMES = [
  'A', 'B', 'C', 'D', 'Item[x][1]', 'Item\n', 'bool', 'int', 'uint', 'uint256', 'bytes', 'bytes4', 'string', 'address',
  'toString', '__proto__', 'constructor', '0', 'length', 'A[]', 'A[2]', 'EIP712Domain', 'a:b', ' A', '',
];
const FIELD_NAMES = ['a', 'b', 'c', '0', '1', 'length', 'toString', 'constructor', 'x y', '', 'map'];
const ODD_FIELD_NAMES = [['__proto__'], '__proto__', 5, undefined, ['a'], true];
const VALUE_TYPES = [
  'uint256', 'int8', 'bool', 'string', 'bytes', 'bytes32', 'address', 'int', 'uint', 'uint7', 'bytes33',
];
const SUFFIXES = ['', '', '', '[]', '[1]', '[2]', '[][]', '[x]', '\n[]', ' []', '[]\n', '[ 1]', '[01]'];
const VALUES = [
  '1', 1, ' ', '0x10', true, false, 'false', '', 'abc', '0x', '0x00000000', undefined, {}, [], -1, 1.5, '0b1',
  '0x1111111111111111111111111111111111111111', `0x${'00'.repeat(32)}`,
];
// Hashed by ethers as an address and taken by its signer for a name
const ADDRESS_AS_NAME = '1111111111111111111111111111111111111111';
// What a value type takes, so that structs with fields get accepted often enough to be compared
const TYPED_VALUES: Record<string, unknown[]> = {
  uint256: ['1', 1, '0x10', 5n, ' '],
  int8: ['-1', -1, 1, '0x10'],
  bool: [true, false, 'false', '', 1],
  string: ['abc', '', ' ', '\ud83d\ude00', '\udc00'],
  bytes: ['0x', '0x00000000', new Uint8Array([1, 2])],
  bytes32: [`0x${'00'.repeat(32)}`, new Uint8Array(32)],
  address: [`0x${ADDRESS_AS_NAME}`, `0x${ADDRESS_AS_NAME}`, ADDRESS_AS_NAME],
};
// What `postMessage` passes on and JSON cannot hold
const CLONED_VALUES = [
  5n, -1n, 2n ** 256n, new Uint8Array([1, 2]), new Uint8Array(32), new Map([['a', 1]]), new Set([true]),
  new String('abc'), new Number(1), new Boolean(false), new Date(0), Object.assign([true], { length: 2 }),
];

let seed = 1;
// How often a value goes wrong: fully in the schemas made to break the check, rarely in the well-formed ones
let noise = 1;

function nextRandom() {
  seed = (seed * 1664525 + 1013904223) % 2 ** 32;
  return seed / 2 ** 32;
}

function pickRandom<T>(list: T[]) {
  return list[Math.floor(nextRandom() * list.length)];
}

function isNoise(rate: number) {
  return nextRandom() < rate * noise;
}

function makeLinkedTypes() {
  const names = ['A', 'B', 'C', 'D'].slice(0, 1 + Math.floor(nextRandom() * 4));

  return Object.fromEntries(names.map((name, index) => [name, [
    ...Array.from({ length: 1 + Math.floor(nextRandom() * 3) }, (_, fieldIndex) => ({
      name: `field${fieldIndex}`,
      type: pickRandom(Object.keys(TYPED_VALUES)) + pickRandom(['', '', '[]', '[2]']),
    })),
    ...names.slice(index + 1, index + 2).map((next) => ({ name: 'next', type: next + pickRandom(['', '[]', '[1]']) })),
  ]])) as Types;
}

function makeTypes() {
  const names = new Set<string>();
  const count = 1 + Math.floor(nextRandom() * 4);
  while (names.size < count) names.add(pickRandom(TYPE_NAMES));

  return JSON.parse(JSON.stringify(Object.fromEntries([...names].map((name) => [
    name,
    Array.from({ length: Math.floor(nextRandom() * 4) }, () => ({
      name: nextRandom() < 0.15 ? pickRandom(ODD_FIELD_NAMES) : pickRandom(FIELD_NAMES),
      type: pickRandom(nextRandom() < 0.5 ? VALUE_TYPES : nextRandom() < 0.8 ? [...names] : TYPE_NAMES)
        + pickRandom(SUFFIXES),
    })),
  ])))) as Types;
}

function makeValue(types: Types, type: string, depth: number): unknown {
  if (depth > 8 || isNoise(0.08)) return pickRandom(nextRandom() < 0.8 ? VALUES : CLONED_VALUES);

  const array = /^([^]*)\[(\d*)\]$/.exec(type);
  if (array && !isNoise(0.1)) {
    const length = array[2] && !isNoise(0.2) ? Number(array[2]) : Math.floor(nextRandom() * 3);
    const list = Array.from({ length }, () => makeValue(types, array[1], depth + 1));
    // An array can be longer than its items after `postMessage`
    if (isNoise(0.1)) list.length++;

    return list;
  }

  if (!Object.prototype.hasOwnProperty.call(types, type)) {
    return pickRandom(TYPED_VALUES[type] && !isNoise(0.2) ? TYPED_VALUES[type] : VALUES);
  }

  if (isNoise(0.1)) return pickRandom(VALUES);

  const struct = Object.fromEntries(types[type].filter(() => !isNoise(0.07)).map((field) => [
    field.name,
    makeValue(types, String(field.type), depth + 1),
  ]));

  if (nextRandom() < 0.5) return struct;

  return { ...struct, [pickRandom(['extra', 'token', 'amount', 'a', '0'])]: pickRandom(VALUES) };
}

function toSignedValue(type: string, value: any) {
  if (type === 'bool') return Boolean(value);

  return /^u?int/.test(type) ? getBigInt(value).toString() : value;
}

// The signer has no provider to resolve a name with
function failToResolve(name: string): Promise<string> {
  throw new Error(`Typed data holds a name: ${name}`);
}

describe('getSignedTypedDataMessage against the struct the signer rebuilds', () => {
  it('returns every message it accepts as ethers visits it before signing', async () => {
    let acceptedCount = 0;
    let scalarCount = 0;
    let nestedCount = 0;

    for (let i = 0; i < CASES; i++) {
      const isLinked = i % 8 === 0;
      noise = isLinked ? 0.1 : 1;
      const types = isLinked ? makeLinkedTypes() : makeTypes();

      for (const primaryType of Object.keys(types)) {
        const message = makeValue(types, primaryType, 0) as Record<string, unknown>;
        const shown = getSignedTypedDataMessage(types, primaryType, message);
        if (!shown) continue;

        const { EIP712Domain, ...typesForSigning } = types;
        const encoder = TypedDataEncoder.from(typesForSigning);
        const rebuilt = encoder.visit(shown, toSignedValue);
        const resolved = await TypedDataEncoder.resolveNames({}, typesForSigning, shown, failToResolve);
        const values = Object.values(shown);
        acceptedCount++;
        if (values.some((value) => typeof value !== 'object')) scalarCount++;
        if (values.some((value) => typeof value === 'object')) nestedCount++;

        expect({ primaryType: encoder.primaryType, message: JSON.stringify(rebuilt), hash: encoder.hash(rebuilt) })
          .toEqual({ primaryType, message: JSON.stringify(shown), hash: encoder.hash(message) });
        expect(getSignedTypedDataMessage(types, primaryType, shown)).toEqual(shown);
        expect(resolved.value).toEqual(shown);
        expect(JSON.parse(JSON.stringify(shown))).toEqual(shown);
        // The escape of half a surrogate pair, which a Swift decoder takes for corrupted data
        expect(JSON.stringify(shown)).not.toMatch(/\\ud[89a-f]/);
      }
    }

    expect(acceptedCount).toBeGreaterThan(1000);
    expect(scalarCount).toBeGreaterThan(1000);
    expect(nestedCount).toBeGreaterThan(1000);
  });
});

describe('getSignedTypedDataDomain against the domain the signer hashes', () => {
  const order = { Order: [{ name: 'id', type: 'uint256' }] };
  const domainValues: Record<string, unknown[]> = {
    name: TYPED_VALUES.string,
    version: TYPED_VALUES.string,
    chainId: [...TYPED_VALUES.uint256, '0x89', 137],
    verifyingContract: TYPED_VALUES.address,
    salt: TYPED_VALUES.bytes32,
  };

  // Whether the signer signs the domain as sent and a native confirmation can decode it
  async function isSignedAsSent(sent: Record<string, unknown>) {
    try {
      TypedDataEncoder.hashDomain(sent);
      await TypedDataEncoder.resolveNames(sent, order, { id: 1 }, failToResolve);
    } catch {
      return false;
    }

    return ![sent.name, sent.version].some((text) => typeof text === 'string' && /[\ud800-\udfff]/u.test(text));
  }

  it('returns every domain the signer signs, as ethers hashes it', async () => {
    let acceptedCount = 0;
    let refusedCount = 0;
    noise = 1;

    for (let i = 0; i < DOMAIN_CASES; i++) {
      const sent: Record<string, unknown> = {};
      for (const [name, values] of Object.entries(domainValues)) {
        if (!isNoise(0.5)) continue;

        // eslint-disable-next-line no-null/no-null -- typed data arrives as JSON
        sent[name] = isNoise(0.1) ? pickRandom([...VALUES, ...CLONED_VALUES, null]) : pickRandom(values);
      }
      if (isNoise(0.03)) sent[pickRandom(['other', 'toString', 'Name'])] = pickRandom(VALUES);

      const shown = getSignedTypedDataDomain(sent);
      expect(Boolean(shown)).toBe(await isSignedAsSent(sent));
      if (!shown) {
        refusedCount++;
        continue;
      }

      const resolved = await TypedDataEncoder.resolveNames(shown, order, { id: 1 }, failToResolve);
      acceptedCount++;

      expect(TypedDataEncoder.hashDomain(shown)).toBe(TypedDataEncoder.hashDomain(sent));
      expect(resolved.domain).toEqual(shown);
      expect(getSignedTypedDataDomain(shown)).toEqual(shown);
      expect(Object.values(shown).every((value) => typeof value === 'string')).toBe(true);
    }

    expect(acceptedCount).toBeGreaterThan(1000);
    expect(refusedCount).toBeGreaterThan(1000);
  });
});
