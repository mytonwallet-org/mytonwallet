import type { ApiBaseCurrency } from '../api/types';

import { CHAIN_ORDER, getChainConfig } from './chain';
import {
  getDefaultRampCurrency,
  getEffectiveRampCurrencies,
  getOffRampBaselineCurrencies,
  getOnRampBaselineCurrencies,
  hasEffectiveRampCurrency,
  normalizeAllowedOnOffRampCurrencies,
} from './ramp-currencies';

describe('normalizeAllowedOnOffRampCurrencies', () => {
  it('returns undefined when the field is absent', () => {
    expect(normalizeAllowedOnOffRampCurrencies(undefined)).toBeUndefined();
  });

  it('treats a non-array payload as absent', () => {
    expect(normalizeAllowedOnOffRampCurrencies('rub')).toBeUndefined();
    expect(normalizeAllowedOnOffRampCurrencies({ 0: 'usd' })).toBeUndefined();
    expect(normalizeAllowedOnOffRampCurrencies(42)).toBeUndefined();
  });

  it('drops non-string elements', () => {
    // eslint-disable-next-line no-null/no-null
    expect(normalizeAllowedOnOffRampCurrencies([42, 'usd', null, undefined])).toEqual(['USD']);
  });

  it('upper-cases known codes and drops unknown ones', () => {
    expect(normalizeAllowedOnOffRampCurrencies(['usd', 'eur', 'xyz'])).toEqual(['USD', 'EUR']);
  });

  it('drops duplicates after normalization', () => {
    expect(normalizeAllowedOnOffRampCurrencies(['usd', 'USD', 'usd'])).toEqual(['USD']);
  });

  it('keeps an empty list empty', () => {
    expect(normalizeAllowedOnOffRampCurrencies([])).toEqual([]);
  });
});

describe('getOnRampBaselineCurrencies', () => {
  it('yields the union of every chain when no chain is given', () => {
    expect(getOnRampBaselineCurrencies()).toEqual(['USD', 'EUR', 'RUB']);
  });

  it('keeps RUB on TON only', () => {
    expect(getOnRampBaselineCurrencies('ton')).toEqual(['USD', 'EUR', 'RUB']);
    expect(getOnRampBaselineCurrencies('tron')).toEqual(['USD', 'EUR']);
    expect(getOnRampBaselineCurrencies('solana')).toEqual(['USD', 'EUR']);
  });
});

describe('getOffRampBaselineCurrencies', () => {
  it('yields the union of every chain when no chain is given', () => {
    expect(getOffRampBaselineCurrencies()).toEqual(['EUR', 'RUB']);
  });

  it('keeps RUB on TON only', () => {
    expect(getOffRampBaselineCurrencies('ton')).toEqual(['EUR', 'RUB']);
    expect(getOffRampBaselineCurrencies('tron')).toEqual(['EUR']);
    expect(getOffRampBaselineCurrencies('ethereum')).toEqual(['EUR']);
  });
});

// The ruble provider settles in a TON asset, so a chain gaining the ruble flow is a deliberate decision and
// not something a chain added later should inherit by default
describe('ruble chains', () => {
  it('offers RUB on exactly the chains the config opts in', () => {
    for (const chain of CHAIN_ORDER) {
      const { canBuyWithCardInRussia } = getChainConfig(chain);

      expect(getOnRampBaselineCurrencies(chain).includes('RUB')).toBe(canBuyWithCardInRussia);
      expect(getOffRampBaselineCurrencies(chain).includes('RUB')).toBe(canBuyWithCardInRussia);
    }
  });

  it('has exactly one such chain', () => {
    expect(CHAIN_ORDER.filter((chain) => getChainConfig(chain).canBuyWithCardInRussia)).toEqual(['ton']);
  });
});

