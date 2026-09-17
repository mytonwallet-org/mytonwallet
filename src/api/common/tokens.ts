import {
  type ApiChain,
  type ApiTokenPriceDetails,
  type ApiTokenUpdateKind,
  type ApiTokenWithMaybePrice,
  type ApiTokenWithPrice,
  type OnApiUpdate,
} from '../types';

import { areDeepEqual } from '../../util/areDeepEqual';
import { getChainConfig, getSupportedChains, getTokenInfo } from '../../util/chain';
import Deferred from '../../util/Deferred';
import isEmptyObject from '../../util/isEmptyObject';
import { buildCollectionByKey, omitUndefined } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { tokenRepository } from '../db';
import { callBackendGet, callBackendPost } from './backend';
import { getHeldSlugs } from './heldTokens';

/** A backstop for the token details payload, which is normally bounded by the number of the tokens on the device */
const MAX_POST_TOKENS = 1500;

export type TokenDetailsOptions = {
  langCode?: string;
  /** Limits the payload to the tokens the polled wallets hold. Off for the runtimes that poll no wallet. */
  shouldNarrowToHeldTokens?: boolean;
};

type TokenDetailsUpdate = Partial<ApiTokenPriceDetails> & Pick<ApiTokenWithPrice, 'slug' | 'isPriceFromBackend'>;

export const tokensPreload = new Deferred();
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

  await updateTokens(tokens, () => {
    if (generation !== uiGeneration) return;
    arePricesFresh = true;
    sendUpdateTokens(onUpdate);
  }, nonBackendTokenDetails, true);
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

  for (const token of tokens) {
    const { slug } = token;
    const cachedToken = tokensCache.bySlug[slug] as ApiTokenWithPrice | undefined;
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

export function getTokensCache() {
  return tokensCache;
}

/** Note that this function may return `undefined` if the token is not found (e.g. pTON) */
export function getTokenBySlug(slug: string): ApiTokenWithPrice | undefined {
  return tokensCache.bySlug[slug];
}

export function getTokenByAddress(tokenAddress: string, chain?: ApiChain) {
  if (chain) return getTokenBySlug(buildTokenSlug(chain, tokenAddress));

  const normalizedAddress = normalizeTokenAddress(tokenAddress);
  const matches = Object.values(tokensCache.bySlug).filter((token) => {
    return token.tokenAddress && normalizeTokenAddress(token.tokenAddress) === normalizedAddress;
  });

  return matches.length === 1 ? matches[0] : undefined;
}

function normalizeTokenAddress(tokenAddress: string) {
  return tokenAddress.trim().toLowerCase();
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

export function buildTokenSlug(chain: ApiChain, address: string) {
  const addressPart = address.replace(/[^a-z\d]/gi, '').slice(0, 10);
  return `${chain}-${addressPart}`.toLowerCase();
}
