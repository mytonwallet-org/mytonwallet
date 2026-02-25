import { ACTIVE_TAB_STORAGE_KEY, IS_EXPLORER, IS_TELEGRAM_APP } from '../config';
import { IS_ELECTRON, IS_LEDGER_EXTENSION_TAB } from './windowEnvironment';

const IS_DISABLED = IS_LEDGER_EXTENSION_TAB || IS_ELECTRON || IS_TELEGRAM_APP || IS_EXPLORER;

const INTERVAL = 2000;

const tabKey = String(Date.now() + Math.random());

if (!IS_DISABLED) {
  localStorage.setItem(ACTIVE_TAB_STORAGE_KEY, tabKey);
}

let callback: NoneToVoidFunction;

const interval = window.setInterval(() => {
  if (!IS_DISABLED && callback && localStorage.getItem(ACTIVE_TAB_STORAGE_KEY) !== tabKey) {
    callback();
    clearInterval(interval);
  }
}, INTERVAL);

export function setActiveTabChangeListener(_callback: NoneToVoidFunction) {
  callback = _callback;
}
