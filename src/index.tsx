import './global/actions';
import './global/init';
import './util/handleError';
import './util/bigintPatch';

import React from './lib/teact/teact';
import TeactDOM from './lib/teact/teact-dom';
import { getActions, getGlobal } from './global';

import {
  DEBUG, IS_CAPACITOR, IS_TELEGRAM_APP, STRICTERDOM_ENABLED,
} from './config';
import { requestMutation } from './lib/fasterdom/fasterdom';
import { enableStrict } from './lib/fasterdom/stricterdom';
import { betterView } from './util/betterView';
import { fixIosAppStorage, initCapacitor, processCapacitorLaunchDeeplink } from './util/capacitor';
import { initElectron } from './util/electron';
import { initFocusScrollController } from './util/focusScroll';
import { forceLoadFonts } from './util/fonts';
import { logDebug, logSelfXssWarnings } from './util/logs';
import { initMultitab } from './util/multitab';
import { initTelegramApp } from './util/telegram';
import {
  IS_DELEGATED_BOTTOM_SHEET, IS_DELEGATING_BOTTOM_SHEET, IS_ELECTRON, IS_IOS_APP, IS_LEDGER_EXTENSION_TAB,
} from './util/windowEnvironment';

import App from './components/App';

import './styles/index.scss';

if (DEBUG) {
  // eslint-disable-next-line no-console
  console.log('>>> INIT');
}

if (STRICTERDOM_ENABLED) {
  enableStrict();
}

if (IS_CAPACITOR) {
  void initCapacitor();
}

if (IS_ELECTRON) {
  void initElectron();
}

if (IS_TELEGRAM_APP) {
  void initTelegramApp();
}

if (IS_DELEGATING_BOTTOM_SHEET) {
  initMultitab({ noPubGlobal: true });
} else if (IS_DELEGATED_BOTTOM_SHEET) {
  initMultitab();
}

initFocusScrollController();

void (async () => {
  if (IS_IOS_APP) {
    await fixIosAppStorage();
  }

  await window.electron?.restoreStorage();

  getActions().init();

  // Connecting to the API from remote tabs creates excessive polling in the API.
  // The remote tab doesn't need the API anyway.
  if (!IS_LEDGER_EXTENSION_TAB) {
    getActions().initApi();
  } else {
    logDebug('API was not initialized because it was connected from a detached tab');
  }

  if (IS_CAPACITOR) {
    await processCapacitorLaunchDeeplink();
  }

  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.log('>>> START INITIAL RENDER');
  }

  requestMutation(() => {
    TeactDOM.render(
      <App />,
      document.getElementById('root')!,
    );

    forceLoadFonts();
    betterView();
  });

  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.log('>>> FINISH INITIAL RENDER');
  }

  document.addEventListener('dblclick', () => {
    // eslint-disable-next-line no-console
    console.warn('GLOBAL STATE', getGlobal());
  });

  if (window.top === window) {
    logSelfXssWarnings();
  }
})();
