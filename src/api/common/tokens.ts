import {
  type ApiChain,
  type ApiCurrencyRates,
  type ApiTokenPriceDetails,
  type ApiTokenUpdateKind,
  type ApiTokenWithMaybePrice,
  type ApiTokenWithPrice,
  type OnApiUpdate,
} from '../types';

import { CURRENCIES } from '../../config';
import { raceWithAbortSignal } from '../../util/abortSignal';
import { areDeepEqual } from '../../util/areDeepEqual';
import { pricePrecisionFromUsdPrice } from '../../util/assetPrecision';
import { getChainConfig, getSupportedChains, getTokenInfo } from '../../util/chain';
import { isUsableRate } from '../../util/currencyRates';
import { HOUR, SECOND } from '../../util/dateFormat';
import Deferred from '../../util/Deferred';
import isEmptyObject from '../../util/isEmptyObject';
import { buildCollectionByKey, isLiteralObject, omitUndefined } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { pause } from '../../util/schedulers';
import { tokenRepository } from '../db';
import { ApiServerError } from '../errors';
import { callBackendGet, callBackendPost } from './backend';
import { getHeldSlugs } from './heldTokens';
import { notifyTokenSlugsMove } from './tokenSlugMoves';

/** A backstop for the token details payload, which is normally bounded by the number of the tokens on the device */
const MAX_POST_TOKENS = 1500;
/** Bounds the time the first balances wait for the token catalog */
const CATALOG_WAIT_TIMEOUT = 5 * SECOND;
const LEGACY_ASSETS_RETRY_DELAY = HOUR;

type BackendTokenCatalog = {
  version: string;
  assets: Omit<ApiTokenWithPrice, 'priceUsd' | 'percentChange24h'>[];
};
type BackendTokenPrices = {
  catalogVersion: string;
  prices: Record<string, [number, number | null]>;
  rates?: ApiCurrencyRates;
};

let backendTokenCatalog: (BackendTokenCatalog & { langCode?: string }) | undefined;
const backendCatalogRequests = new Map<string, Promise<BackendTokenCatalog>>();
let legacyAssetsUntil = 0;

export type TokenDetailsOptions = {
  langCode?: string;
  /** Limits the payload to the tokens the polled wallets hold. Off for the runtimes that poll no wallet. */
  shouldNarrowToHeldTokens?: boolean;
};

type TokenDetailsUpdate = Partial<ApiTokenPriceDetails> & Pick<ApiTokenWithPrice, 'slug' | 'isPriceFromBackend'>;
/** A token found on a wallet or by its address, which needs a slug of its own only when it has no address */
export type FetchedToken = Omit<ApiTokenWithMaybePrice, 'slug'> & Partial<Pick<ApiTokenWithMaybePrice, 'slug'>>;

export const tokensPreload = new Deferred();
/**
 * Settles when a backend request of the current UI has applied the token catalog to the cache or failed. The
 * database write that follows is not awaited. `isCatalogRequested` tells whether the worker requests the catalog, so
 * that runtimes without it never wait.
 */
const catalogPreload = new Deferred();
let isCatalogRequested = false;
/**
 * The wait of the balances: the cached tokens, then the catalog or `CATALOG_WAIT_TIMEOUT`. A token found after the
 * timeout or a failed request may take the backend slug of a catalog token, which the catalog moves once it arrives.
 */
let catalogWait: Promise<unknown> | undefined;
/** Slugs of the last backend catalog, reused when the details are requested outside `updateTokensFromBackend` */
let backendTokenSlugs = new Set<string>();
let isTokenUpdatePaused = false;
let arePricesFresh = false;
// Initial discovery may not cover tokens persisted separately by the client.
// Cache replays and explicit refreshes after the first fresh send retain normal full-snapshot semantics.
let hasSentFreshTokens = false;
let pendingTokenUpdate: OnApiUpdate | undefined;
const tokensCache: {
  bySlug: Record<string, ApiTokenWithPrice>;
} = {
  bySlug: { ...getTokenInfo() },
};
/**
 * The slugs of the cached tokens by address key, so that a lookup without a chain does not scan the whole cache. A slug
 * stays listed after another address takes it, so the lookup checks the address of every token it finds.
 */
