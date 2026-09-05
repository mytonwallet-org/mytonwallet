import type { ApiBaseCurrency, ApiCurrencyRates } from '../api/types';

import { CURRENCIES } from '../config';
import { Big } from '../lib/big.js';

/**
 * Establishes the invariant every consumer of `currencyRates` already assumes: each currency maps to
 * a string `Big` can parse into a positive number.
 *
 * Nothing downstream can hold that line on its own. Rates are read on render paths - the currency
 * switcher, the balance card, every token list - and `Big` answers a value it cannot parse by
 * throwing, so one unusable entry does not spoil one number, it replaces the screen with the error
 * overlay. The values arrive as strings over the network and are cached to localStorage afterwards,
 * so an unusable one would break the first render of every later session too, before any poll can
 * replace it.
 *
 * `'Infinity'` is the shape to keep in mind: a division by a zero price rendered through `toFixed`
 * produces it, and a string survives JSON where a raw number would have flattened to `null`.
 * `'NaN'`, `''`, a missing key and a negative rate fail the same way, and `'0'` is worse than a
 * throw because it quietly reports every balance as nothing.
 *
 * A fallback is stale by construction - these are the constants the app boots with before it has
 * ever spoken to the backend - so a currency that falls back shows an out-of-date number rather than
 * no application at all.
 */
export function sanitizeCurrencyRates(rates: Partial<ApiCurrencyRates> | undefined): ApiCurrencyRates {
  const entries = Object.entries(CURRENCIES).map(([currency, { fallbackRate }]) => {
    const rate = rates?.[currency as ApiBaseCurrency];

    return [currency, isUsableRate(rate) ? rate : fallbackRate];
  });

  return Object.fromEntries(entries) as ApiCurrencyRates;
}

/**
 * Asks the parser the consumers use rather than a second opinion. `Number` is more forgiving than
 * `Big` - it reads `'0x10'` and tolerates surrounding spaces, both of which `Big` rejects - so a
 * check written in terms of `Number` would pass values that still throw downstream.
 */
function isUsableRate(rate: unknown): rate is string {
  if (typeof rate !== 'string') {
    return false;
  }

  try {
    return new Big(rate).gt(0);
  } catch {
    return false;
  }
}
