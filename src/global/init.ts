import type { GlobalState } from './types';

import { cloneDeep } from '../util/iteratees';
import { IS_DELEGATED_BOTTOM_SHEET, IS_LEDGER_EXTENSION_TAB } from '../util/windowEnvironment';
import { initCache, loadCache } from './cache';
import { addActionHandler } from './index';
import { INITIAL_STATE } from './initialState';
import { selectHasSession } from './selectors';

if (!IS_DELEGATED_BOTTOM_SHEET) {
  initCache();
}

addActionHandler('init', (currentGlobal, actions) => {
  const initial = cloneDeep(INITIAL_STATE);

  // Do not do anything if we have already received initialized global state from main
  if (IS_DELEGATED_BOTTOM_SHEET && (currentGlobal as AnyLiteral).isInited !== false) {
    return currentGlobal;
  }

  const global = loadCache(initial);

  if (IS_DELEGATED_BOTTOM_SHEET) {
    return {
      ...initial,
      settings: {
        ...initial.settings,
        theme: global.settings.theme,
      },
      isInited: false,
    } as GlobalState & { isInited?: false };
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
