import { AppState } from './types';

import { IS_AIR_APP, IS_CAPACITOR } from '../config';
import { switchToAir } from '../util/capacitor';
import { cloneDeep } from '../util/iteratees';
import { IS_LEDGER_EXTENSION_TAB } from '../util/windowEnvironment';
import { initCache, loadCache } from './cache';
import { addActionHandler } from './index';
import { INITIAL_STATE } from './initialState';
import { selectHasSession } from './selectors';

initCache();

addActionHandler('init', (currentGlobal, actions) => {
  const initial = cloneDeep(INITIAL_STATE);

  const global = loadCache(initial);

  if (
    IS_CAPACITOR && !IS_AIR_APP
    && global.settings.shouldAutoSwitchToAirOnNextStart
    && global.settings.hasOpenedAir !== true
  ) {
    void switchToAir();
    return {
      ...initial,
      ...global,
      appState: AppState.Empty,
    };
  }

  if (IS_LEDGER_EXTENSION_TAB) {
    actions.initLedgerPage();
    return {
      ...initial,
      settings: {
        ...initial.settings,
        theme: global.settings.theme,
      },
    };
  }

  if (selectHasSession(global)) {
    actions.afterSignIn();
  }

  return global;
});