const slugsByAddressKey = new Map<string, Set<string>>();
Object.values(tokensCache.bySlug).forEach(indexTokenAddress);
// getTokenInfo fills absent prices with zero; retain which values are placeholders before that conversion.
const unpricedSlugs = new Set(getSupportedChains().flatMap((chain) => (
  getChainConfig(chain).tokenInfo.filter((token) => token.priceUsd === undefined).map((token) => token.slug)
)));
let lastUnpricedSlugs: Set<string> | undefined;
/**
 * The tokens as the UI last received them, so that a refresh sends only what changed since. Sending the whole cache
 * costs the UI thread megabytes of structured clone on every price tick.
 *
 * The snapshot is not saved while the prices are stale: the UI then keeps its own prices and ignores the sent ones
 * (see `updateTokens` in `global/reducers/misc.ts`). After such a send the worker does not know what the UI really
 * holds, so the next send goes in full.
 *
 */
let lastTokensBySlug: Record<string, ApiTokenWithPrice> | undefined;
/**
 * Counts the UI connections. A backend request outlives the UI that started it, and its callback then delivers into
 * a closed port without an error, so such a request must not record its send as received by the current UI.
 */
let uiGeneration = 0;

export async function loadTokensCache() {
  try {
    const tokens = await tokenRepository.all();
    await updateTokens(tokens);
  } finally {
    tokensPreload.resolve();
  }
}

export function fetchBackendTokenDetails(assets: string[], langCode?: string): Promise<ApiTokenPriceDetails[]> {
  return callBackendPost<ApiTokenPriceDetails[]>(buildTokenDetailsPath(langCode), { assets });
}

/**
 * Picks the tokens to ask `POST /assets` about. The catalog covers the enabled tokens, so the request is
 * for the rest: the rug pulled, the disabled and whatever the backend does not publish.
 */
export function pickTokensForDetails(tokens: ApiTokenWithPrice[], options: {
  /** Slugs returned by the backend catalog */
  backendSlugs: Set<string>;
  /** When given, the payload is limited to the tokens the polled wallets hold */
  heldSlugs?: Set<string>;
  maxCount: number;
}) {
  const { backendSlugs, heldSlugs, maxCount } = options;
  const result: ApiTokenWithPrice[] = [];

  for (const token of tokens) {
    if (!token.tokenAddress || backendSlugs.has(token.slug)) continue;
    if (getHasFullTokenSlug(token)) continue;
    // `type` arrives from this very endpoint, so an unclassified LP token is still requested once. Afterwards it is
    // dropped: an LP token has no price of its own and the UI treats it as a service token.
    if (token.type === 'lp_token') continue;
    if (heldSlugs && !heldSlugs.has(token.slug)) continue;

    result.push(token);

    if (result.length >= maxCount) break;
  }

  return result;
}

/** Loads backend tokens, tops them up with the details of the tokens the catalog doesn't cover, and caches both */
export async function updateTokensFromBackend(
  onUpdate: OnApiUpdate,
  options: TokenDetailsOptions = {},
  onCurrencyRates?: (rates: ApiCurrencyRates | undefined) => void,
) {
  const { langCode } = options;
  const generation = uiGeneration;

  try {
    const tokens = await fetchBackendTokens(langCode, (rates) => {
      if (generation === uiGeneration) onCurrencyRates?.(rates);
    });

    for (const token of tokens) {
      token.isFromBackend = true;
      token.isPriceFromBackend = token.priceUsd !== undefined;
    }

    await tokensPreload.promise;

    backendTokenSlugs = new Set(tokens.map((token) => token.slug));

    // A failed top-up must not discard the catalog, which is the part the UI waits for
    const nonBackendTokenDetails = await fetchNonBackendTokenDetails(options).catch((err) => {
      logDebugError('fetchNonBackendTokenDetails', err);
      return undefined;
    });

    // The UI this request was started for is gone; the current one gets the result from its own request, which may
    // have already cached a newer response than this one
    if (generation !== uiGeneration) return;

    const update = updateTokens(tokens, () => {
      if (generation !== uiGeneration) return;
      arePricesFresh = true;
      sendUpdateTokens(onUpdate);
    }, nonBackendTokenDetails, true);
    // `updateTokens` fills the cache before it writes the database, and the slugs depend on the cache alone
    catalogPreload.resolve();
    await update;
  } finally {
    // The response for a closed UI is dropped above, so only the current one ends the wait
    if (generation === uiGeneration) catalogPreload.resolve();
  }
}

