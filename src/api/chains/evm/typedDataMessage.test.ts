import { getIcapAddress, TypedDataEncoder } from 'ethers';

import { getSignedTypedData, getSignedTypedDataDomain, getSignedTypedDataMessage } from './typedDataMessage';

const TOKEN = '0x5555555555555555555555555555555555555555';
const SPENDER = '0x4444444444444444444444444444444444444444';

const types = {
  PermitBatch: [
    { name: 'details', type: 'PermitDetails[]' },
    { name: 'spender', type: 'address' },
  ],
  PermitDetails: [
    { name: 'token', type: 'address' },
    { name: 'amount', type: 'uint160' },
  ],
};
const message = { details: [{ token: TOKEN, amount: '1' }, { token: TOKEN, amount: '2' }], spender: SPENDER };

describe('getSignedTypedDataMessage', () => {
  it('returns the message of the struct that gets signed', () => {
    expect(getSignedTypedDataMessage(types, 'PermitBatch', message)).toEqual(message);
  });

  it('returns the types as it checked them, without the domain type and what a field holds besides its names', () => {
    const noted = {
      ...types,
      EIP712Domain: [{ name: 'name', type: 'string' }],
      PermitDetails: types.PermitDetails.map((field) => ({ ...field, note: 'unchecked' })),
    };

    expect(getSignedTypedData(noted, 'PermitBatch', message)).toEqual({ types, message });
  });

  it('ignores the declared domain type, as signing does', () => {
    const withDomain = { ...types, EIP712Domain: [{ name: 'name', type: 'string' }] };

    expect(getSignedTypedDataMessage(withDomain, 'PermitBatch', message)).toEqual(message);
    expect(getSignedTypedDataMessage(withDomain, 'EIP712Domain', message)).toBeUndefined();
  });

  it.each(['PermitDetails', 'Missing', 'toString', ''])('refuses primary type %p', (primaryType) => {
    expect(getSignedTypedDataMessage(types, primaryType, message)).toBeUndefined();
  });

  it('leaves out the keys that are not signed without changing the hash', () => {
    const padded = {
      ...message,
      details: message.details.map((item) => ({ ...item, note: 'unsigned' })),
      token: TOKEN,
    };

    const signedMessage = getSignedTypedDataMessage(types, 'PermitBatch', padded)!;

    expect(signedMessage).toEqual(message);
    expect(TypedDataEncoder.hash({}, types, signedMessage)).toBe(TypedDataEncoder.hash({}, types, padded));
  });

  it.each([
    ['two unrelated structs', { A: [{ name: 'x', type: 'uint256' }], B: [{ name: 'y', type: 'uint256' }] }, 'A'],
    ['a type cycle', { A: [{ name: 'b', type: 'B' }], B: [{ name: 'a', type: 'A' }] }, 'A'],
    ['an unknown field type', { A: [{ name: 'x', type: 'Missing' }] }, 'A'],
    ['fields that are not a list', { A: 'x' }, 'A'],
  ])('refuses %s', (_, malformedTypes, primaryType) => {
    expect(getSignedTypedDataMessage(malformedTypes as never, primaryType, {})).toBeUndefined();
  });

  it('refuses a value that cannot be hashed', () => {
    const unhashable = { details: [{ token: TOKEN, amount: 'one' }], spender: SPENDER };

    expect(getSignedTypedDataMessage(types, 'PermitBatch', unhashable)).toBeUndefined();
  });

  it.each([
    ['a field', '{"Permit":[{"name":"__proto__","type":"bool"},{"name":"value","type":"uint256"}]}'],
    ['a field with a list', '{"Permit":[{"name":["__proto__"],"type":"bool"},{"name":"value","type":"uint256"}]}'],
    ['a struct', '{"Permit":[{"name":"value","type":"uint256"}],"__proto__":[{"name":"value","type":"uint256"}]}'],
  ])('refuses %s named `__proto__`, which signing drops', (_, typesJson) => {
    const sent = JSON.parse('{"__proto__":false,"value":"1"}') as Record<string, unknown>;

    expect(getSignedTypedDataMessage(JSON.parse(typesJson), 'Permit', sent)).toBeUndefined();
  });

  it.each([
    [' ', '0'], ['0x10', '16'], ['0b101', '5'], [' 12 ', '12'], [16, '16'], ['-0x5', '-5'],
  ])('returns integer value %p as the %p that gets signed', (value, signedValue) => {
    const order = { Order: [{ name: 'amount', type: 'int256' }, { name: 'amounts', type: 'int[2]' }] };
    const sent = { amount: value, amounts: [value, value] };

    const signedMessage = getSignedTypedDataMessage(order, 'Order', sent)!;

    expect(signedMessage).toEqual({ amount: signedValue, amounts: [signedValue, signedValue] });
    expect(TypedDataEncoder.hash({}, order, signedMessage)).toBe(TypedDataEncoder.hash({}, order, sent));
  });

  it.each([
    ['Item\n[]', 'Item\n', [{ amount: '5' }]],
    ['Item[x][1]', 'Item[x][1]', undefined],
    ['Item[\u0663]', 'Item[\u0663]', undefined],
  ])('reads field type %j as ethers does, or refuses it', (type, structName, signedItems) => {
    const order = { Order: [{ name: 'items', type }], [structName]: [{ name: 'amount', type: 'uint256' }] };
    const items = Object.assign([{ amount: '5', token: TOKEN }], { amount: '0' });

    expect(getSignedTypedDataMessage(order, 'Order', { items })).toEqual(signedItems && { items: signedItems });
  });

  it('refuses a struct named as a value type, which ethers signs in its place', () => {
    const named = { bool: [{ name: 'token', type: 'address' }, { name: 'amount', type: 'uint256' }] };

    expect(getSignedTypedDataMessage(named, 'bool', { token: TOKEN, amount: '5' })).toBeUndefined();
  });

  it('refuses more text than it hashes before the confirmation', () => {
    const note = { Note: [{ name: 'text', type: 'string' }] };

    expect(getSignedTypedDataMessage(note, 'Note', { text: 'a'.repeat(1_999_996) })).toBeDefined();
    expect(getSignedTypedDataMessage(note, 'Note', { text: 'a'.repeat(1_999_997) })).toBeUndefined();
  });

  it('refuses types longer than ethers goes over quickly, counting a struct name again with each field', () => {
    const note = (name: string) => ({ [name]: [{ name: 'text', type: 'string' }] });
    const name = (length: number) => 'N'.repeat(length);

    expect(getSignedTypedDataMessage(note(name(24_994)), name(24_994), { text: '' })).toBeDefined();
    expect(getSignedTypedDataMessage(note(name(24_995)), name(24_995), { text: '' })).toBeUndefined();
    expect(getSignedTypedDataMessage({ [name(50_000)]: [] }, name(50_000), {})).toEqual({});
    expect(getSignedTypedDataMessage({ [name(50_001)]: [] }, name(50_001), {})).toBeUndefined();
  });

  it('counts a field type again for each of its array dimensions', () => {
    const lists = (depth: number) => ({ Lists: [{ name: 'a', type: `bool${'[]'.repeat(depth)}` }] });

    expect(getSignedTypedDataMessage(lists(156), 'Lists', { a: [] })).toEqual({ a: [] });
    expect(getSignedTypedDataMessage(lists(157), 'Lists', { a: [] })).toBeUndefined();
  });

  it.each([
    ['\u00e9', true],
    ['e\u0301', false],
  ])('takes field name %j only in the Unicode form the iOS confirmation tells from others', (name, isSigned) => {
    const signedMessage = getSignedTypedDataMessage({ Order: [{ name, type: 'uint256' }] }, 'Order', { [name]: '1' });

    expect(signedMessage).toEqual(isSigned ? { [name]: '1' } : undefined);
  });

  it.each([
    ['\u00e9', true],
    ['e\u0301', false],
  ])('takes struct name %j only in the Unicode form the iOS confirmation tells from others', (name, isSigned) => {
    const order = { [name]: [{ name: 'amount', type: 'uint256' }] };
    const signedMessage = getSignedTypedDataMessage(order, name, { amount: '1' });

    expect(signedMessage).toEqual(isSigned ? { amount: '1' } : undefined);
    expect(getSignedTypedDataMessage({ [name]: [] }, name, {})).toEqual(isSigned ? {} : undefined);
  });

  it.each([
    ['[]', {}, ''],
    ['[][]', [], '[]'],
  ])('reads the item type of a list typed with %s once, not for each of its items', (suffix, item, itemSuffix) => {
    const name = 'N'.repeat(1000);
    const list = { List: [{ name: 'items', type: `${name}${suffix}` }], [name]: [] };
    const items = Array.from({ length: 50 }, () => item);
    const exec = jest.spyOn(RegExp.prototype, 'exec');

    const signedMessage = getSignedTypedDataMessage(list, 'List', { items });
    const itemTypeReadCount = exec.mock.calls.filter(([text]) => text === `${name}${itemSuffix}`).length;
    exec.mockRestore();

    expect(signedMessage).toEqual({ items });
    expect(itemTypeReadCount).toBeLessThan(items.length);
  });

  it('counts the dimensions of a field type only if the type fits the limit', () => {
    const type = '['.repeat(50_000);
    const split = jest.spyOn(String.prototype, 'split');

    const signedMessage = getSignedTypedDataMessage({ Lists: [{ name: 'a', type }] }, 'Lists', {});
    const isTypeSplit = split.mock.contexts.some((text) => String(text) === type);
    split.mockRestore();

    expect(signedMessage).toBeUndefined();
    expect(isTypeSplit).toBe(false);
  });

  it('counts the struct types before it reads any of them', () => {
    let readCount = 0;
    const many = {};
    for (let i = 0; i <= 20; i++) {
      Object.defineProperty(many, `Type${i}`, {
        enumerable: true,
        get: () => {
          readCount++;

          return [];
        },
      });
    }

    expect(getSignedTypedDataMessage(many, 'Type0', {})).toBeUndefined();
    expect(readCount).toBe(0);
  });

  it('stops reading the fields once the types are too long', () => {
    let readCount = 0;
    const field = {
      get name() {
        readCount++;

        return '';
      },
      type: '',
    };

    expect(getSignedTypedDataMessage({ '': Array.from({ length: 60_000 }, () => field) }, '', {})).toBeUndefined();
    expect(readCount).toBeLessThanOrEqual(50_001);
  });

  it.each([
    ['bytes', new Uint8Array([1, 2, 3]), '0x010203'],
    ['bytes4', new Uint8Array([1, 2, 3, 4]), '0x01020304'],
    ['bytes', new Uint8Array(0), '0x'],
  ])('returns an array of bytes for %s as the hex that gets signed', (type, bytes, hex) => {
    const note = { Note: [{ name: 'data', type }] };
    const signedMessage = getSignedTypedDataMessage(note, 'Note', { data: bytes });

    expect(signedMessage).toEqual({ data: hex });
    expect(TypedDataEncoder.hash({}, note, signedMessage!)).toBe(TypedDataEncoder.hash({}, note, { data: bytes }));
  });

  it.each(['string', 'address', 'bytes4'])('refuses an array of bytes that %s does not hold', (type) => {
    const note = { Note: [{ name: 'data', type }] };

    expect(getSignedTypedDataMessage(note, 'Note', { data: new Uint8Array([1, 2, 3]) })).toBeUndefined();
  });

  it('counts the hex of an array of bytes as text', () => {
    const notes = { Notes: [{ name: 'first', type: 'bytes' }, { name: 'second', type: 'bytes' }] };
    const bytes = new Uint8Array(600_000);

    expect(getSignedTypedDataMessage(notes, 'Notes', { first: bytes, second: '0x' })).toBeDefined();
    expect(getSignedTypedDataMessage(notes, 'Notes', { first: bytes, second: bytes })).toBeUndefined();
  });

  it('refuses an array of bytes longer than the text it may return before reading it', () => {
    let readCount = 0;
    const bytes = new Proxy(new Uint8Array(1_000_000), {
      get: (target, key) => {
        readCount++;

        return Reflect.get(target, key);
      },
    });

    const note = { Note: [{ name: 'data', type: 'bytes' }] };

    expect(getSignedTypedDataMessage(note, 'Note', { data: bytes })).toBeUndefined();
    expect(readCount).toBeLessThan(10);
  });

  it.each(['string', 'address', 'bytes', 'bytes32'])('refuses a bigint for %s before ethers writes it out', (type) => {
    const writeOut = jest.spyOn(BigInt.prototype, 'toString');

    const signedMessage = getSignedTypedDataMessage({ Note: [{ name: 'text', type }] }, 'Note', { text: 5n });
    const writeOutCount = writeOut.mock.calls.length;
    writeOut.mockRestore();

    expect(signedMessage).toBeUndefined();
    expect(writeOutCount).toBe(0);
  });

  it('counts only the names in the types and hands ethers nothing else of them', () => {
    const note = { Note: [{ name: 'text', type: 'string', comment: 'a'.repeat(60_000) }] };
    const from = jest.spyOn(TypedDataEncoder, 'from');

    const signedMessage = getSignedTypedDataMessage(note, 'Note', { text: '' });
    const [typesForSigning] = from.mock.calls[0];
    from.mockRestore();

    expect(signedMessage).toEqual({ text: '' });
    expect(typesForSigning).toEqual({ Note: [{ name: 'text', type: 'string' }] });
  });

  it('refuses fields that are not a list, which a confirmation cannot read', () => {
    const flag = { Flag: new Set([{ name: 'on', type: 'bool' }]) as unknown as Array<{ name: string; type: string }> };

    expect(getSignedTypedDataMessage(flag, 'Flag', { on: true })).toBeUndefined();
  });

  it('refuses a field type that is not a string', () => {
    const flag = { Flag: [{ name: 'on', type: new String('bool') as unknown as string }] };

    expect(getSignedTypedDataMessage(flag, 'Flag', { on: true })).toBeUndefined();
  });

  it('refuses types that are not a plain object', () => {
    const bare = Object.assign(Object.create({}), types) as typeof types;

    expect(getSignedTypedDataMessage(bare, 'PermitBatch', message)).toBeUndefined();
  });

  it('refuses a list that is longer than its items', () => {
    const list = { List: [{ name: 'flags', type: 'bool[]' }] };
    const flags = [true];
    flags.length = 2;

    expect(getSignedTypedDataMessage(list, 'List', { flags: [true] })).toEqual({ flags: [true] });
    expect(getSignedTypedDataMessage(list, 'List', { flags })).toBeUndefined();
  });

  it('refuses what is no array for a list without going through it', () => {
    const list = { List: [{ name: 'flags', type: 'bool[]' }] };
    const flags = 'true';
    const iterate = jest.spyOn(String.prototype, Symbol.iterator);

    const results = [flags, new Set([true]), new Uint8Array(1), { 0: true, length: 1 }]
      .map((value) => getSignedTypedDataMessage(list, 'List', { flags: value as unknown as boolean[] }));
    const iteratedTexts = iterate.mock.contexts.map(String);
    iterate.mockRestore();

    expect(results).toEqual([undefined, undefined, undefined, undefined]);
    expect(iteratedTexts).not.toContain(flags);
  });

  it('refuses an address the signer would take for a name', () => {
    const order = { Order: [{ name: 'to', type: 'address' }] };
    const hex = '1111111111111111111111111111111111111111';

    expect(getSignedTypedDataMessage(order, 'Order', { to: `0x${hex}` })).toEqual({ to: `0x${hex}` });
    expect(getSignedTypedDataMessage(order, 'Order', { to: hex })).toBeUndefined();
    expect(getSignedTypedDataMessage(order, 'Order', { to: getIcapAddress(`0x${hex}`) })).toBeUndefined();
  });

  it('refuses an integer longer than any 256-bit one', () => {
    const order = { Order: [{ name: 'amount', type: 'int256' }] };
    const minimum = '-57896044618658097711785492504343953926634992332820282019728792003956564819968';
    const zeros = '0'.repeat(255);

    expect(getSignedTypedDataMessage(order, 'Order', { amount: `-0b1${zeros}` })).toEqual({ amount: minimum });
    expect(getSignedTypedDataMessage(order, 'Order', { amount: `-0b01${zeros}` })).toBeUndefined();
  });

  it('refuses a bigint longer than any 256-bit one before writing it out', () => {
    const order = { Order: [{ name: 'amount', type: 'uint256' }] };
    const writeOut = jest.spyOn(BigInt.prototype, 'toString');

    const longest = getSignedTypedDataMessage(order, 'Order', { amount: 2n ** 256n - 1n });
    const writeOutCount = writeOut.mock.calls.length;
    const longer = getSignedTypedDataMessage(order, 'Order', { amount: 2n ** 256n });
    const isLongerWrittenOut = writeOut.mock.calls.length > writeOutCount;
    writeOut.mockRestore();

    expect(longest).toEqual({ amount: (2n ** 256n - 1n).toString() });
    expect(longer).toBeUndefined();
    expect(isLongerWrittenOut).toBe(false);
  });

  it('counts a field name each time the message it returns repeats it', () => {
    const list = { List: [{ name: 'items', type: 'Item[]' }], Item: [{ name: 'a'.repeat(1000), type: 'bool' }] };
    const items = (count: number) => ({ items: Array.from({ length: count }, () => ({})) });

    expect(getSignedTypedDataMessage(list, 'List', items(1999))).toBeDefined();
    expect(getSignedTypedDataMessage(list, 'List', items(2000))).toBeUndefined();
  });

  it.each([
    [1_999_990, true],
    [1_999_991, false],
  ])('returns a message with %i characters of text only if it accepts it again', (length, isAccepted) => {
    const note = { Note: [{ name: 'text', type: 'string' }, { name: 'count', type: 'uint8' }] };
    const shown = getSignedTypedDataMessage(note, 'Note', { text: 'a'.repeat(length), count: 1 });

    expect(Boolean(shown)).toBe(isAccepted);
    expect(shown && getSignedTypedDataMessage(note, 'Note', shown)).toEqual(shown);
  });

  it('refuses a message with more values than it copies before the confirmation', () => {
    const list = { List: [{ name: 'items', type: 'uint8[]' }] };
    const items = (count: number) => ({ items: Array.from({ length: count }, () => '1') });

    expect(getSignedTypedDataMessage(list, 'List', items(24_998))).toEqual(items(24_998));
    expect(getSignedTypedDataMessage(list, 'List', items(24_999))).toBeUndefined();
  });

  it('returns a tree of structs in nested arrays of fixed size, as a bulk order sends them', () => {
    const bulk = { ...types, BulkOrder: [{ name: 'tree', type: 'PermitBatch[2][2]' }] };
    const tree = { tree: [[message, message], [message, message]] };

    expect(getSignedTypedDataMessage(bulk, 'BulkOrder', tree)).toEqual(tree);
    expect(getSignedTypedDataMessage(bulk, 'BulkOrder', { tree: [[message, message], [message]] })).toBeUndefined();
  });

  it('refuses a type graph with more paths than ethers walks quickly', () => {
    const graph = (size: number) => Object.fromEntries(Array.from({ length: size }, (_, index) => [
      `T${index}`,
      Array.from({ length: size - index - 1 }, (__, offset) => (
        { name: `f${offset}`, type: `T${index + offset + 1}` }
      )),
    ]));
    const value = (size: number, index = 0): Record<string, unknown> => Object.fromEntries(
      Array.from({ length: size - index - 1 }, (_, offset) => [`f${offset}`, value(size, index + offset + 1)]),
    );

    expect(getSignedTypedDataMessage(graph(10), 'T0', value(10))).toEqual(value(10));
    expect(getSignedTypedDataMessage(graph(11), 'T0', value(11))).toBeUndefined();
  });

  it('refuses a field name that is not a string, which a native confirmation cannot decode', () => {
    const flags = JSON.parse('{"Flags":[{"name":5,"type":"bool"}]}');

    expect(getSignedTypedDataMessage(flags, 'Flags', { 5: true })).toBeUndefined();
  });

  it.each(['string', 'uint256'])('refuses an object for %s before ethers puts it into an error message', (type) => {
    let readCount = 0;
    const text = {
      get nested() {
        readCount++;

        return 'text';
      },
    };

    expect(getSignedTypedDataMessage({ Note: [{ name: 'text', type }] }, 'Note', { text })).toBeUndefined();
    expect(readCount).toBe(0);
  });

  it('refuses more struct types than ethers resolves quickly', () => {
    function chainOfTypes(count: number) {
      return Object.fromEntries(Array.from({ length: count }, (_, index) => [
        `T${index}`,
        [index + 1 < count ? { name: 'next', type: `T${index + 1}` } : { name: 'value', type: 'uint256' }],
      ]));
    }
    function chainMessage(count: number): Record<string, unknown> {
      return count === 1 ? { value: '1' } : { next: chainMessage(count - 1) };
    }

    expect(getSignedTypedDataMessage(chainOfTypes(20), 'T0', chainMessage(20))).toEqual(chainMessage(20));
    expect(getSignedTypedDataMessage(chainOfTypes(21), 'T0', chainMessage(21))).toBeUndefined();
  });

  it('refuses a struct value that is not an object', () => {
    // eslint-disable-next-line no-null/no-null -- dApps send JSON
    expect(getSignedTypedDataMessage(types, 'PermitBatch', { details: [null], spender: SPENDER })).toBeUndefined();
    expect(getSignedTypedDataMessage(types, 'PermitBatch', { details: {}, spender: SPENDER })).toBeUndefined();
  });

  it.each([5, 'on', true, [true]])('refuses %p sent for a struct of flags', (value) => {
    const order = { Order: [{ name: 'flags', type: 'Flags' }], Flags: [{ name: 'isOpen', type: 'bool' }] };

    expect(getSignedTypedDataMessage(order, 'Order', { flags: {} })).toEqual({ flags: { isOpen: false } });
    expect(getSignedTypedDataMessage(order, 'Order', { flags: value as unknown as object })).toBeUndefined();
  });

  it.each([['\udc00', false], ['\ud83d\ude00', true]])('takes %j in a name and in a text: %p', (text, isTaken) => {
    const named = { Order: [{ name: `flag${text}`, type: 'bool' }] };
    const noted = { Order: [{ name: 'note', type: 'string' }] };

    expect(Boolean(getSignedTypedDataMessage(named, 'Order', { [`flag${text}`]: true }))).toBe(isTaken);
    expect(Boolean(getSignedTypedDataMessage({ [`Order${text}`]: [] }, `Order${text}`, {}))).toBe(isTaken);
    expect(Boolean(getSignedTypedDataMessage(noted, 'Order', { note: `to ${text} be` }))).toBe(isTaken);
  });

  it.each([
    ['false', true], ['0', true], [1, true], [true, true], [false, false], [0, false], ['', false], [undefined, false],
  ])('returns bool value %p as the %p that gets signed', (value, signedValue) => {
    const permit = { Permit: [{ name: 'allowed', type: 'bool' }, { name: 'flags', type: 'bool[]' }] };
    const sent = { allowed: value, flags: [value] };

    const signedMessage = getSignedTypedDataMessage(permit, 'Permit', sent)!;

    expect(signedMessage).toEqual({ allowed: signedValue, flags: [signedValue] });
    expect(TypedDataEncoder.hash({}, permit, signedMessage)).toBe(TypedDataEncoder.hash({}, permit, sent));
  });

  it('refuses a missing field that resolves to an inherited method', () => {
    const inherited = { A: [{ name: 'toString', type: 'string' }] };

    expect(getSignedTypedDataMessage(inherited, 'A', {})).toBeUndefined();
    expect(getSignedTypedDataMessage(inherited, 'A', { toString: 'text' })).toEqual({ toString: 'text' });
  });
});