describe('getEffectiveRampCurrencies', () => {
  const BASELINE: ApiBaseCurrency[] = ['USD', 'EUR', 'RUB'];

  it('returns the baseline when no allowed list is given', () => {
    expect(getEffectiveRampCurrencies(BASELINE)).toEqual(['USD', 'EUR', 'RUB']);
  });

  it('narrows the baseline to the allowed list', () => {
    expect(getEffectiveRampCurrencies(BASELINE, ['USD', 'EUR'])).toEqual(['USD', 'EUR']);
  });

  it('never widens beyond the baseline', () => {
    expect(getEffectiveRampCurrencies(['EUR', 'RUB'], ['USD', 'EUR', 'RUB'])).toEqual(['EUR', 'RUB']);
  });

  it('yields an empty list for an empty allowed list', () => {
    expect(getEffectiveRampCurrencies(BASELINE, [])).toEqual([]);
  });
});

describe('hasEffectiveRampCurrency', () => {
  const BASELINE: ApiBaseCurrency[] = ['USD', 'EUR', 'RUB'];

  it('agrees with the narrowed list it declines to build', () => {
    const allowedLists: (ApiBaseCurrency[] | undefined)[] = [
      undefined, [], ['USD'], ['RUB'], ['CNY'], ['USD', 'EUR', 'RUB'],
    ];

    for (const allowed of allowedLists) {
      expect(hasEffectiveRampCurrency(BASELINE, allowed))
        .toBe(getEffectiveRampCurrencies(BASELINE, allowed).length > 0);
    }
  });

  it('is false when the allowed list and the baseline do not overlap', () => {
    expect(hasEffectiveRampCurrency(['EUR', 'RUB'], ['USD'])).toBe(false);
  });

  it('is false for an empty baseline even with no allowed list', () => {
    expect(hasEffectiveRampCurrency([])).toBe(false);
  });
});

// Selectors call these on every global change, so a fresh array per call would make every connected
// container re-render; the chain-specific variants have to be the same object every time
describe('baseline currency references', () => {
  it('hands back one stable array per chain', () => {
    expect(getOnRampBaselineCurrencies('tron')).toBe(getOnRampBaselineCurrencies('tron'));
    expect(getOnRampBaselineCurrencies('ton')).toBe(getOnRampBaselineCurrencies());
    expect(getOffRampBaselineCurrencies('tron')).toBe(getOffRampBaselineCurrencies('ethereum'));
    expect(getOffRampBaselineCurrencies('ton')).toBe(getOffRampBaselineCurrencies());
  });
});

describe('getDefaultRampCurrency', () => {
  const offer = (...currencies: ApiBaseCurrency[]) => new Set<ApiBaseCurrency>(currencies);

  it('starts on the wallet currency when it is offered', () => {
    expect(getDefaultRampCurrency(offer('USD', 'EUR'), 'EUR', undefined)).toBe('EUR');
  });

  it('prefers the wallet currency over the ruble in Russia', () => {
    expect(getDefaultRampCurrency(offer('USD', 'EUR', 'RUB'), 'EUR', 'RU')).toBe('EUR');
  });

  it('starts on the ruble in Russia when the wallet names nothing offered', () => {
    expect(getDefaultRampCurrency(offer('USD', 'EUR', 'RUB'), undefined, 'RU')).toBe('RUB');
    expect(getDefaultRampCurrency(offer('USD', 'EUR', 'RUB'), 'CNY', 'RU')).toBe('RUB');
  });

  it('falls back to the first offered currency when no preference survives', () => {
    expect(getDefaultRampCurrency(offer('EUR', 'RUB'), 'USD', 'US')).toBe('EUR');
    expect(getDefaultRampCurrency(offer('USD', 'EUR'), 'RUB', 'RU')).toBe('USD');
  });

  // A currency the server withdrew must not come back as a default the client picked on its own
  it('never answers with a currency outside the offered set', () => {
    expect(getDefaultRampCurrency(offer('RUB'), 'USD', 'US')).toBe('RUB');
  });

  it('answers nothing when nothing is offered', () => {
    expect(getDefaultRampCurrency(offer(), 'USD', 'RU')).toBeUndefined();
  });
});