export async function fetchBackendTokens(
  langCode?: string,
  onCurrencyRates?: (rates: ApiCurrencyRates | undefined) => void,
): Promise<ApiTokenWithMaybePrice[]> {
  if (Date.now() < legacyAssetsUntil) {
    onCurrencyRates?.(undefined);
    return callBackendGet<ApiTokenWithPrice[]>('/assets', { langCode });
  }

  try {
    let catalog = backendTokenCatalog?.langCode === langCode ? backendTokenCatalog : undefined;
    const pricesRequest = callBackendGet<BackendTokenPrices>('/assets/prices');
    const catalogRequest = !catalog ? fetchBackendTokenCatalog(langCode).then(
      (value) => ({ value }),
      (error: unknown) => ({ error }),
    ) : undefined;

    const { catalogVersion, prices, rates } = await pricesRequest;
    onCurrencyRates?.(isCurrencyRates(rates) ? rates : undefined);
    if (Date.now() < legacyAssetsUntil) {
      onCurrencyRates?.(undefined);
      return callBackendGet<ApiTokenWithPrice[]>('/assets', { langCode });
    }
    const catalogResult = catalogRequest ? await catalogRequest : { value: catalog! };
    if ('error' in catalogResult) throw catalogResult.error;
    catalog = catalogResult.value;

    if (!catalogRequest && catalog.version !== catalogVersion) {
      try {
        catalog = { ...await fetchBackendTokenCatalog(langCode, catalogVersion), langCode };
      } catch (err) {
        if (err instanceof ApiServerError && err.statusCode === 404) throw err;
        logDebugError('fetchBackendTokenCatalog', err);
      }
    }

    const hasMatchingVersion = catalog.version === catalogVersion;
    return catalog.assets.map((token) => {
      const priceUsd = hasMatchingVersion ? prices[token.slug]?.[0] : undefined;
      return {
        ...token,
        priceUsd,
        // A missing change keeps the cached value, or becomes zero for a newly discovered token
        percentChange24h: hasMatchingVersion ? prices[token.slug]?.[1] ?? undefined : undefined,
        // Catalog may omit precision; derive only then so an explicit backend value is kept
        ...(priceUsd !== undefined && token.precision === undefined && {
          precision: pricePrecisionFromUsdPrice(priceUsd),
        }),
      };
    });
  } catch (err) {
    if (err instanceof ApiServerError && err.statusCode === 404) {
      legacyAssetsUntil = Date.now() + LEGACY_ASSETS_RETRY_DELAY;
    }
    if (Date.now() >= legacyAssetsUntil) throw err;
    onCurrencyRates?.(undefined);
    return callBackendGet<ApiTokenWithPrice[]>('/assets', { langCode });
  }
}

function isCurrencyRates(rates: unknown): rates is ApiCurrencyRates {
  return isLiteralObject(rates) && Object.keys(CURRENCIES).every((currency) => isUsableRate(rates[currency]));
}

async function fetchBackendTokenCatalog(langCode: string | undefined, version?: string): Promise<BackendTokenCatalog> {
  const key = JSON.stringify([langCode, version]);
  const pending = backendCatalogRequests.get(key);
  if (pending) return pending;

  const request = callBackendGet<BackendTokenCatalog>('/assets/catalog', { langCode }).then((catalog) => {
    backendTokenCatalog = { ...catalog, langCode };
    return catalog;
  });
  backendCatalogRequests.set(key, request);
  try {
    return await request;
  } catch (err) {
    if (err instanceof ApiServerError && err.statusCode === 404) {
      legacyAssetsUntil = Date.now() + LEGACY_ASSETS_RETRY_DELAY;
    }
    throw err;
  } finally {
    backendCatalogRequests.delete(key);
  }
}