describe('getSignedTypedDataDomain', () => {
  const SALT = `0x${'ab'.repeat(32)}`;
  const domain = { name: 'Token', version: '1', chainId: 1, verifyingContract: TOKEN, salt: SALT };

  it('returns the fields that get signed, with the chain id as a decimal', () => {
    // eslint-disable-next-line no-null/no-null -- typed data arrives as JSON
    const sent = { ...domain, chainId: '0x89', version: null, other: undefined };

    const signedDomain = getSignedTypedDataDomain(sent)!;

    expect(signedDomain).toEqual({ name: 'Token', chainId: '137', verifyingContract: TOKEN, salt: SALT });
    expect(TypedDataEncoder.hashDomain(signedDomain)).toBe(TypedDataEncoder.hashDomain(sent));
    expect(getSignedTypedDataDomain(signedDomain)).toEqual(signedDomain);
  });

  it('returns a salt sent as an array of bytes as its hex', () => {
    const sent = { salt: new Uint8Array(32).fill(0xab) };

    expect(getSignedTypedDataDomain(sent)).toEqual({ salt: SALT });
  });

  it.each([
    [[]], [new Uint8Array(0)], [new Map()], [undefined], ['Token'],
  ])('refuses %p, which a native confirmation cannot decode as a domain', (sent) => {
    expect(getSignedTypedDataDomain(sent as unknown as Record<string, unknown>)).toBeUndefined();
  });

  it.each([
    { name: '\udc00' },
    { name: 7 },
    { version: { text: '1' } },
    { chainId: 1.5 },
    { chainId: true },
    { chainId: -1 },
    { verifyingContract: TOKEN.slice(2) },
    { verifyingContract: getIcapAddress(TOKEN) },
    { salt: '0xab' },
    { other: 'unsigned' },
  ])('refuses the domain field %p, which does not get signed as it is shown', (field) => {
    expect(getSignedTypedDataDomain({ ...domain, ...field })).toBeUndefined();
  });
});
