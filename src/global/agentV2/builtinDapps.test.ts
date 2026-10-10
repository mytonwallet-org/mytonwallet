import type { GlobalState } from '../../global/types';

import { INITIAL_STATE } from '../../global/initialState';
import { buildAgentBuiltinDapps } from './builtinDapps';

function createGlobal(): GlobalState {
  return { ...INITIAL_STATE, currentAccountId: '0-mainnet', accounts: { byId: {
    '0-mainnet': { type: 'mnemonic', byChain: {
      solana: { address: 'solana-address' }, ton: { address: 'ton-address' },
    } },
  } } };
}

describe('built-in purchase destinations', () => {
  it('advertises native purchase destinations bound to the account and provider', () => {
    const destinations = buildAgentBuiltinDapps(createGlobal());
    expect(destinations).toContainEqual({ name: 'Buy SOL (Solana, solana) via MoonPay',
      url: 'mtw://buy-with-card?chain=solana&provider=moonpay' });
    expect(destinations.map(({ url }) => url)).toEqual(expect.arrayContaining([
      'mtw://buy-with-card?chain=ton&provider=moonpay',
      'mtw://buy-with-card?chain=ton&provider=avanchange',
    ]));
    expect(destinations).toHaveLength(3);
  });

  it('removes destinations when their provider currencies or network are unavailable', () => {
    const global = createGlobal();
    global.restrictions = { ...global.restrictions, allowedOnOffRampCurrencies: ['RUB'] };
    expect(buildAgentBuiltinDapps(global).map(({ url }) => url)).toEqual([
      'mtw://buy-with-card?chain=ton&provider=avanchange',
    ]);
    global.settings = { ...global.settings, isTestnet: true };
    expect(buildAgentBuiltinDapps(global)).toEqual([]);
  });
});