export async function fetchNonBackendTokenDetails(
  options: TokenDetailsOptions = {},
): Promise<TokenDetailsUpdate[] | undefined> {
  const { langCode, shouldNarrowToHeldTokens } = options;
  // POST is used to retrieve data because the addresses may not fit into a URL
  const requestedTokens = pickTokensForDetails(Object.values(tokensCache.bySlug), {
    backendSlugs: backendTokenSlugs,
    heldSlugs: shouldNarrowToHeldTokens ? getHeldSlugs() : undefined,
    maxCount: MAX_POST_TOKENS,
  });

  if (!requestedTokens.length) return undefined;

  const details = await fetchBackendTokenDetails(requestedTokens.map((token) => token.tokenAddress!), langCode);
  const detailsBySlug = buildCollectionByKey(details, 'slug');
  const updates: TokenDetailsUpdate[] = [...details];
  // A successful omission releases price ownership without discarding the last quote. Failed requests never get here.
  for (const { slug, isPriceFromBackend } of requestedTokens) {
    if (isPriceFromBackend && !backendTokenSlugs.has(slug) && detailsBySlug[slug]?.priceUsd === undefined) {
      updates.push({ slug, isPriceFromBackend: false });
    }
  }

  return updates;
}

function buildTokenDetailsPath(langCode?: string) {
  if (!langCode) {
    return '/assets';
  }

  return `/assets?${new URLSearchParams({ langCode }).toString()}`;
}

export async function updateTokens(
  tokens: ApiTokenWithMaybePrice[],
  sendUpdate?: NoneToVoidFunction,
  tokenDetails?: TokenDetailsUpdate[],
  shouldSendUpdate?: boolean,
) {
  const tokensForDb: ApiTokenWithPrice[] = [];
  const detailsBySlug = buildCollectionByKey(tokenDetails ?? [], 'slug');

  for (const { slug, ...details } of tokenDetails ?? []) {
    const cachedToken = tokensCache.bySlug[slug] as ApiTokenWithPrice | undefined;
    if (cachedToken) {
      const token = {
        ...cachedToken,
        ...details,
        ...(details.priceUsd !== undefined && { isPriceFromBackend: true }),
      };
      cacheToken(token);
      tokensForDb.push(token);
      if (details.priceUsd !== undefined) unpricedSlugs.delete(slug);
    }
  }

  // A cached `isFromBackend` may come from an earlier catalog, so only the tokens listed here count as the catalog's.
  // They are keyed by the full slug, as the catalog may list one address on several chains.
  const catalogSlugByFullSlug = new Map<string, string>();
  for (const { isFromBackend, chain, tokenAddress, slug } of tokens) {
    if (isFromBackend && tokenAddress) catalogSlugByFullSlug.set(buildFullTokenSlug(chain, tokenAddress), slug);
  }
  const movedSlugs: string[] = [];

  for (let token of tokens) {
    let cachedToken = tokensCache.bySlug[token.slug] as ApiTokenWithPrice | undefined;
    // The catalog gives the slug to its own token, and the token that held it moves to its full slug. Of two tokens
    // this catalog lists under one slug, the one with the smaller address key keeps it, so the order of the catalog
    // does not move them back and forth.
    if (cachedToken?.tokenAddress && token.isFromBackend && token.tokenAddress
      && !getIsSameTokenAddress(cachedToken.tokenAddress, token.tokenAddress)) {
      const holderAddressKey = buildTokenAddressKey(cachedToken.tokenAddress);
      if (catalogSlugByFullSlug.get(buildFullTokenSlug(cachedToken.chain, cachedToken.tokenAddress)) === token.slug
        && holderAddressKey < buildTokenAddressKey(token.tokenAddress)) {
        token = { ...token, slug: buildFullTokenSlug(token.chain, token.tokenAddress) };
        cachedToken = tokensCache.bySlug[token.slug];
      } else {
        tokensForDb.push(moveTokenToFullSlug(cachedToken));
        movedSlugs.push(token.slug);
        cachedToken = undefined;
      }
    }
    // A catalog token that leaves its full slug for this one keeps the data its chain gave it there, and the balances
    // stored under the full slug are refetched
    const aliasToken = !cachedToken && token.isFromBackend && token.tokenAddress
      ? tokensCache.bySlug[buildFullTokenSlug(token.chain, token.tokenAddress)] as ApiTokenWithPrice | undefined
      : undefined;
    if (aliasToken) movedSlugs.push(aliasToken.slug);
    const { slug } = token;
    const mergedToken = mergeTokenWithCache(token, detailsBySlug, cachedToken ?? aliasToken);

    if (cachedToken === undefined) {
      shouldSendUpdate = true;
      if (!aliasToken || unpricedSlugs.has(aliasToken.slug)) unpricedSlugs.add(slug);
    }
    if (token.priceUsd !== undefined || detailsBySlug[slug]?.priceUsd !== undefined) unpricedSlugs.delete(slug);

    cacheToken(mergedToken);
    if (token.tokenAddress) {
      tokensForDb.push(mergedToken);
    }
  }

  if (movedSlugs.length) notifyTokenSlugsMove(movedSlugs);

  await tokenRepository.bulkPut(tokensForDb);

  if (shouldSendUpdate && sendUpdate) {
    sendUpdate();
  }
}

