import type { ApiSwapActivity } from '../../api/types';

import { getLifiReceivedToken } from './lifiHistory';

const activity = {
  to: 'arbitrum-0x3333333333',
  lifi: {
    outcome: 'partial',
    quotedTo: 'arbitrum:0x1111111111111111111111111111111111111111',
    quotedToAmount: '1',
    received: {
      chain: 'arbitrum', tokenAddress: '0x3333333333333333333333333333333333333333',
      symbol: 'USDT', decimals: 6, amount: '0.975',
    },
  },
} as ApiSwapActivity;

describe('LI.FI activity settlement', () => {
  it('renders an unlisted alternate token from the actual status response', () => {
    expect(getLifiReceivedToken(activity)).toMatchObject({
      slug: activity.to,
      symbol: 'USDT',
      chain: 'arbitrum',
      tokenAddress: activity.lifi?.received?.tokenAddress,
    });
  });

  it('prefers the catalogue token when it is known', () => {
    const known = { slug: activity.to, symbol: 'USDT', chain: 'arbitrum' } as any;
    expect(getLifiReceivedToken(activity, known)).toBe(known);
  });

  it('does not invent a received token when LI.FI only returned a terminal status', () => {
    expect(getLifiReceivedToken({
      ...activity,
      lifi: { ...activity.lifi!, received: undefined },
    })).toBeUndefined();
  });
});
