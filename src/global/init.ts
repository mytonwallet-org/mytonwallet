import { IS_EXPLORER } from '../config';
import { cloneDeep } from '../util/iteratees';
import { IS_LEDGER_EXTENSION_TAB } from '../util/windowEnvironment';
import { openFirstNavigationTab } from './reducers/misc';
import { initCache, loadCache } from './cache';
import { addActionHandler } from './index';
import { INITIAL_STATE } from './initialState';
import { selectHasSession } from './selectors';

initCache();

addActionHandler('init', (currentGlobal, actions) => {
  const initial = cloneDeep(INITIAL_STATE);

  const global = loadCache(initial);

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

  if (!selectHasSession(global)) return global;

  actions.afterSignIn();

  // The app opens on the first navigation tab of the user's order, as the native apps do. A deeplink processed after
  // the start opens its own screen over it, and the explorer shows the wallet its link names
  return IS_EXPLORER ? global : openFirstNavigationTab(global);
});
