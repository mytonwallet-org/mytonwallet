import { getBigInt, hexlify, TypedDataEncoder } from 'ethers';

import { buildTypedDataDomainType } from './typedDataDomain';

type TypedDataTypes = Record<string, Array<{ name: string; type: string }>>;
type Budget = { valuesLeft: number; textLeft: number; elementTypes: Map<string, string | undefined> };

// The text of a struct repeats in every struct that refers to it, and ethers goes over the name of a struct for
// each of its fields, so that name counts once more with each field
const MAX_STRUCT_TYPES = 20;
const MAX_TYPES_LENGTH = 50_000;
// Every path of the type graph is walked by ethers, and each type that refers to all the later ones doubles them
const MAX_TYPE_VISITS = 1000;
// The message is copied and hashed before the user confirms anything
const MAX_MESSAGE_VALUES = 25_000;
const MAX_TEXT_LENGTH = 2_000_000;
// Splits an array type exactly as ethers does, so that both read the same element type
const ARRAY_TYPE_REGEX = /^([^[]*(?:\[\d*\])*)\[\d*\]$/;
const INTEGER_TYPE_REGEX = /^u?int\d*$/;
// An address in any other form is hashed by ethers, but its signer takes it for a name, which it cannot resolve
const ADDRESS_REGEX = /^0x[0-9a-fA-F]{40}$/;
// Half of a surrogate pair is hashed by ethers, and the iOS confirmation cannot decode a request that holds one
const LONE_SURROGATE_REGEX = /[\uD800-\uDFFF]/u;
// A 256-bit integer takes at most this many characters, in binary with a sign, and a longer string is slow to convert
const MAX_INTEGER_LENGTH = 259;
const MAX_INTEGER_BITS = 257;
// The first names are read by ethers as value types whatever struct they declare, and a confirmation reads a
// bracket as the end of an array type where ethers reads a part of the name
const UNSIGNABLE_STRUCT_NAME_REGEX = /^(address|bool|string|bytes\d*|u?int\d+)$|[[\]]/;

// The signed part of `message`, or `undefined` when ethers would sign another struct than `primaryType`: it hashes
// the one type no other type refers to, and of the message only the fields the types declare
export function getSignedTypedDataMessage(
  types: TypedDataTypes,
  primaryType: string,
  message: Record<string, unknown>,
): Record<string, unknown> | undefined {
  return getSignedTypedData(types, primaryType, message)?.message;
}

// The same with the types as they were checked, for a confirmation to read nothing else of the request
export function getSignedTypedData(
  types: TypedDataTypes,
  primaryType: string,
  message: Record<string, unknown>,
): { types: TypedDataTypes; message: Record<string, unknown> } | undefined {
  try {
    // A typed array, which `postMessage` passes on, would be listed here byte by byte
    if (Object.getPrototypeOf(types) !== Object.prototype) return undefined;

    const structNames = Object.keys(types).filter((name) => name !== 'EIP712Domain');
    if (structNames.length > MAX_STRUCT_TYPES) return undefined;

    const typesForSigning = copyTypes(types, structNames);
    const visitCounts = new Map<string, number>();

    if (structNames.some((name) => (
      UNSIGNABLE_STRUCT_NAME_REGEX.test(name)
      || countTypeVisits(typesForSigning, name, visitCounts) > MAX_TYPE_VISITS
    ))) {
      return undefined;
    }

    const encoder = TypedDataEncoder.from(typesForSigning);
    if (encoder.primaryType !== primaryType) return undefined;

    const budget = { valuesLeft: MAX_MESSAGE_VALUES, textLeft: MAX_TEXT_LENGTH, elementTypes: new Map() };
    const signedMessage = pickSignedValue(typesForSigning, primaryType, message, budget) as Record<string, unknown>;

    return encoder.hash(signedMessage) === encoder.hash(message)
      ? { types: typesForSigning, message: signedMessage }
      : undefined;
  } catch {
    return undefined;
  }
}

// The domain with only the fields that get signed, or `undefined` when ethers would not sign it as it is or a
// native confirmation could not decode it
export function getSignedTypedDataDomain(domain: Record<string, unknown>): Record<string, unknown> | undefined {
  try {
    // A list or a map is an object as well, and it passes for a domain with no fields
    if (Object.getPrototypeOf(domain) !== Object.prototype) return undefined;

    const types = { EIP712Domain: buildTypedDataDomainType(domain) };
    const budget = { valuesLeft: MAX_MESSAGE_VALUES, textLeft: MAX_TEXT_LENGTH, elementTypes: new Map() };
    const signedDomain = pickSignedValue(types, 'EIP712Domain', domain, budget) as Record<string, unknown>;

    return TypedDataEncoder.hashDomain(signedDomain) === TypedDataEncoder.hashDomain(domain) ? signedDomain : undefined;
  } catch {
    return undefined;
  }
}

// The types with nothing but their names, as the confirmations read them. A request that came by `postMessage` can
// hold more, which ethers would print into an error message at length.
function copyTypes(types: TypedDataTypes, structNames: string[]) {
  let lengthLeft = MAX_TYPES_LENGTH;
  const spendLength = (length: number) => {
    lengthLeft -= length;
    if (lengthLeft < 0) throw new Error('Typed data types are too long');
  };

  return Object.fromEntries(structNames.map((structName) => {
    const fields = types[structName];
    if (!Array.isArray(fields)) throw new Error('Typed data fields are not a list');

    const fieldCopies: TypedDataTypes[string] = [];
    spendLength(structName.length);
    assertOneForm(structName);

    for (const { name, type } of fields) {
      // A native confirmation decodes a field name as a string, and ethers drops a field named `__proto__` as it
      // rebuilds a struct by assignment
      if (typeof name !== 'string' || typeof type !== 'string' || name === '__proto__') {
        throw new Error('Typed data field is not shown as it gets signed');
      }

      // A field counts as a character more, so that fields without names are not read to the end of a long list
      spendLength(structName.length + name.length + type.length + 1);
      // A type is read by ethers again for each of its array dimensions, which are counted in a type that fits
      spendLength(type.length * (type.split('[').length - 1));
      assertOneForm(name);

      fieldCopies.push({ name, type });
    }

    return [structName, fieldCopies];
  }));
}

// The iOS confirmation takes two names that differ in their Unicode form alone for one, and shows one value for both
function assertOneForm(name: string) {
  if (name !== name.normalize() || LONE_SURROGATE_REGEX.test(name)) {
    throw new Error('Typed data name is not in the composed form');
  }
}

// The number of steps ethers takes from `type` down the type graph; a cycle, which ethers refuses, counts as endless
function countTypeVisits(types: TypedDataTypes, type: string, visitCounts: Map<string, number>): number {
  const knownCount = visitCounts.get(type);
  if (knownCount !== undefined) return knownCount;

  visitCounts.set(type, Infinity);

  const fieldTypes = new Set(types[type].map((field) => /^[^[]*/.exec(field.type)![0]));
  let count = 1;
  for (const fieldType of fieldTypes) {
    if (Object.prototype.hasOwnProperty.call(types, fieldType)) count += countTypeVisits(types, fieldType, visitCounts);
  }

  visitCounts.set(type, count);

  return count;
}

function pickSignedValue(types: TypedDataTypes, type: string, value: any, budget: Budget): unknown {
  if (budget.valuesLeft-- <= 0) throw new Error('Typed data is too large');

  // A type is split once for a request, however many values have it
  if (!budget.elementTypes.has(type)) budget.elementTypes.set(type, ARRAY_TYPE_REGEX.exec(type)?.[1]);
  const elementType = budget.elementTypes.get(type);
  if (elementType !== undefined) {
    // A string is no list to ethers, and it would be copied here letter by letter
    if (!Array.isArray(value)) throw new Error('Typed data value is not a list');

    const items: unknown[] = [];
    // An array that came by `postMessage` can be longer than its items, and `map` would copy the whole length
    for (const item of value as unknown[]) items.push(pickSignedValue(types, elementType, item, budget));

    return items;
  }

  if (Object.prototype.hasOwnProperty.call(types, type)) {
    // A number is read by ethers as a struct with none of its fields, which a struct of flags can be signed as
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Typed data value is no struct');

    return Object.fromEntries(types[type].map((field) => [
      spendText(budget, field.name),
      pickSignedValue(types, field.type, value[field.name], budget),
    ]));
  }

  // The string `false` is hashed by ethers as `true` and a blank string as `0`, so these go out as they get hashed
  if (type === 'bool') return Boolean(value);

  // The whole of a value ethers cannot hash goes into its error message, and of these types it hashes text or bytes
  if (!INTEGER_TYPE_REGEX.test(type)) {
    // Bytes come by `postMessage` as an array of them, which ethers hashes as their hex and a confirmation cannot show
    if (value instanceof Uint8Array) {
      if (value.length * 2 + 2 > budget.textLeft) throw new Error('Typed data is too large');

      return spendText(budget, hexlify(value));
    }

    if (typeof value !== 'string') throw new Error('Typed data value is not a string');
    if (type === 'address' && !ADDRESS_REGEX.test(value)) throw new Error('Typed data address is not signable');

    spendText(budget, value);
    if (LONE_SURROGATE_REGEX.test(value)) throw new Error('Typed data text is not well formed');

    return value;
  }

  if (value && typeof value === 'object') throw new Error('Typed data value is not a scalar');
  if (typeof value === 'string' && value.length > MAX_INTEGER_LENGTH) throw new Error('Integer is too long');

  const integer = getBigInt(value);
  // A `bigint` that came by `postMessage` can be of any length, and a long one is slow to write out
  if (BigInt.asIntN(MAX_INTEGER_BITS, integer) !== integer) throw new Error('Integer is too long');

  return spendText(budget, integer.toString());
}

// Counts the text as it goes out, so that a message this module returned passes it again before signing
function spendText(budget: Budget, text: string) {
  budget.textLeft -= text.length;
  if (budget.textLeft < 0) throw new Error('Typed data is too large');

  return text;
}
