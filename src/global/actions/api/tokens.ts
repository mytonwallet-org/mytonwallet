import { logDebugError } from '../../../util/logs';
import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updateTokenNetWorthHistory, updateTokenPriceHistory } from '../../reducers/tokens';
import { selectCurrentAccount, selectCurrentAccountId } from '../../selectors';

addActionHandler('loadPriceHistory', async (global, actions, payload) => {
  const { slug, period, currency = global.settings.baseCurrency } = payload ?? {};

  const history = await callApi('fetchPriceHistory', slug, period, currency);

  if (!history) {
    return;
  }

  global = getGlobal();
  global = updateTokenPriceHistory(global, slug, { [period]: history });
  setGlobal(global);
});

addActionHandler('loadTokenNetWorthHistory', async (global, actions, payload) => {
  const {
    slug,
    period,
    currency = global.settings.baseCurrency,
  } = payload;

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
  setGlobal(updateTokenNetWorthHistory(global, currentAccountId, slug, { [period]: history }));
});
