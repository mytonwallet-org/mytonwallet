import type { UserToken } from '../../../global/types';
import type { LangFn } from '../../../util/langProvider';

import { STAKING_SLUG_PREFIX, TON_USDE } from '../../../config';

const ETHENA_STAKING_SLUG = `${STAKING_SLUG_PREFIX}${TON_USDE.slug}`;

export default function getTokenName(lang: LangFn, token: UserToken) {
  if (!token.isStaking) {
    return token.name;
  }

  switch (token.slug) {
    case ETHENA_STAKING_SLUG:
      return lang('%token% Staking', { token: 'Ethena' })[0] as string;
    default:
      return lang('%token% Staking', { token: token.name })[0] as string;
  }
}
