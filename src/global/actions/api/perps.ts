import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updatePerpsAssetChart, updatePerpsAssetDetail } from '../../reducers';
import { selectCurrentAccount, selectCurrentAccountId } from '../../selectors';

const detailRequests = new Map<string, number>();
const chartRequests = new Map<string, number>();

addActionHandler('loadPerpsAsset', async (global, _actions, { assetId }) => {
  const accountId = selectCurrentAccountId(global);
  const address = selectCurrentAccount(global)?.byChain.arbitrum?.address;
  if (!accountId || !address) return;

  const requestKey = `${accountId}:${assetId}`;
  const requestId = (detailRequests.get(requestKey) ?? 0) + 1;
  detailRequests.set(requestKey, requestId);

  const result = await callApi('perpsGetAsset', {
    address,
    asset: assetId,
    chain: 'hyperliquid',
  });

  if (detailRequests.get(requestKey) !== requestId) return;

  global = getGlobal();
  if (selectCurrentAccountId(global) !== accountId) return;

  setGlobal(updatePerpsAssetDetail(
    global,
    accountId,
    assetId,
    result
      ? { data: result, hasError: undefined, fetchedAt: Date.now() }
      : { hasError: true },
  ));
});

addActionHandler('loadPerpsAssetChart', async (global, _actions, { assetId, period }) => {
  const requestKey = `${assetId}:${period}`;
  const requestId = (chartRequests.get(requestKey) ?? 0) + 1;
  chartRequests.set(requestKey, requestId);

  const history = await callApi('perpsGetAssetChart', {
    asset: assetId,
    chain: 'hyperliquid',
    period,
  });

  if (chartRequests.get(requestKey) !== requestId) return;

  global = getGlobal();
  if (!history) {
    if (!global.perpsAssetChart?.byAssetId[assetId]?.[period]) {
      setGlobal(updatePerpsAssetChart(global, assetId, { [period]: [] }));
    }

    return;
  }

  setGlobal(updatePerpsAssetChart(global, assetId, { [period]: history }));
});
