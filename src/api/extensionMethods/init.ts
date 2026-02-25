import type { OnApiUpdate } from '../types';

import { addHooks } from '../hooks';
import * as siteMethods from './sites';
import { openPopupWindow } from './window';
import * as extensionMethods from '.';

addHooks({
  onWindowNeeded: openPopupWindow,
  onFullLogout: extensionMethods.onFullLogout,
  onDappDisconnected: (_, dapp) => {
    siteMethods.updateSites({
      type: 'disconnectSite',
      url: dapp.url,
    });
  },
});

export default function init(onUpdate: OnApiUpdate) {
  void extensionMethods.initExtension();
  siteMethods.initSiteMethods(onUpdate);
}
