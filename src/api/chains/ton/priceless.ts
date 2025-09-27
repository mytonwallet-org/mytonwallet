import type { ApiNetwork, ApiTokenWithPrice } from '../../types';

import { buildCollectionByKey } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { getTokensCache, tokensPreload, updateTokens } from '../../common/tokens';
import { getAccountStates } from './toncenter';

export async function updateTokenHashes(
  network: ApiNetwork,
  tokenSlugs: string[],
  sendUpdateTokens?: NoneToVoidFunction,
) {
  await tokensPreload.promise;
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
    const states = await getAccountStates(network, tokensToFetch.map((token) => token.tokenAddress!));

    for (const address of Object.keys(states)) {
      if (!tokensByAddress[address]) continue;
      tokensByAddress[address].codeHash = Buffer.from(states[address].code_hash, 'base64').toString('hex');
    }

    await updateTokens(Object.values(tokensByAddress).filter((token) => token.codeHash), sendUpdateTokens);
  } catch (err) {
    logDebugError('Failed to fetch contract code hashes for tokens', err);
  }
}
