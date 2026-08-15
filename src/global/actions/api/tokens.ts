import { logDebugError } from '../../../util/logs';
import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updateTokenDetails, updateTokenNetWorthHistory, updateTokenPriceHistory } from '../../reducers/tokens';
import { selectCurrentAccount, selectCurrentAccountId } from '../../selectors';

addActionHandler('loadPriceHistory', async (global, actions, payload) => {
  const { slug, period, currency = global.settings.baseCurrency } = payload ?? {};
  const { baseCurrency } = global.settings;

  const history = await callApi('fetchPriceHistory', slug, period, currency);

  if (!history) {
    return;
  }

  global = getGlobal();
  // The history is not stored per currency, and the chart asks for a new series on every currency
  // change, so a result awaited across such a change belongs to no longer shown prices
  if (global.settings.baseCurrency !== baseCurrency) {
    return;
  }

  global = updateTokenPriceHistory(global, slug, { [period]: history });
  setGlobal(global);
});

addActionHandler('loadTokenDetails', async (global, actions, { slug }) => {
  const result = await callApi('fetchTokenInfo', slug);

  global = getGlobal();
  setGlobal(updateTokenDetails(global, slug, !result || 'error' in result
    ? { hasError: true }
    : { data: result.details, hasError: undefined }));
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
