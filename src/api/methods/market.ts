import type { LangCode } from '../../global/types';
import type {
  ApiChain,
  ApiMarketAsset,
  ApiMarketAssetsResponse,
  ApiMarketAssetsResponseWithSlug,
} from '../types';

import { getIsSupportedChain } from '../../util/chain';
import { callBackendGet } from '../common/backend';
import { getSwapItemSlug } from '../common/swap';

/**
 * The catalogue also covers chains only swaps and the CEX providers use, and a card for one of them
 * opens a token screen that cannot resolve. Dropping them here is what narrows `chain` to
 * `ApiChain`, and it covers every platform, since all three read the market through this method.
 */
function enrichMarketResponse(response: ApiMarketAssetsResponse): ApiMarketAssetsResponseWithSlug {
  return {
    sections: response.sections
      .map((section) => ({
        ...section,
        assets: section.assets
          .filter((e): e is ApiMarketAsset & { chain: ApiChain } => getIsSupportedChain(e.chain))
          .map((e) => ({
            ...e,
            slug: getSwapItemSlug(e.newBackendId, e.chain),
          })),
      }))
      .filter((section) => section.assets.length > 0),
  };
}

export async function fetchMarketAssets(langCode?: LangCode): Promise<ApiMarketAssetsResponseWithSlug | undefined> {
  const response = await callBackendGet<ApiMarketAssetsResponse>(
    '/market/assets',
    langCode ? { langCode } : undefined,
  );

  return enrichMarketResponse(response);
}
