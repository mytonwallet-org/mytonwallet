import type { ApiParsedPayload } from '../../api/types';

import { getPayloadRecipientAddress } from './transfer';

const TO_ADDRESS = 'message-address';

describe('getPayloadRecipientAddress', () => {
  it.each([
    ['tokens:transfer', { type: 'tokens:transfer', destination: 'token-recipient' }],
    ['tokens:transfer-non-standard', { type: 'tokens:transfer-non-standard', destination: 'token-recipient' }],
    ['nft:transfer', { type: 'nft:transfer', newOwner: 'nft-recipient' }],
  ] as const)('returns the semantic recipient for %s', (_type, payload) => {
    expect(getPayloadRecipientAddress({ toAddress: TO_ADDRESS, payload: payload as ApiParsedPayload })).toBe(
      'destination' in payload ? payload.destination : payload.newOwner,
    );
  });

  it('does not treat a burn response address as a recipient', () => {
    const payload = { type: 'tokens:burn', address: 'response-address' } as ApiParsedPayload;

    expect(getPayloadRecipientAddress({ toAddress: TO_ADDRESS, payload })).toBeUndefined();
  });

  it('skips a recipient that matches the message address', () => {
    const payload = { type: 'tokens:transfer', destination: TO_ADDRESS } as ApiParsedPayload;

    expect(getPayloadRecipientAddress({ toAddress: TO_ADDRESS, payload })).toBeUndefined();
  });
});