function mergeTokenWithCache(
  token: ApiTokenWithMaybePrice,
  detailsBySlug: Record<string, TokenDetailsUpdate>,
  cachedToken?: ApiTokenWithPrice,
): ApiTokenWithPrice {
  if (cachedToken) {
    const priceSource = cachedToken.isPriceFromBackend && !token.isPriceFromBackend ? cachedToken : token;
    // Metadata from backend takes priority (e.g., image)
    return {
      ...omitUndefined(token.isFromBackend ? cachedToken : token),
      ...omitUndefined(token.isFromBackend ? token : cachedToken),
      ...(token.isFromBackend && { localizedName: token.localizedName }),
      priceUsd: priceSource.priceUsd ?? cachedToken.priceUsd,
      percentChange24h: priceSource.percentChange24h ?? cachedToken.percentChange24h,
      // For the scenario where the token was cached previously, but now it's disabled
      ...omitUndefined((detailsBySlug[token.slug] as TokenDetailsUpdate | undefined) ?? {}),
      ...(token.slug in detailsBySlug && { isFromBackend: undefined }),
    };
  } else if (token.slug in detailsBySlug) {
    return {
      ...token,
      ...detailsBySlug[token.slug],
      priceUsd: detailsBySlug[token.slug]?.priceUsd ?? token.priceUsd ?? 0,
      percentChange24h: detailsBySlug[token.slug]?.percentChange24h ?? token.percentChange24h ?? 0,
      isFromBackend: undefined,
      ...(detailsBySlug[token.slug]?.priceUsd !== undefined && { isPriceFromBackend: true }),
    };
  } else {
    return {
      ...token,
      priceUsd: token.priceUsd ?? 0,
      percentChange24h: token.percentChange24h ?? 0,
    };
  }
}

/** The moved token gets no more backend details, so its last backend price no longer outranks provider prices */
function moveTokenToFullSlug(token: ApiTokenWithPrice) {
  const slug = buildFullTokenSlug(token.chain, token.tokenAddress!);
  // The token under the backend slug got every update since it took that slug, so it outranks an older full-slug copy,
  // which fills in only what that token lacks
  const movedToken = { ...tokensCache.bySlug[slug], ...omitUndefined(token), slug, isPriceFromBackend: false };
  cacheToken(movedToken);
  unpricedSlugs.delete(slug);
  if (unpricedSlugs.delete(token.slug)) unpricedSlugs.add(slug);

  return movedToken;
}

function cacheToken(token: ApiTokenWithPrice) {
  tokensCache.bySlug[token.slug] = token;
  indexTokenAddress(token);
}

function indexTokenAddress({ slug, tokenAddress }: ApiTokenWithPrice) {
  if (!tokenAddress) return;

  const addressKey = buildTokenAddressKey(tokenAddress);
  const slugs = slugsByAddressKey.get(addressKey);
  if (slugs) {
    slugs.add(slug);
  } else {
    slugsByAddressKey.set(addressKey, new Set([slug]));
  }
}

export function getTokensCache() {
  return tokensCache;
}

/** Note that this function may return `undefined` if the token is not found (e.g. pTON) */
export function getTokenBySlug(slug: string): ApiTokenWithPrice | undefined {
  return tokensCache.bySlug[slug];
}

