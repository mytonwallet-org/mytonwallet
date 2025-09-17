import '../global/actions/ui/shared';
import '../util/handleError';
import '../util/bigintPatch';

import React from '../lib/teact/teact';
import TeactDOM from '../lib/teact/teact-dom';
import { getActions, getGlobal } from '../global';

import type { LangCode } from '../global/types';

import { ANIMATION_LEVEL_DEFAULT, DEBUG, IS_TELEGRAM_APP, STRICTERDOM_ENABLED, THEME_DEFAULT } from '../config';
import { requestMutation } from '../lib/fasterdom/fasterdom';
import { enableStrict } from '../lib/fasterdom/stricterdom';
import { betterView } from '../util/betterView';
import { forceLoadFonts } from '../util/fonts';
import { setLanguage } from '../util/langProvider';
import { logSelfXssWarnings } from '../util/logs';
import switchTheme, { setStatusBarStyle } from '../util/switchTheme';
import { getTelegramApp, initTelegramApp } from '../util/telegram';
import { getSearchParameter } from './util/searchParams';
import { setEnvironment } from '../api/environment';

import App from './components/App';

import '../styles/index.scss';
import './styles/index.scss';

if (DEBUG) {
  // eslint-disable-next-line no-console
  console.log('>>> INIT');
}

if (IS_TELEGRAM_APP) {
  void initTelegramApp();

  document.documentElement.classList.add('force-transparent-bg');
  setStatusBarStyle();
  setTimeout(() => {
    requestMutation(() => {
      document.documentElement.classList.remove('force-transparent-bg');
    });
  }, 200);
}

setEnvironment({});

if (STRICTERDOM_ENABLED) {
  enableStrict();
}

void (() => {
  const actions = getActions();
  actions.setAnimationLevel({ level: ANIMATION_LEVEL_DEFAULT });
  actions.setTheme({ theme: THEME_DEFAULT });
  switchTheme(THEME_DEFAULT);

  const langCode = (
    getTelegramApp()?.initDataUnsafe.user?.language_code
    ?? getSearchParameter('langCode')
  );
  if (langCode) {
    void setLanguage(langCode as LangCode);
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
