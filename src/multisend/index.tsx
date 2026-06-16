import '../global/actions/ui/shared';
import '../util/handleError';
import '../util/bigintPatch';

import React from '../lib/teact/teact';
import TeactDOM from '../lib/teact/teact-dom';
import { getActions, getGlobal } from '../global';

import {
  ANIMATION_LEVEL_DEFAULT,
  DEBUG,
  STRICTERDOM_ENABLED,
  THEME_DEFAULT,
} from './config';
import { requestMutation } from '../lib/fasterdom/fasterdom';
import { enableStrict } from '../lib/fasterdom/stricterdom';
import { betterView } from '../util/betterView';
import { forceLoadFonts } from '../util/fonts';
import { logSelfXssWarnings } from '../util/logs';
import switchTheme from '../util/switchTheme';
import { fetchKnownTokens } from './utils/tokens';
import { tonConnect } from './utils/tonConnect';

import App from './components/App';

import '../styles/index.scss';
import './index.scss';

if (DEBUG) {
  // eslint-disable-next-line no-console
  console.log('>>> INIT');
}

if (STRICTERDOM_ENABLED) {
  enableStrict();
}

void (async () => {
  const actions = getActions();
  actions.setAnimationLevel({ level: ANIMATION_LEVEL_DEFAULT });
  actions.setTheme({ theme: THEME_DEFAULT });
  switchTheme(THEME_DEFAULT);

  fetchKnownTokens().catch((error) => {
    // eslint-disable-next-line no-console
    console.error('Failed to initialize token loading:', error);
  });

  const walletInfoList = await tonConnect.getWallets();
  const mwWalletInfo = walletInfoList.find((walletInfo) => walletInfo.appName === 'mytonwallet');

  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.log('>>> START INITIAL RENDER');
  }

  requestMutation(() => {
    TeactDOM.render(
      <App mwWalletInfo={mwWalletInfo} />,
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