export function getTokenByAddress(tokenAddress: string, chain?: ApiChain) {
  if (chain) return getTokenBySlug(buildTokenSlug(chain, tokenAddress));

  const addressKey = buildTokenAddressKey(tokenAddress);
  const matches = [...slugsByAddressKey.get(addressKey) ?? []].flatMap((slug) => {
    const token = getTokenBySlug(slug);
    return token?.tokenAddress && buildTokenAddressKey(token.tokenAddress) === addressKey ? [token] : [];
  });

  const matchedToken = matches[0];
  if (!matchedToken || matches.some((token) => token.chain !== matchedToken.chain)) return undefined;

  // Balances can still refer to a full-slug alias after the catalog gives this token its backend slug
  return getTokenBySlug(buildTokenSlug(matchedToken.chain, tokenAddress)) ?? matchedToken;
}

export function sendUpdateTokens(onUpdate: OnApiUpdate) {
  if (isTokenUpdatePaused) {
    pendingTokenUpdate = onUpdate;
    return;
  }

  const kind: ApiTokenUpdateKind = !arePricesFresh ? 'fromCache' : lastTokensBySlug ? 'partial' : 'full';
  const isIncomplete = !hasSentFreshTokens;
  const { tokens, removedSlugs } = kind === 'partial'
    ? pickChangedTokens(tokensCache.bySlug, lastTokensBySlug!)
    : { tokens: tokensCache.bySlug, removedSlugs: undefined };
  lastTokensBySlug = arePricesFresh ? { ...tokensCache.bySlug } : undefined;
  lastUnpricedSlugs = arePricesFresh ? new Set(unpricedSlugs) : undefined;
  if (arePricesFresh) hasSentFreshTokens = true;

  if (kind === 'partial' && isEmptyObject(tokens) && !removedSlugs?.length) return;

  const includedUnpricedSlugs = Object.keys(tokens).filter((slug) => unpricedSlugs.has(slug));
  onUpdate({
    type: 'updateTokens',
    kind,
    tokens,
    ...(isIncomplete && { isIncomplete }),
    ...(includedUnpricedSlugs.length && { unpricedSlugs: includedUnpricedSlugs }),
    ...(removedSlugs?.length && { removedSlugs }),
  });
}

/** Forgets what the UI holds, so that a new UI connection receives the complete token list first */
export function resetLastTokens() {
  lastTokensBySlug = undefined;
  lastUnpricedSlugs = undefined;
}

function pickChangedTokens(
  tokensBySlug: Record<string, ApiTokenWithPrice>,
  sentBySlug: Record<string, ApiTokenWithPrice>,
) {
  const tokens: Record<string, ApiTokenWithPrice> = {};

  for (const slug in tokensBySlug) {
    const token = tokensBySlug[slug];
    const sentToken = sentBySlug[slug];
    const hasNewPrice = unpricedSlugs.has(slug) !== lastUnpricedSlugs?.has(slug);
    if (!sentToken || hasNewPrice || (sentToken !== token && !areDeepEqual(sentToken, token))) {
      tokens[slug] = token;
    }
  }

  const removedSlugs = Object.keys(sentBySlug).filter((slug) => !(slug in tokensBySlug));

  return { tokens, removedSlugs };
}

/** Called when a UI connects: holds the sends until its first backend request settles */
export function pauseTokenUpdates() {
  uiGeneration += 1;
  isTokenUpdatePaused = true;
  isCatalogRequested = true;
  arePricesFresh = false;
  resetLastTokens();
  pendingTokenUpdate = undefined;
}

export function resumeTokenUpdates() {
  isTokenUpdatePaused = false;

  const onUpdate = pendingTokenUpdate;
  pendingTokenUpdate = undefined;
  if (onUpdate) {
    sendUpdateTokens(onUpdate);
  }
}

/**
 * Waits until the slugs of the tokens found on a wallet can be assigned and returns the resolver for one response. A
 * token found before the first token catalog of the worker could take the backend slug the catalog gives to another
 * token. The resolver must assign the slugs in the same synchronous run that writes the tokens to the cache.
 */
export async function waitForTokenSlugResolver(signal?: AbortSignal) {
  if (isCatalogRequested) {
    catalogWait ??= tokensPreload.promise.then(() => Promise.race([
      catalogPreload.promise,
      pause(CATALOG_WAIT_TIMEOUT),
    ]));
    await raceWithAbortSignal(catalogWait, signal);
  }

  return resolveTokenSlugs;
}

