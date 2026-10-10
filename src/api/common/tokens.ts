import {
  type ApiChain,
  type ApiTokenPriceDetails,
  type ApiTokenUpdateKind,
  type ApiTokenWithMaybePrice,
  type ApiTokenWithPrice,
  type OnApiUpdate,
} from '../types';

import { raceWithAbortSignal } from '../../util/abortSignal';
import { areDeepEqual } from '../../util/areDeepEqual';
import { getChainConfig, getSupportedChains, getTokenInfo } from '../../util/chain';
import Deferred from '../../util/Deferred';
import isEmptyObject from '../../util/isEmptyObject';
import { buildCollectionByKey, omitUndefined } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { tokenRepository } from '../db';
import { callBackendGet, callBackendPost } from './backend';
import { getHeldSlugs } from './heldTokens';
import { notifyTokenSlugsMove } from './tokenSlugMoves';

/** A backstop for the token details payload, which is normally bounded by the number of the tokens on the device */
const MAX_POST_TOKENS = 1500;

export type TokenDetailsOptions = {
  langCode?: string;
  /** Limits the payload to the tokens the polled wallets hold. Off for the runtimes that poll no wallet. */
  shouldNarrowToHeldTokens?: boolean;
};

type TokenDetailsUpdate = Partial<ApiTokenPriceDetails> & Pick<ApiTokenWithPrice, 'slug' | 'isPriceFromBackend'>;

export const tokensPreload = new Deferred();
/**
 * Settles when a `GET /assets` request of the current UI has applied the token catalog to the cache or failed. The
 * database write that follows is not awaited. `isCatalogRequested` tells whether the worker requests the catalog, so
 * that runtimes without it never wait.
 */
const catalogPreload = new Deferred();
let isCatalogRequested = false;
/** Slugs of the last `GET /assets` response, reused when the details are requested outside `updateTokensFromBackend` */
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
 * Picks the tokens to ask `POST /assets` about. `GET /assets` covers the enabled tokens, so the request is
 * for the rest: the rug pulled, the disabled and whatever the backend does not publish.
 */
export function pickTokensForDetails(tokens: ApiTokenWithPrice[], options: {
  /** Slugs returned by `GET /assets` */
  backendSlugs: Set<string>;
  /** When given, the payload is limited to the tokens the polled wallets hold */
  heldSlugs?: Set<string>;
  maxCount: number;
}) {
  const { backendSlugs, heldSlugs, maxCount } = options;
  const result: ApiTokenWithPrice[] = [];

  for (const token of tokens) {
    if (!token.tokenAddress || backendSlugs.has(token.slug)) continue;
    // The details come back under the backend slug of the address, which another token holds for a token with a full slug
    if (token.slug !== buildBackendTokenSlug(token.chain, token.tokenAddress)) continue;
    // `type` arrives from this very endpoint, so an unclassified LP token is still requested once. Afterwards it is
    // dropped: an LP token has no price of its own and the UI treats it as a service token.
    if (token.type === 'lp_token') continue;
    if (heldSlugs && !heldSlugs.has(token.slug)) continue;

    result.push(token);

    if (result.length >= maxCount) break;
  }

  return result;
}

/** Loads `GET /assets`, tops it up with the details of the tokens it doesn't cover, and applies both to the cache */
export async function updateTokensFromBackend(onUpdate: OnApiUpdate, options: TokenDetailsOptions = {}) {
  const { langCode } = options;
  const generation = uiGeneration;

  try {
    const tokens = await callBackendGet<ApiTokenWithPrice[]>('/assets', { langCode });

    for (const token of tokens) {
      token.isFromBackend = true;
      token.isPriceFromBackend = token.priceUsd !== undefined;
    }

    await tokensPreload.promise;

    backendTokenSlugs = new Set(tokens.map((token) => token.slug));

    // A failed top-up must not discard the `GET /assets` response, which is the part the UI waits for
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
      tokensCache.bySlug[slug] = token;
      tokensForDb.push(token);
      if (details.priceUsd !== undefined) unpricedSlugs.delete(slug);
    }
  }

  // A cached `isFromBackend` may come from an earlier catalog, so only the tokens listed here count as the catalog's
  const catalogAddressKeys = new Set<string>();
  for (const { isFromBackend, tokenAddress } of tokens) {
    if (isFromBackend && tokenAddress) catalogAddressKeys.add(buildTokenAddressKey(tokenAddress));
  }
  const movedSlugs: string[] = [];

  for (let token of tokens) {
    let cachedToken = tokensCache.bySlug[token.slug] as ApiTokenWithPrice | undefined;
    // The catalog gives the slug to its own token, and the token that held it moves to its full slug. The moved row
    // goes to the database first, as the slug is unique there. Of two tokens this catalog lists under one slug, the
    // one with the smaller address key keeps it, so the order of the catalog does not move them back and forth.
    if (cachedToken?.tokenAddress && token.isFromBackend && token.tokenAddress
      && !getIsSameTokenAddress(cachedToken.tokenAddress, token.tokenAddress)) {
      const holderAddressKey = buildTokenAddressKey(cachedToken.tokenAddress);
      if (catalogAddressKeys.has(holderAddressKey) && holderAddressKey < buildTokenAddressKey(token.tokenAddress)) {
        token = { ...token, slug: buildFullTokenSlug(token.chain, token.tokenAddress) };
        cachedToken = tokensCache.bySlug[token.slug];
      } else {
        tokensForDb.push(moveTokenToFullSlug(cachedToken));
        movedSlugs.push(token.slug);
        cachedToken = undefined;
      }
    }
    const { slug } = token;
    const mergedToken = mergeTokenWithCache(token, detailsBySlug, cachedToken);

    if (cachedToken === undefined) {
      shouldSendUpdate = true;
      unpricedSlugs.add(slug);
    }
    if (token.priceUsd !== undefined || detailsBySlug[slug]?.priceUsd !== undefined) unpricedSlugs.delete(slug);

    tokensCache.bySlug[token.slug] = mergedToken;
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
  tokensCache.bySlug[slug] ??= { ...token, slug, isPriceFromBackend: false };
  if (unpricedSlugs.delete(token.slug)) unpricedSlugs.add(slug);

  return tokensCache.bySlug[slug];
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
  const matches = Object.values(tokensCache.bySlug).filter((token) => {
    return token.tokenAddress && buildTokenAddressKey(token.tokenAddress) === addressKey;
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
  if (isCatalogRequested) await raceWithAbortSignal(catalogPreload.promise, signal);

  return resolveTokenSlugs;
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
