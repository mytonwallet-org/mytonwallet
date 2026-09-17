import type { LangCode } from '../../global/types';
import type { ApiSite, ApiSiteCategory } from '../types';

import { callBackendGet } from '../common/backend';

/** An editorial dapp listing served by the backend. It has its own module so a build can drop it alone. */
export function loadExploreSites(
  { isLandscape, langCode }: { isLandscape: boolean; langCode: LangCode },
  signal?: AbortSignal,
): Promise<{ categories: ApiSiteCategory[]; sites: ApiSite[] }> {
  return callBackendGet('/v2/dapp/catalog', { isLandscape, langCode }, undefined, signal);
}