/**
 * Caches the tokens fetched together and returns them, in the same order, with their slugs. They may share a backend
 * slug, so the slugs of the tokens with an address are assigned together, right before the cache gets them. A token
 * without an address keeps its own slug.
 */
export async function updateTokensFetchedTogether(tokens: FetchedToken[], options: {
  signal?: AbortSignal;
  sendUpdate?: NoneToVoidFunction;
  shouldSendUpdate?: boolean;
} = {}) {
  const { signal, sendUpdate, shouldSendUpdate } = options;
  const resolveSlugs = await waitForTokenSlugResolver(signal);
  const slugs = resolveSlugs(tokens.flatMap(({ chain, tokenAddress }) => (
    tokenAddress ? [{ chain, address: tokenAddress }] : []
  )));
  let slugIndex = 0;
  const tokensWithSlugs = tokens.map((token): ApiTokenWithMaybePrice => ({
    ...token,
    slug: token.tokenAddress ? slugs[slugIndex++] : token.slug!,
  }));
  await updateTokens(tokensWithSlugs, sendUpdate, undefined, shouldSendUpdate);

  return tokensWithSlugs;
}

/**
 * The slug of the token at this address. It is the slug the backend derives from the address unless the cache holds
 * another token under it, which takes the full slug of its address instead.
 */
export function buildTokenSlug(chain: ApiChain, address: string) {
  const slug = buildBackendTokenSlug(chain, address);
  const holderAddress = tokensCache.bySlug[slug]?.tokenAddress;

  return holderAddress && !getIsSameTokenAddress(holderAddress, address) ? buildFullTokenSlug(chain, address) : slug;
}

/**
 * A token gets the full slug of its address when another token holds the backend slug of that address. `POST /assets`
 * still returns its details under the backend slug, so a request with both tokens gets two answers under one slug and
 * can't tell them apart.
 */
export function getHasFullTokenSlug(
  { slug, chain, tokenAddress }: Pick<ApiTokenWithPrice, 'slug' | 'chain' | 'tokenAddress'>,
) {
  if (!tokenAddress) return false;

  return slug !== buildBackendTokenSlug(chain, tokenAddress) && slug === buildFullTokenSlug(chain, tokenAddress);
}

/**
 * Assigns the slugs of the tokens found together, which do not reach the cache before all of them are assigned. Of
 * those that share a backend slug the cache does not hold, the one with the smallest address key keeps it and the
 * others take their full slugs. The order of a response therefore does not decide which token gets the slug, which
 * matters where the cache starts empty on every launch (Air).
 */
function resolveTokenSlugs(tokens: { chain: ApiChain; address: string }[]) {
  const slugs = tokens.map(({ chain, address }) => buildTokenSlug(chain, address));
  const addressKeys = tokens.map(({ address }) => buildTokenAddressKey(address));
  const ownerKeyBySlug = new Map<string, string>();

  slugs.forEach((slug, i) => {
    const ownerKey = ownerKeyBySlug.get(slug);
    if (ownerKey === undefined || addressKeys[i] < ownerKey) ownerKeyBySlug.set(slug, addressKeys[i]);
  });

  return tokens.map(({ chain, address }, i) => (
    ownerKeyBySlug.get(slugs[i]) === addressKeys[i] ? slugs[i] : buildFullTokenSlug(chain, address)
  ));
}

/**
 * The slug the backend gives the token at this address: the chain and the first 10 characters of the address key, in
 * lower case
 */
function buildBackendTokenSlug(chain: ApiChain, address: string) {
  return `${chain}-${buildTokenAddressKey(address).slice(0, 10)}`.toLowerCase();
}

/** Keeps the whole address key, so it is longer than any backend slug and has the one `-` the apps parse slugs by */
function buildFullTokenSlug(chain: ApiChain, address: string) {
  return `${chain}-${buildTokenAddressKey(address)}`.toLowerCase();
}

function getIsSameTokenAddress(address: string, otherAddress: string) {
  return buildTokenAddressKey(address) === buildTokenAddressKey(otherAddress);
}

/** The alphanumeric characters of the address in lower case, the same for every spelling of an EVM address */
function buildTokenAddressKey(address: string) {
  return address.replace(/[^a-z\d]/gi, '').toLowerCase();
}
