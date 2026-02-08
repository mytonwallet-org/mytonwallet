import { cloneDeep } from '../util/iteratees';
import { IS_DELEGATED_BOTTOM_SHEET, IS_LEDGER_EXTENSION_TAB } from '../util/windowEnvironment';
import { initCache, loadCache } from './cache';
import { addActionHandler } from './index';
import { INITIAL_STATE } from './initialState';
import { selectHasSession } from './selectors';

if (!IS_DELEGATED_BOTTOM_SHEET) {
  initCache();
}

addActionHandler('init', (_, actions) => {
  const initial = cloneDeep(INITIAL_STATE);

  const global = loadCache(initial);

  if (IS_DELEGATED_BOTTOM_SHEET) {
    return {
      ...initial,
      settings: {
        ...initial.settings,
        theme: global.settings.theme,
      },
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
