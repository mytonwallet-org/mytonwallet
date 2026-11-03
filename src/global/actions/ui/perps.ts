import { DEFAULT_PRICE_HISTORY_PERIOD } from '../../../util/priceHistory';
import { addActionHandler } from '../../index';
import { updateCurrentAccountState } from '../../reducers';
import { selectCurrentAccountState } from '../../selectors';

addActionHandler('openPerpsAsset', (global, _actions, { assetId }) => {
  const period = selectCurrentAccountState(global)?.currentPerpsAssetPeriod ?? DEFAULT_PRICE_HISTORY_PERIOD;

  return updateCurrentAccountState(global, {
    currentPerpsAssetId: assetId,
    currentPerpsAssetPeriod: period,
  });
});

addActionHandler('closePerpsAsset', (global) => {
  return updateCurrentAccountState(global, {
    currentPerpsAssetId: undefined,
  });
});

addActionHandler('setCurrentPerpsAssetPeriod', (global, _actions, { period }) => {
  return updateCurrentAccountState(global, {
    currentPerpsAssetPeriod: period,
  });
});
