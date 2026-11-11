import type { TypedDataField } from 'ethers';
import { TypedDataEncoder } from 'ethers';
import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { Eip712TypedDataViewProps } from './Eip712TypedDataView';

import Eip712TypedDataView from './Eip712TypedDataView';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en', isRtl: false }),
}));

const USDC_ADDRESS = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
const SALT = `0x${'5a'.repeat(32)}`;

const PERMIT_TYPES = {
  Permit: [
    { name: 'owner', type: 'address' },
    { name: 'spender', type: 'address' },
    { name: 'value', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
};

const PERMIT_MESSAGE = {
  owner: `0x${'11'.repeat(20)}`,
  spender: `0x${'22'.repeat(20)}`,
  value: '1000000',
  nonce: '0',
  deadline: '1893456000',
};

const DECLARES_NAME_VERSION_CHAIN_ID = [
  { name: 'name', type: 'string' },
  { name: 'version', type: 'string' },
  { name: 'chainId', type: 'uint256' },
];

describe('Eip712TypedDataView', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('shows a verifyingContract and salt that types.EIP712Domain does not declare', () => {
    renderPermit({
      domain: { name: 'USD Coin', version: '2', chainId: 1, verifyingContract: USDC_ADDRESS, salt: SALT },
      types: { EIP712Domain: DECLARES_NAME_VERSION_CHAIN_ID, ...PERMIT_TYPES },
    });

    expect(getDomainRows(root)).toEqual([
      ['name', 'USD Coin'],
      ['version', '2'],
      ['chainId', '1'],
      ['verifyingContract', USDC_ADDRESS],
      ['salt', SALT],
    ]);
  });

  it.each([
    {
      title: 'undeclared verifyingContract',
      domain: { name: 'USD Coin', version: '2', chainId: 1, verifyingContract: USDC_ADDRESS },
      declared: DECLARES_NAME_VERSION_CHAIN_ID,
    },
    {
      title: 'undeclared salt',
      domain: { name: 'USD Coin', salt: SALT },
      declared: [{ name: 'name', type: 'string' }],
    },
    {
      title: 'declared fields missing from domain',
      domain: { name: 'USD Coin' },
      declared: [...DECLARES_NAME_VERSION_CHAIN_ID, { name: 'verifyingContract', type: 'address' }],
    },
    {
      title: 'null and undefined domain fields',
      // eslint-disable-next-line no-null/no-null -- dApps send JSON nulls
      domain: { name: 'USD Coin', version: null, chainId: undefined, verifyingContract: USDC_ADDRESS },
      declared: DECLARES_NAME_VERSION_CHAIN_ID,
    },
    {
      title: 'domain keys out of EIP-712 order and no EIP712Domain type',
      domain: { salt: SALT, verifyingContract: USDC_ADDRESS, chainId: '0x1', name: 'USD Coin' },
      declared: undefined,
    },
  ])('shows exactly the domain fields ethers signs: $title', ({ domain, declared }) => {
    renderPermit({
      domain,
      types: declared ? { EIP712Domain: declared, ...PERMIT_TYPES } : PERMIT_TYPES,
    });

    const signedDomainFields: TypedDataField[] = TypedDataEncoder
      .getPayload(domain, PERMIT_TYPES, PERMIT_MESSAGE).types.EIP712Domain;

    expect(getDomainRows(root).map(([name]) => name)).toEqual(signedDomainFields.map(({ name }) => name));
  });

  function renderPermit({ domain, types }: Pick<Eip712TypedDataViewProps, 'domain' | 'types'>) {
    TeactDOM.render(
      <Eip712TypedDataView domain={domain} types={types} primaryType="Permit" message={PERMIT_MESSAGE} />,
      root,
    );
  }
});

function getDomainRows(root: HTMLElement): Array<[string, string]> {
  const label = Array.from(root.querySelectorAll('p')).find((p) => p.textContent === 'EIP-712 domain');
  const struct = label?.nextElementSibling?.firstElementChild;

  return Array.from(struct?.children ?? []).map((row) => [
    row.children[0].textContent ?? '',
    row.children[1].textContent ?? '',
  ]);
}
