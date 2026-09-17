import type { ApiNetwork, ApiTokenWithPrice } from '../../types';

import { raceWithAbortSignal, throwIfAborted } from '../../../util/abortSignal';
import { buildCollectionByKey } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { getTokensCache, tokensPreload, updateTokens } from '../../common/tokens';
import { getAccountStates } from './toncenter';

export async function updateTokenHashes(
  network: ApiNetwork,
  tokenSlugs: string[],
  sendUpdateTokens?: NoneToVoidFunction,
  signal?: AbortSignal,
) {
  await raceWithAbortSignal(tokensPreload.promise, signal);
  const cachedTokens = getTokensCache().bySlug;

  const tokensToFetch = tokenSlugs.reduce<ApiTokenWithPrice[]>((tokensToFetch, tokenSlug) => {
    const token = cachedTokens[tokenSlug];

    if (
      token
      && token.chain === 'ton'
      && !token.codeHash
      && ['LP', 'STAKED', 'POOL'].some((option) => token.symbol.toUpperCase().includes(option))
    ) {
      tokensToFetch.push(token);
    }

    return tokensToFetch;
  }, []);

  if (!tokensToFetch.length) {
    return;
  }

  const tokensByAddress = buildCollectionByKey(tokensToFetch, 'tokenAddress');

  try {
    const states = await getAccountStates(network, tokensToFetch.map((token) => token.tokenAddress!), signal);

    for (const address of Object.keys(states)) {
      if (!tokensByAddress[address]) continue;
      tokensByAddress[address] = {
        ...tokensByAddress[address],
        codeHash: Buffer.from(states[address].code_hash, 'base64').toString('hex'),
      };
    }

    const updatedTokens = Object.values(tokensByAddress).filter((token) => token.codeHash).map((token) => ({
      ...token,
      // This request fetched only code hashes; its cached prices may be placeholders or outdated by now.
      priceUsd: undefined,
      percentChange24h: undefined,
    }));
    if (updatedTokens.length) {
      await updateTokens(updatedTokens, sendUpdateTokens, [], true);
    }
  } catch (err) {
    throwIfAborted(signal);
    logDebugError('Failed to fetch contract code hashes for tokens', err);
  }
}
