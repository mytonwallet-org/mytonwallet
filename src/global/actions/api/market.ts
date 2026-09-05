import { areDeepEqual } from '../../../util/areDeepEqual';
import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';

let activeRequestId = 0;

addActionHandler('loadMarketAssets', async (global) => {
  const requestId = ++activeRequestId;
  const { langCode } = global.settings;
  const response = await callApi('fetchMarketAssets', langCode);

  // A newer request is on its way, so this response is out of date
  if (requestId !== activeRequestId) {
    return;
  }

  // The sections already on the screen are more useful than an empty list, so a failed request keeps them
  if (!response) {
    return;
  }

  const marketData = { ...response, langCode };

  global = getGlobal();
  if (areDeepEqual(marketData, global.marketData)) {
    return;
  }

  setGlobal({ ...global, marketData });
});
