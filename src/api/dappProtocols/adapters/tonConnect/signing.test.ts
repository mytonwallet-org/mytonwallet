import { beginCell } from '@ton/core';

import { base64ToBytes, bytesToBase64 } from '../../../common/utils';
import { signDataWithPrivateKey, signTonProofWithPrivateKey } from './signing';

describe('signTonProofWithPrivateKey', () => {
  it('signs with expected signature', async () => {
    const address = 'UQCyqTmXJpshFu1GW1tyTX6paa3c-37OG9s3uv8ZzX_9GDfx';
    const privateKey = base64ToBytes('fXaAuTRa6zvLnARTnVd2Llb1MDYLfhJsDKa9IXptmrnVI3r3b7swQGk4qik0ZnUfJbhu1yC82DUCSiVHvyHZ/Q=='); // eslint-disable-line @stylistic/max-len
    const proof = {
      timestamp: 1703731900,
      domain: 'example.com',
      payload: 'Hello, world',
    };

    const signature = await signTonProofWithPrivateKey(
      address,
      privateKey,
      proof,
    );

    expect(bytesToBase64(signature)).toBe(
      '9UNF8FFAztuhnR7T3MzTZYmO92Vd3zrrYsR6pdaOUXaVqAvegqrfpTET8MS469kB7os5QBcQm650ye7AmfJ3Dw==',
    );
  });
});

describe('signDataWithPrivateKey', () => {
  // The test data are borrowed from https://github.com/mois-ilya/ton-sign-data-reference/blob/d35109dfa88eed8620cb03a45e28a92540f63e3b/src/__tests__/sign.test.ts#L489
  const timestamp = 1703980800;
  const address = 'UQCyqTmXJpshFu1GW1tyTX6paa3c-37OG9s3uv8ZzX_9GDfx';
  const domain = 'example.com';
  const privateKey = base64ToBytes('g4aJS60IkrE/pfCQzDp8+zpzwTP1cSfvTKVHFa4H7E/2Xzi4I+htfxgE7VSkBqjSwuMhkdO+SuLRrEXNzXP0eg=='); // eslint-disable-line @stylistic/max-len

  const testCases = [
    {
      name: 'text payload',
      payload: { type: 'text' as const, text: 'Hello, TON!' },
      expectedSignature: '/34cktAUdWpCVgUfyXQlFtINRhdC9DRlshhMtOx1I9G2TDLV20xrHPxp9fvifz3EHZthCnSHN/IVF8zw7twNCw==',
    },
    {
      name: 'binary payload',
      payload: {
        type: 'binary' as const,
        bytes: Buffer.from('Hello, TON!').toString('base64'),
      },
      expectedSignature: 'R7vQ6Zj2CYXJAa+ldLWgwPbJyR/58XrQV3HDw4yuqSYmR8PcoBpt5h1DOLX0LgxjOE3tieuwsDP6WwnCDkAECg==',
    },
    {
      name: 'cell payload',
      payload: {
        type: 'cell' as const,
        schema: 'message#_ text:string = Message;',
        cell: beginCell()
          .storeUint(0, 32)
          .storeStringTail('Hello, TON!')
          .endCell()
          .toBoc()
          .toString('base64'),
      },
      expectedSignature: 'xULn8inA8A1qhFEFK8jpY+UEq7dHlpA/tm8LkxBBzRkZjTrni31H1p5Q+XMTS4I7HWsyC0i82teVdwc02lg4AQ==',
    },
  ];

  it.each(testCases)('signs $name with expected signature', async ({ payload, expectedSignature }) => {
    const signature = await signDataWithPrivateKey(
      address,
      timestamp,
      domain,
      payload,
      privateKey,
    );

    expect(bytesToBase64(signature)).toBe(expectedSignature);
  });
});
