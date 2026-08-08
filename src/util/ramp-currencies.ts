import type { ApiBaseCurrency, ApiChain, ApiCountryCode } from '../api/types';

import { CURRENCIES } from '../config';
import { getChainConfig } from './chain';

// Widest per-surface baselines, i.e. what is offered on at least one chain; the server list may only narrow them.
// The chain-specific variants are constants rather than filtered on demand because selectors read them on every
// global change and must hand back a stable reference
const ON_RAMP_CURRENCIES: ApiBaseCurrency[] = ['USD', 'EUR', 'RUB'];
const ON_RAMP_CURRENCIES_WITHOUT_RUB: ApiBaseCurrency[] = ['USD', 'EUR'];
const OFF_RAMP_CURRENCIES: ApiBaseCurrency[] = ['EUR', 'RUB'];
const OFF_RAMP_CURRENCIES_WITHOUT_RUB: ApiBaseCurrency[] = ['EUR'];

/**
 * Both ruble directions run through Avanchange, which settles in GRAM - a TON asset - so buying and selling reach
 * the same single chain. Asking the chain config which chains it serves, rather than naming the ones it does not,
 * is what keeps every chain added later out of the ruble flow until it is opted in explicitly.
 */
export function getIsRubSupported(chain: ApiChain): boolean {
  return getChainConfig(chain).canBuyWithCardInRussia;
}

// No chain means the caller is asking about any chain at all, and the ruble exists on one of them
function getIsRubInBaseline(chain?: ApiChain): boolean {
  return !chain || getIsRubSupported(chain);
}

/**
 * Currencies the on-ramp offers on the given chain. Omitting the chain answers for any chain, i.e. yields the union,
 * which is what the entry-point gates outside a concrete chain context need.
 */
export function getOnRampBaselineCurrencies(chain?: ApiChain): ApiBaseCurrency[] {
  return getIsRubInBaseline(chain) ? ON_RAMP_CURRENCIES : ON_RAMP_CURRENCIES_WITHOUT_RUB;
}

/** Off-ramp counterpart of `getOnRampBaselineCurrencies` */
export function getOffRampBaselineCurrencies(chain?: ApiChain): ApiBaseCurrency[] {
  return getIsRubInBaseline(chain) ? OFF_RAMP_CURRENCIES : OFF_RAMP_CURRENCIES_WITHOUT_RUB;
}

// The input crosses a trust boundary (server JSON), so the shape is validated at runtime
// instead of relying on the compile-time type; anything malformed reads as an absent field
export function normalizeAllowedOnOffRampCurrencies(raw?: unknown): ApiBaseCurrency[] | undefined {
  if (!Array.isArray(raw)) return undefined;

  const known = raw
    .filter((code): code is string => typeof code === 'string')
    .map((code) => code.toUpperCase())
    // Own-property check, not `in`: the predicate hands the value to the type system as a currency,
    // and that promise should not rest on nothing inherited from the prototype happening to collide
    .filter((code): code is ApiBaseCurrency => Object.prototype.hasOwnProperty.call(CURRENCIES, code));

  return [...new Set(known)];
}

export function getEffectiveRampCurrencies(
  baseline: ApiBaseCurrency[],
  allowed?: ApiBaseCurrency[],
): ApiBaseCurrency[] {
  if (!allowed) return baseline;

  return baseline.filter((currency) => allowed.includes(currency));
}

/**
 * Whether the surface has anything left to offer, answered without materialising the narrowed set - selectors run on
 * every global change and must not allocate.
 */
export function hasEffectiveRampCurrency(baseline: ApiBaseCurrency[], allowed?: ApiBaseCurrency[]): boolean {
  if (!allowed) return baseline.length > 0;

  return baseline.some((currency) => allowed.includes(currency));
}

/**
 * Which currency a ramp surface starts on: the wallet's own currency, then the ruble for users in Russia, then
 * whatever the surface has left. `undefined` means nothing is offered at all, and the caller must close or refuse
 * the surface - naming a currency of its own here is what lets a client offer one the server withdrew.
 */
export function getDefaultRampCurrency(
  supportedCurrencies: Set<ApiBaseCurrency>,
  baseCurrency: ApiBaseCurrency | undefined,
  countryCode: ApiCountryCode | undefined,
): ApiBaseCurrency | undefined {
  const preferences: (ApiBaseCurrency | undefined)[] = [baseCurrency, countryCode === 'RU' ? 'RUB' : undefined];
  const preferred = preferences.find((currency) => currency && supportedCurrencies.has(currency));

  return preferred ?? [...supportedCurrencies][0];
}
