import type { LangCode, TokenDetailsState } from '../../types';

import { getIsInBackground } from '../../../util/backgroundMode';
import { SECOND } from '../../../util/dateFormat';
import { logDebugError } from '../../../util/logs';
import { debounce } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { pickTokenDetailsSlugsToPreload } from '../../helpers/tokenDetails';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';
import { updateTokenDetails, updateTokenNetWorthHistory, updateTokenPriceHistory } from '../../reducers/tokens';
import { selectCurrentAccount, selectCurrentAccountId, selectCurrentAccountTokens } from '../../selectors';

type TokenDetailsRequest = { langCode: LangCode; startedAt: number };

// Balances and tokens arrive chain by chain, so the preload waits for the token list to settle
const TOKEN_DETAILS_PRELOAD_DEBOUNCE = 300;
// A live request ends within the 10-second backend timeout. An older one has lost its response: the iOS health check
// replaces a silent API worker without settling the requests sent to it.
const TOKEN_DETAILS_REQUEST_TIMEOUT = 30 * SECOND;

// The request that is loading the details of each slug right now
const pendingTokenDetailsRequests = new Map<string, TokenDetailsRequest>();

const preloadTokenDetailsDebounced = debounce(() => {
  // Price updates keep triggering the preload in the background. It waits instead, as `Main` preloads once the
  // wallet is focused again.
  if (getIsInBackground()) return;

  const global = getGlobal();
  const tokens = selectCurrentAccountTokens(global);
  if (!tokens) return;

  const slugs = pickTokenDetailsSlugsToPreload(
    tokens, global.tokenDetails.bySlug, global.settings.langCode, Date.now(),
  );
  if (slugs.length) getActions().loadTokenDetails({ slugs });
}, TOKEN_DETAILS_PRELOAD_DEBOUNCE, false);

addActionHandler('loadPriceHistory', async (global, actions, payload) => {
  const { slug, period, currency = global.settings.baseCurrency } = payload ?? {};
  const { baseCurrency } = global.settings;

  const history = await callApi('fetchPriceHistory', slug, period, currency);

  global = getGlobal();
  // The history is not stored per currency, and the chart asks for a new series on every currency
  // change, so a result awaited across such a change belongs to no longer shown prices
  if (global.settings.baseCurrency !== baseCurrency) {
    return;
  }

  if (!history) {
    // An empty series renders as "no data" while the chart keeps polling. Leaving the period
    // unset instead would keep the chart on the spinner it shows before the first result, which a
    // token whose history never loads would never leave. A series already shown survives the
    // failure and is replaced by the next successful poll.
    if (!global.tokenPriceHistory.bySlug[slug]?.[period]) {
      setGlobal(updateTokenPriceHistory(global, slug, { [period]: [] }));
    }

    return;
  }

  global = updateTokenPriceHistory(global, slug, { [period]: history.points }, { [period]: history.backfill });
  setGlobal(global);
});

addActionHandler('loadTokenDetails', async (global, actions, { slugs }) => {
  const request: TokenDetailsRequest = { langCode: global.settings.langCode, startedAt: Date.now() };
  // An opened token asks for its details while the preload may already be requesting them
  const requestedSlugs = slugs.filter((slug) => !getIsCoveredByPendingRequest(slug, request));
  if (!requestedSlugs.length) return;

  requestedSlugs.forEach((slug) => pendingTokenDetailsRequests.set(slug, request));
  const result = await callApi('fetchTokenInfo', requestedSlugs);

  // A newer request takes a slug over after a language change, a timeout or an API reconnect. A late response to this
  // one then leaves both the marker and the details of that slug to the newer request.
  const ownSlugs = requestedSlugs.filter((slug) => pendingTokenDetailsRequests.get(slug) === request);
  ownSlugs.forEach((slug) => pendingTokenDetailsRequests.delete(slug));
  if (!ownSlugs.length) return;

  global = getGlobal();
  // The language may change while the request is in flight. A response in the previous language would overwrite the
  // details already loaded in the new one.
  if (global.settings.langCode !== request.langCode) return;

  const fetchedAt = Date.now();
  const partialBySlug: Record<string, TokenDetailsState> = {};
  for (const slug of ownSlugs) {
    partialBySlug[slug] = !result || 'error' in result
      ? { hasError: true }
      : { data: result.detailsBySlug[slug], hasError: undefined, langCode: request.langCode, fetchedAt };
  }

  setGlobal(updateTokenDetails(global, partialBySlug));
});

addActionHandler('initApi', () => {
  // A new API worker never answers the requests sent to the one it replaces
  pendingTokenDetailsRequests.clear();
});

addActionHandler('preloadTokenDetails', () => {
  preloadTokenDetailsDebounced();
});

addActionHandler('loadTokenNetWorthHistory', async (global, actions, payload) => {
  const {
    slug,
    period,
    currency = global.settings.baseCurrency,
  } = payload;
  const { baseCurrency } = global.settings;

  const token = global.tokenInfo.bySlug[slug];
  const currentAccount = selectCurrentAccount(global);
  const currentAccountId = selectCurrentAccountId(global);
  const accountAddress = currentAccount?.byChain?.[token?.chain]?.address;
  if (!accountAddress || !currentAccountId || !token) {
    return;
  }

  const assetId = token.tokenAddress ?? token.slug;

  let history = await callApi('fetchTokenNetWorthHistory', accountAddress, assetId, period, currency);
  if (!history || 'error' in history) {
    if (history && 'error' in history) {
      logDebugError('loadTokenNetWorthHistory', history.error);
    }
    history = [];
  }

  global = getGlobal();
  if (global.settings.baseCurrency !== baseCurrency) {
    return;
  }

  setGlobal(updateTokenNetWorthHistory(global, currentAccountId, slug, { [period]: history }));
});

function getIsCoveredByPendingRequest(slug: string, request: TokenDetailsRequest) {
  const pending = pendingTokenDetailsRequests.get(slug);

  return pending?.langCode === request.langCode
    && request.startedAt - pending.startedAt < TOKEN_DETAILS_REQUEST_TIMEOUT;
}
