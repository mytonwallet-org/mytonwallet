import type { UnifiedSignDataPayload } from '../../api/dappProtocols/types';

import { getSignDataWarningKinds } from './signDataWarningPolicy';

const PAYLOADS = {
  text: { type: 'text', text: 'Message' },
  binary: { type: 'binary', bytes: '00' },
  cell: { type: 'cell', schema: 'root$_ = Root;', cell: 'te6ccgEBAQEAAgAAAA==' },
  eip712: {
    type: 'eip712',
    domain: {},
    types: {},
    primaryType: 'Message',
    message: {},
  },
} satisfies Record<string, UnifiedSignDataPayload>;

describe('signData warning policy', () => {
  it.each([
    ['text', PAYLOADS.text],
    ['binary', PAYLOADS.binary],
    ['EIP-712', PAYLOADS.eip712],
    ['parsed or fallback TL-B cell', PAYLOADS.cell],
  ])('shows exactly one generic trust warning for %s', (_name, payload) => {
    expect(getSignDataWarningKinds(payload)).toEqual(['genericTrust']);
  });

  it('does not render a warning before a signData payload is available', () => {
    expect(getSignDataWarningKinds(undefined)).toEqual([]);
  });
});
