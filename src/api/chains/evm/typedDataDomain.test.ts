import { TypedDataEncoder } from 'ethers';

import { buildTypedDataDomainType, isValidTypedDataDomain } from './typedDataDomain';

const VERIFYING_CONTRACT = '0x3333333333333333333333333333333333333333';
const SALT = `0x${'ab'.repeat(32)}`;
const TYPES = { Permit: [{ name: 'value', type: 'uint256' }] };
const MESSAGE = { value: '1' };
const DOMAIN_CASES: [string, Record<string, unknown>][] = [
  ['an undeclared verifyingContract', {
    name: 'Token', version: '1', chainId: 1, verifyingContract: VERIFYING_CONTRACT,
  }],
  ['an undeclared salt', { name: 'Token', salt: SALT }],
  // eslint-disable-next-line no-null/no-null -- typed data arrives as JSON
  ['null fields', { name: 'Token', version: null, chainId: null, verifyingContract: null, salt: null }],
  ['undefined fields', { name: 'Token', version: undefined, chainId: undefined, verifyingContract: undefined,
    salt: undefined }],
  ['fields outside EIP-712 order', { salt: SALT, verifyingContract: VERIFYING_CONTRACT,
    chainId: 1, version: '1', name: 'Token' }],
  ['an empty domain', {}],
];

describe('buildTypedDataDomainType', () => {
  it.each(DOMAIN_CASES)('matches ethers for %s', (_, domain) => {
    const expected = TypedDataEncoder.getPayload(domain, TYPES, MESSAGE).types.EIP712Domain;

    expect(buildTypedDataDomainType(domain)).toEqual(expected);
    expect(isValidTypedDataDomain(domain)).toBe(true);
  });
});

describe('isValidTypedDataDomain', () => {
  it('rejects domain keys outside EIP-712, including Object prototype names', () => {
    expect(isValidTypedDataDomain({ name: 'Token', extra: 'hidden' })).toBe(false);
    expect(isValidTypedDataDomain({ name: 'Token', toString: 'hidden' })).toBe(false);
  });

  it('ignores nullish domain values outside EIP-712', () => {
    // eslint-disable-next-line no-null/no-null -- ethers omits nullish domain values
    expect(isValidTypedDataDomain({ name: 'Token', extra: null, other: undefined })).toBe(true);
  });
});
