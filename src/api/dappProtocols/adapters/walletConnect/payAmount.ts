import type { ApiChain } from '../../../types';
import type { WcPayFiatAmount, WcPayFiatCurrency, WcPayRawAmount } from './types';
import { CHAIN_IDS } from './types';

import { CURRENCIES } from '../../../../config';
import { getChainConfig } from '../../../../util/chain';
import { buildTokenSlug, getTokenBySlug, getTokensCache } from '../../../common/tokens';

const WC_PAY_FIAT_CURRENCIES = new Set<WcPayFiatCurrency>(['USD', 'EUR']);

const ISO4217_UNIT_PREFIX = 'iso4217/';
const CAIP19_UNIT_PREFIX = 'caip19/';

type WcPayCaip19Parts = {
  caip2: string;
  assetNamespace: string;
  assetReference: string;
};

function isWcPayFiatCurrency(value: string): value is WcPayFiatCurrency {
  return WC_PAY_FIAT_CURRENCIES.has(value as WcPayFiatCurrency);
}

function normalizeWcPayFiatCurrencyCode(value: string) {
  const normalized = value.trim().toUpperCase();

  return isWcPayFiatCurrency(normalized) ? normalized : undefined;
}

function resolveWcPayFiatCurrencyFromUnit(unit?: string): WcPayFiatCurrency | undefined {
  if (!unit) {
    return undefined;
  }

  const normalizedUnit = unit.trim().toLowerCase();
  const prefixIndex = normalizedUnit.indexOf(ISO4217_UNIT_PREFIX);

  if (prefixIndex === -1) {
    return undefined;
  }

  const code = unit.slice(prefixIndex + ISO4217_UNIT_PREFIX.length);

  return normalizeWcPayFiatCurrencyCode(code);
}

function resolveWcPayFiatCurrencyFromDisplay(display: WcPayRawAmount['display']): WcPayFiatCurrency | undefined {
  const fromSymbol = normalizeWcPayFiatCurrencyCode(display.assetSymbol);

  if (fromSymbol) {
    return fromSymbol;
  }

  if (!display.assetName) {
    return undefined;
  }

  const normalizedAssetName = display.assetName.trim().toLowerCase();

  for (const [currency, { name }] of Object.entries(CURRENCIES)) {
    if (!isWcPayFiatCurrency(currency)) {
      continue;
    }

    if (name.trim().toLowerCase() === normalizedAssetName) {
      return currency;
    }
  }

  return undefined;
}

function resolveWcPayFiatCurrency(amount: WcPayRawAmount): WcPayFiatCurrency | undefined {
  return resolveWcPayFiatCurrencyFromUnit(amount.unit)
    ?? resolveWcPayFiatCurrencyFromDisplay(amount.display);
}

export function parseWcPayFiatAmount(amount: WcPayRawAmount): WcPayFiatAmount | undefined {
  const slug = resolveWcPayFiatCurrency(amount);

  if (!slug) {
    return undefined;
  }

  return {
    value: amount.value,
    decimals: amount.display.decimals,
    slug,
  };
}

function parseWcPayCaip19Unit(unit?: string): WcPayCaip19Parts | undefined {
  if (!unit) {
    return undefined;
  }

  const normalizedUnit = unit.trim();

  if (normalizedUnit.toLowerCase().startsWith(ISO4217_UNIT_PREFIX)) {
    return undefined;
  }

  const assetPath = normalizedUnit.startsWith(CAIP19_UNIT_PREFIX)
    ? normalizedUnit.slice(CAIP19_UNIT_PREFIX.length)
    : normalizedUnit;

  const slashIndex = assetPath.indexOf('/');

  if (slashIndex === -1) {
    return undefined;
  }

  const caip2 = assetPath.slice(0, slashIndex);
  const assetPart = assetPath.slice(slashIndex + 1);
  const colonIndex = assetPart.indexOf(':');

  if (colonIndex === -1) {
    return undefined;
  }

  return {
    caip2,
    assetNamespace: assetPart.slice(0, colonIndex).toLowerCase(),
    assetReference: assetPart.slice(colonIndex + 1),
  };
}

function resolveWcPayTokenAddress(parts: WcPayCaip19Parts): string | undefined {
  switch (parts.assetNamespace) {
    case 'slip44':
      return undefined;
    case 'erc20':
    case 'token':
    case 'jetton':
      return parts.assetReference;
    default:
      return parts.assetReference || undefined;
  }
}

function resolveWcPayTokenSlugFromCaip19(
  parts: WcPayCaip19Parts,
  chainHint?: ApiChain,
): string | undefined {
  const chain = CHAIN_IDS[parts.caip2]?.chain ?? chainHint;

  if (!chain) {
    return undefined;
  }

  if (parts.assetNamespace === 'slip44') {
    const nativeSlug = getChainConfig(chain).nativeToken.slug;

    return getTokenBySlug(nativeSlug)?.slug ?? nativeSlug;
  }

  const tokenAddress = resolveWcPayTokenAddress(parts);

  if (!tokenAddress) {
    return undefined;
  }

  const slug = buildTokenSlug(chain, tokenAddress);

  return getTokenBySlug(slug)?.slug ?? slug;
}

function symbolsMatch(left: string, right: string): boolean {
  return left.trim().toLowerCase() === right.trim().toLowerCase();
}

function resolveWcPayTokenSlugFromSymbol(symbol: string, chain?: ApiChain): string | undefined {
  const normalizedSymbol = symbol.trim();

  if (!normalizedSymbol) {
    return undefined;
  }

  const tokens = Object.values(getTokensCache().bySlug);

  if (chain) {
    const nativeToken = getChainConfig(chain).nativeToken;

    if (symbolsMatch(nativeToken.symbol, normalizedSymbol)) {
      return getTokenBySlug(nativeToken.slug)?.slug ?? nativeToken.slug;
    }

    for (const token of tokens) {
      if (token.chain === chain && symbolsMatch(token.symbol, normalizedSymbol)) {
        return token.slug;
      }
    }
  }

  for (const token of tokens) {
    if (symbolsMatch(token.symbol, normalizedSymbol)) {
      return token.slug;
    }
  }

  return undefined;
}

export function resolveWcPayTokenSlug(amount: WcPayRawAmount, chainHint?: ApiChain) {
  const caip19Parts = parseWcPayCaip19Unit(amount.unit);

  if (caip19Parts) {
    const slugFromUnit = resolveWcPayTokenSlugFromCaip19(caip19Parts, chainHint);

    if (slugFromUnit) {
      return slugFromUnit;
    }
  }

  return resolveWcPayTokenSlugFromSymbol(amount.display.assetSymbol, chainHint);
}

export function toWcPayRawAmount(amount: {
  unit?: string;
  value: string;
  display: {
    assetSymbol: string;
    assetName?: string;
    decimals: number;
  };
}): WcPayRawAmount {
  return {
    unit: amount.unit,
    value: amount.value,
    display: {
      assetSymbol: amount.display.assetSymbol,
      assetName: amount.display.assetName,
      decimals: amount.display.decimals,
    },
  };
}
