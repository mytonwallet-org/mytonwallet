import type { LangCode, TokenDetailsState, UserToken } from '../types';

import { MINUTE } from '../../util/dateFormat';

const TOKEN_DETAILS_LIFETIME = 15 * MINUTE;
const TOKEN_DETAILS_PRELOAD_LIMIT = 50;

/** Picks the tokens the user is most likely to open: the top of the visible token list of the account */
export function pickTokenDetailsSlugsToPreload(
  tokens: UserToken[],
  detailsBySlug: Record<string, TokenDetailsState>,
  langCode: LangCode,
  now: number,
) {
  return tokens
    .filter(({ isDisabled }) => !isDisabled)
    .slice(0, TOKEN_DETAILS_PRELOAD_LIMIT)
    .filter(({ slug }) => !getIsTokenDetailsFresh(detailsBySlug[slug], langCode, now))
    .map(({ slug }) => slug);
}

/** Fresh details are not requested by the preload and are the only ones that survive an app restart */
export function getIsTokenDetailsFresh(details: TokenDetailsState | undefined, langCode: LangCode, now: number) {
  return details?.langCode === langCode && now - details.fetchedAt! < TOKEN_DETAILS_LIFETIME;
}
